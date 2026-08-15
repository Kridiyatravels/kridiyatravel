-- Derive the booking payment state from cumulative cleared customer payments.
-- A single partial receipt must not mark the full booking as paid.
create or replace function public.record_customer_payment(
  p_booking_id uuid,
  p_amount numeric,
  p_method text,
  p_status text default 'received'::text,
  p_currency text default 'AED'::text,
  p_payment_link text default null::text,
  p_notes text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment_id uuid;
  v_ref text;
  v_booking_ref text;
  v_selling_price numeric;
  v_received_total numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  select booking_reference, selling_price
  into v_booking_ref, v_selling_price
  from public.bookings
  where id = p_booking_id and archived_at is null;

  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  v_ref := public.next_payment_reference();

  insert into public.payments (
    booking_id,
    payment_reference,
    amount,
    currency,
    method,
    status,
    payment_link,
    notes,
    received_at,
    created_by
  ) values (
    p_booking_id,
    v_ref,
    p_amount,
    upper(coalesce(p_currency, 'AED')),
    p_method,
    p_status,
    nullif(trim(coalesce(p_payment_link, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_status = 'received' then now() else null end,
    auth.uid()
  ) returning id into v_payment_id;

  if p_status = 'received' then
    select coalesce(sum(amount), 0)
    into v_received_total
    from public.payments
    where booking_id = p_booking_id
      and payment_direction = 'customer_in'
      and status = 'received';
  end if;

  update public.bookings
  set payment_status = case
        when p_status = 'received'
          and coalesce(v_selling_price, 0) > 0
          and v_received_total < v_selling_price then 'partially_paid'
        when p_status = 'received' then 'paid'
        when p_status = 'proof_received' then 'proof_received'
        else payment_status
      end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment.recorded',
    'payment',
    v_payment_id,
    jsonb_build_object(
      'booking_reference', v_booking_ref,
      'payment_reference', v_ref,
      'amount', p_amount,
      'method', p_method,
      'status', p_status,
      'received_total', v_received_total,
      'selling_price', v_selling_price
    )
  );

  return v_payment_id;
end;
$function$;

revoke execute on function public.record_customer_payment(uuid,numeric,text,text,text,text,text)
  from public, anon;
grant execute on function public.record_customer_payment(uuid,numeric,text,text,text,text,text)
  to authenticated, service_role;
