-- Stage 3: enforce refund maker-checker separation and mandatory approval.
create or replace function public.approve_payment_refund_internal_20260815(
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
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if not public.can_approve_refunds() then raise exception 'Refund approval permission required'; end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in'
  for update;
  if not found then raise exception 'Customer payment not found'; end if;
  if v_payment.status <> 'refund_pending' then raise exception 'Only pending refunds can be approved'; end if;
  if v_payment.refund_requested_by is null then raise exception 'Refund request has no accountable requester'; end if;
  if v_payment.refund_requested_by = v_actor then
    raise exception 'A refund must be approved by a different authorized person';
  end if;

  update public.payments
  set status = 'refund_approved',
      refund_approved_by = v_actor,
      refund_approved_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_actor, 'payment.refund_approved', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference,
      'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency,
      'requested_by', v_payment.refund_requested_by, 'note', nullif(trim(coalesce(p_note, '')), '')));
  return p_payment_id;
end;
$$;

create or replace function public.complete_payment_refund_internal_20260815(
  p_payment_id uuid,
  p_refund_method text,
  p_refund_reference text default null,
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
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if not public.can_approve_refunds() then raise exception 'Refund completion permission required'; end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in'
  for update;
  if not found then raise exception 'Customer payment not found'; end if;
  if v_payment.status <> 'refund_approved' then raise exception 'Refund approval is required before completion'; end if;
  if v_payment.refund_approved_by is null or v_payment.refund_approved_at is null then
    raise exception 'Refund approval evidence is incomplete';
  end if;
  if v_payment.refund_requested_by = v_actor then
    raise exception 'The refund requester cannot complete the refund';
  end if;
  if nullif(trim(coalesce(p_refund_method, '')), '') is null then raise exception 'Refund method is required'; end if;

  update public.payments
  set status = 'refunded',
      refund_method = nullif(trim(p_refund_method), ''),
      refund_reference = nullif(trim(coalesce(p_refund_reference, '')), ''),
      refund_completed_by = v_actor,
      refund_completed_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings set payment_status = 'refunded', updated_at = now() where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_actor, 'payment.refund_completed', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference,
      'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency,
      'requested_by', v_payment.refund_requested_by, 'approved_by', v_payment.refund_approved_by,
      'method', nullif(trim(p_refund_method), ''),
      'reference', nullif(trim(coalesce(p_refund_reference, '')), ''),
      'note', nullif(trim(coalesce(p_note, '')), '')));
  return p_payment_id;
end;
$$;

revoke execute on function public.approve_payment_refund_internal_20260815(uuid, text) from public, anon, authenticated;
revoke execute on function public.complete_payment_refund_internal_20260815(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.approve_payment_refund_internal_20260815(uuid, text) to postgres, service_role;
grant execute on function public.complete_payment_refund_internal_20260815(uuid, text, text, text) to postgres, service_role;

