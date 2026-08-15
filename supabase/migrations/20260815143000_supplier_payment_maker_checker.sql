-- Separate supplier payable creation from payment release.
alter table public.supplier_payments
  add column if not exists payment_approved_by uuid references auth.users(id),
  add column if not exists payment_approved_at timestamptz,
  add column if not exists disbursement_reference text;

drop policy if exists supplier_payments_insert_staff on public.supplier_payments;
drop policy if exists supplier_payments_update_staff on public.supplier_payments;
revoke insert, update, delete on table public.supplier_payments from anon, authenticated;

create or replace function public.record_supplier_payment(
  p_booking_id uuid,
  p_supplier_name text,
  p_amount_payable numeric,
  p_amount_paid numeric default 0,
  p_status text default 'pending'::text,
  p_currency text default 'AED'::text,
  p_supplier_reference text default null::text,
  p_due_date date default null::date,
  p_notes text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_supplier_payment_id uuid;
  v_booking_ref text;
  v_effective_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_staff_permission('edit_payments') then raise exception 'Permission denied'; end if;
  if nullif(trim(coalesce(p_supplier_name, '')), '') is null then raise exception 'Supplier name is required'; end if;
  if p_amount_payable is null or p_amount_payable <= 0 then raise exception 'Supplier payable amount must be greater than zero'; end if;
  if coalesce(p_amount_paid, 0) <> 0 or coalesce(p_status, 'pending') in ('partial', 'paid') then
    raise exception 'Record the payable first; an owner or admin must release supplier payment separately';
  end if;

  select booking_reference into v_booking_ref
  from public.bookings where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then raise exception 'Booking not found'; end if;

  v_effective_status := case when p_status in ('disputed', 'cancelled') then p_status else 'pending' end;
  insert into public.supplier_payments (
    booking_id, supplier_name, supplier_reference, amount_payable, amount_paid,
    currency, due_date, paid_at, status, notes, created_by
  ) values (
    p_booking_id, trim(p_supplier_name), nullif(trim(coalesce(p_supplier_reference, '')), ''),
    p_amount_payable, 0, upper(coalesce(p_currency, 'AED')), p_due_date, null,
    v_effective_status, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_supplier_payment_id;

  update public.bookings
  set supplier_name = trim(p_supplier_name),
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      supplier_cost = p_amount_payable,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'supplier_payment.recorded', 'supplier_payment', v_supplier_payment_id,
    jsonb_build_object('booking_reference', v_booking_ref, 'supplier_name', trim(p_supplier_name),
      'amount_payable', p_amount_payable, 'amount_paid', 0, 'status', v_effective_status));
  return v_supplier_payment_id;
end;
$function$;

create or replace function public.approve_supplier_payment(
  p_supplier_payment_id uuid,
  p_amount numeric,
  p_reference text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.supplier_payments%rowtype;
  v_new_paid numeric;
  v_new_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  if not public.is_admin() then raise exception 'Owner or admin approval required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  if nullif(trim(coalesce(p_reference, '')), '') is null then raise exception 'Transaction reference is required'; end if;

  select * into v_row from public.supplier_payments
  where id = p_supplier_payment_id for update;
  if not found then raise exception 'Supplier payment not found'; end if;
  if v_row.status not in ('pending', 'partial') then raise exception 'Only pending or partial supplier payments can be released'; end if;
  if v_row.created_by = auth.uid() then raise exception 'The payable creator cannot approve its payment'; end if;

  v_new_paid := coalesce(v_row.amount_paid, 0) + p_amount;
  if v_new_paid > v_row.amount_payable then raise exception 'Cumulative paid amount cannot exceed payable amount'; end if;
  v_new_status := case when v_new_paid = v_row.amount_payable then 'paid' else 'partial' end;

  update public.supplier_payments
  set amount_paid = v_new_paid,
      status = v_new_status,
      paid_at = case when v_new_status = 'paid' then now() else paid_at end,
      payment_approved_by = auth.uid(),
      payment_approved_at = now(),
      disbursement_reference = trim(p_reference),
      notes = case when nullif(trim(coalesce(p_note, '')), '') is null then notes
                   when notes is null then trim(p_note) else notes || E'\n' || trim(p_note) end,
      updated_at = now()
  where id = p_supplier_payment_id;

  if v_new_status = 'paid' then
    update public.bookings set payment_status = 'supplier_paid', updated_at = now()
    where id = v_row.booking_id;
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'supplier_payment.approved', 'supplier_payment', p_supplier_payment_id,
    jsonb_build_object('maker_user_id', v_row.created_by, 'approved_amount', p_amount,
      'previous_paid', coalesce(v_row.amount_paid, 0), 'cumulative_paid', v_new_paid,
      'amount_payable', v_row.amount_payable, 'status', v_new_status,
      'disbursement_reference', trim(p_reference)));

  return jsonb_build_object('id', p_supplier_payment_id, 'amount_paid', v_new_paid,
    'amount_payable', v_row.amount_payable, 'status', v_new_status);
end;
$function$;

revoke execute on function public.record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text) from public, anon;
grant execute on function public.record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text) to authenticated, service_role;
revoke execute on function public.approve_supplier_payment(uuid,numeric,text,text) from public, anon;
grant execute on function public.approve_supplier_payment(uuid,numeric,text,text) to authenticated, service_role;
