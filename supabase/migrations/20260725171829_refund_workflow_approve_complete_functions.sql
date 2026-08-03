create or replace function public.approve_payment_refund(
  p_payment_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  if not public.can_approve_refunds() then
    raise exception 'Refund approval permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if v_payment.status <> 'refund_pending' then
    raise exception 'Only pending refunds can be approved';
  end if;

  update public.payments
  set status = 'refund_approved',
      refund_approved_by = auth.uid(),
      refund_approved_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.refund_approved', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference, 'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency, 'note', nullif(trim(coalesce(p_note, '')), '')));

  return p_payment_id;
end;
$$;

create or replace function public.complete_payment_refund(
  p_payment_id uuid,
  p_refund_method text,
  p_refund_reference text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  if not public.can_approve_refunds() then
    raise exception 'Refund completion permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if v_payment.status not in ('refund_pending', 'refund_approved') then
    raise exception 'Only pending or approved refunds can be completed';
  end if;

  if nullif(trim(coalesce(p_refund_method, '')), '') is null then
    raise exception 'Refund method is required';
  end if;

  update public.payments
  set status = 'refunded', refund_method = nullif(trim(p_refund_method), ''), refund_reference = nullif(trim(coalesce(p_refund_reference, '')), ''), refund_completed_by = auth.uid(), refund_completed_at = now(), notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))), updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings set payment_status = 'refunded', updated_at = now() where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.refund_completed', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference, 'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency, 'method', nullif(trim(p_refund_method), ''), 'reference', nullif(trim(coalesce(p_refund_reference, '')), ''), 'note', nullif(trim(coalesce(p_note, '')), '')));

  return p_payment_id;
end;
$$;

revoke execute on function public.approve_payment_refund(uuid, text) from public;
revoke execute on function public.approve_payment_refund(uuid, text) from anon;
grant execute on function public.approve_payment_refund(uuid, text) to authenticated, service_role;

revoke execute on function public.complete_payment_refund(uuid, text, text, text) from public;
revoke execute on function public.complete_payment_refund(uuid, text, text, text) from anon;
grant execute on function public.complete_payment_refund(uuid, text, text, text) to authenticated, service_role;
