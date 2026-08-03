create or replace function public.request_payment_refund(
  p_payment_id uuid,
  p_refund_amount numeric default null,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  if not (public.has_staff_permission('edit_payments') or public.can_approve_refunds()) then
    raise exception 'Refund request permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if coalesce(p_refund_amount, v_payment.amount) <= 0 then
    raise exception 'Refund amount must be greater than zero';
  end if;

  update public.payments
  set status = 'refund_pending',
      refund_amount = coalesce(p_refund_amount, v_payment.amount),
      refund_reason = nullif(trim(coalesce(p_reason, '')), ''),
      refund_requested_by = auth.uid(),
      refund_requested_at = now(),
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings
    set payment_status = 'refund_pending',
        updated_at = now()
    where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment.refund_requested',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'refund_amount', coalesce(p_refund_amount, v_payment.amount),
      'currency', v_payment.currency,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );

  return p_payment_id;
end;
$$;

revoke execute on function public.request_payment_refund(uuid, numeric, text) from public;
revoke execute on function public.request_payment_refund(uuid, numeric, text) from anon;
grant execute on function public.request_payment_refund(uuid, numeric, text) to authenticated, service_role;
