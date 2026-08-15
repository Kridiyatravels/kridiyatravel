-- Repair contradictory supplier payment states using financial evidence.
update public.supplier_payments
set status = case when amount_paid > 0 then 'partial' else 'pending' end,
    paid_at = null,
    updated_at = now()
where status = 'paid'
  and amount_paid < amount_payable;

with customer_totals as (
  select
    b.id as booking_id,
    coalesce(sum(p.amount) filter (
      where p.payment_direction = 'customer_in' and p.status = 'received'
    ), 0) as received_total
  from public.bookings b
  left join public.payments p on p.booking_id = b.id
  group by b.id
)
update public.bookings b
set payment_status = case
      when totals.received_total > 0
        and totals.received_total < coalesce(b.selling_price, b.amount, 0)
        then 'partially_paid'
      when totals.received_total > 0 then 'paid'
      else 'not_requested'
    end,
    updated_at = now()
from customer_totals totals
where b.payment_status = 'supplier_paid'
  and totals.booking_id = b.id
  and not exists (
    select 1
    from public.supplier_payments sp
    where sp.booking_id = b.id
      and sp.status = 'paid'
      and sp.amount_paid >= sp.amount_payable
  );

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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;
  if nullif(trim(coalesce(p_supplier_name, '')), '') is null then
    raise exception 'Supplier name is required';
  end if;
  if p_amount_payable is null or p_amount_payable <= 0 then
    raise exception 'Supplier payable amount must be greater than zero';
  end if;
  if coalesce(p_amount_paid, 0) < 0 then
    raise exception 'Supplier paid amount cannot be negative';
  end if;
  if coalesce(p_amount_paid, 0) > p_amount_payable then
    raise exception 'Supplier paid amount cannot exceed payable amount';
  end if;

  select booking_reference into v_booking_ref
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  v_effective_status := case
    when p_status in ('disputed', 'cancelled') then p_status
    when coalesce(p_amount_paid, 0) = 0 then 'pending'
    when p_amount_paid < p_amount_payable then 'partial'
    else 'paid'
  end;

  insert into public.supplier_payments (
    booking_id, supplier_name, supplier_reference, amount_payable,
    amount_paid, currency, due_date, paid_at, status, notes, created_by
  ) values (
    p_booking_id,
    trim(p_supplier_name),
    nullif(trim(coalesce(p_supplier_reference, '')), ''),
    p_amount_payable,
    coalesce(p_amount_paid, 0),
    upper(coalesce(p_currency, 'AED')),
    p_due_date,
    case when v_effective_status = 'paid' then now() else null end,
    v_effective_status,
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
  ) returning id into v_supplier_payment_id;

  update public.bookings
  set supplier_name = trim(p_supplier_name),
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      supplier_cost = p_amount_payable,
      payment_status = case
        when v_effective_status = 'paid' then 'supplier_paid'
        else payment_status
      end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(),
    'supplier_payment.recorded',
    'supplier_payment',
    v_supplier_payment_id,
    jsonb_build_object(
      'booking_reference', v_booking_ref,
      'supplier_name', p_supplier_name,
      'amount_payable', p_amount_payable,
      'amount_paid', coalesce(p_amount_paid, 0),
      'requested_status', p_status,
      'status', v_effective_status
    )
  );

  return v_supplier_payment_id;
end;
$function$;

revoke execute on function public.record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text)
  from public, anon;
grant execute on function public.record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text)
  to authenticated, service_role;
