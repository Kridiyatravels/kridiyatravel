-- Stage 3: verify the exact proof-bearing payment instead of recording a detached payment row.
alter table public.payments
  add column if not exists proof_verified_by uuid references auth.users(id) on delete set null,
  add column if not exists proof_verified_at timestamptz;

-- Payment state changes must use audited RPCs. Staff retain SELECT access only.
revoke insert, update, delete on public.payments from anon, authenticated;
drop policy if exists payments_insert_staff on public.payments;
drop policy if exists payments_update_staff on public.payments;

create or replace function public.verify_customer_payment_proof(
  p_payment_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := (select auth.uid());
  v_payment public.payments%rowtype;
  v_selling_price numeric;
  v_received_total numeric;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  if not public.has_staff_permission('edit_payments') then raise exception 'Payment verification permission required'; end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in'
  for update;
  if not found then raise exception 'Customer payment not found'; end if;
  if v_payment.proof_storage_path is null or v_payment.proof_uploaded_at is null then
    raise exception 'No payment proof is attached';
  end if;
  if v_payment.status <> 'proof_received' then raise exception 'Only received proof can be verified'; end if;
  if v_payment.proof_uploaded_by = v_actor then
    raise exception 'Payment proof must be verified by a different authorized person';
  end if;

  update public.payments
  set status = 'received',
      received_at = now(),
      proof_verified_by = v_actor,
      proof_verified_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    select selling_price into v_selling_price from public.bookings where id = v_payment.booking_id for update;
    select coalesce(sum(amount), 0) into v_received_total
    from public.payments
    where booking_id = v_payment.booking_id
      and payment_direction = 'customer_in'
      and status = 'received';
    update public.bookings
    set payment_status = case
          when coalesce(v_selling_price, 0) > 0 and v_received_total < v_selling_price then 'partially_paid'
          else 'paid'
        end,
        updated_at = now()
    where id = v_payment.booking_id;
  end if;

  update public.tasks_reminders
  set status = 'done', completed_at = now(), updated_at = now()
  where entity_type = 'payment' and entity_id = p_payment_id
    and status in ('open', 'snoozed')
    and (automation_key like 'customer-proof:%' or task_type = 'payment_reminder');

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_actor, 'payment.proof_verified', 'payment', p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'amount', v_payment.amount,
      'currency', v_payment.currency,
      'proof_uploaded_by', v_payment.proof_uploaded_by,
      'proof_uploaded_at', v_payment.proof_uploaded_at,
      'note', nullif(trim(coalesce(p_note, '')), '')
    ));
  return p_payment_id;
end;
$$;

revoke execute on function public.verify_customer_payment_proof(uuid, text) from public, anon;
grant execute on function public.verify_customer_payment_proof(uuid, text) to authenticated, service_role;

