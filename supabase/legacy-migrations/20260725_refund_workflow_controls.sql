-- Refund workflow controls for customer payments.
-- Adds auditable refund metadata and admin/finance RPCs.

alter table public.payments
  add column if not exists refund_amount numeric,
  add column if not exists refund_reason text,
  add column if not exists refund_method text,
  add column if not exists refund_reference text,
  add column if not exists refund_requested_by uuid references auth.users(id) on delete set null,
  add column if not exists refund_requested_at timestamptz,
  add column if not exists refund_approved_by uuid references auth.users(id) on delete set null,
  add column if not exists refund_approved_at timestamptz,
  add column if not exists refund_completed_by uuid references auth.users(id) on delete set null,
  add column if not exists refund_completed_at timestamptz;

create index if not exists payments_refund_status_idx
on public.payments(status, refund_requested_at desc)
where status in ('refund_pending', 'refund_approved', 'refunded');

create or replace function public.can_approve_refunds()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.is_admin() or public.has_staff_permission('approve_refunds');
$$;

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
  values (
    auth.uid(),
    'payment.refund_approved',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'refund_amount', v_payment.refund_amount,
      'currency', v_payment.currency,
      'note', nullif(trim(coalesce(p_note, '')), '')
    )
  );

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
  set status = 'refunded',
      refund_method = nullif(trim(p_refund_method), ''),
      refund_reference = nullif(trim(coalesce(p_refund_reference, '')), ''),
      refund_completed_by = auth.uid(),
      refund_completed_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings
    set payment_status = 'refunded',
        updated_at = now()
    where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment.refund_completed',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'refund_amount', v_payment.refund_amount,
      'currency', v_payment.currency,
      'method', nullif(trim(p_refund_method), ''),
      'reference', nullif(trim(coalesce(p_refund_reference, '')), ''),
      'note', nullif(trim(coalesce(p_note, '')), '')
    )
  );

  return p_payment_id;
end;
$$;

create or replace function public.list_operations_payments(limit_count integer default 200)
returns table(
  id uuid,
  booking_id uuid,
  enquiry_id uuid,
  customer_id uuid,
  corporate_account_id uuid,
  booking_reference text,
  booking_title text,
  customer_name text,
  corporate_company_name text,
  service_type text,
  payment_reference text,
  payment_direction text,
  amount numeric,
  currency text,
  method text,
  status text,
  payment_link text,
  has_proof boolean,
  proof_file_name text,
  proof_uploaded_at timestamptz,
  receipt_document_id uuid,
  refund_amount numeric,
  refund_reason text,
  refund_method text,
  refund_reference text,
  refund_requested_at timestamptz,
  refund_approved_at timestamptz,
  refund_completed_at timestamptz,
  received_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    p.id,
    p.booking_id,
    p.enquiry_id,
    p.customer_id,
    p.corporate_account_id,
    b.booking_reference,
    b.title as booking_title,
    null::text as customer_name,
    ca.company_name as corporate_company_name,
    b.service_type::text as service_type,
    p.payment_reference,
    p.payment_direction,
    p.amount,
    p.currency,
    p.method,
    p.status,
    p.payment_link,
    (p.proof_storage_path is not null) as has_proof,
    p.proof_file_name,
    p.proof_uploaded_at,
    p.receipt_document_id,
    p.refund_amount,
    p.refund_reason,
    p.refund_method,
    p.refund_reference,
    p.refund_requested_at,
    p.refund_approved_at,
    p.refund_completed_at,
    p.received_at,
    p.created_at,
    p.updated_at
  from public.payments p
  left join public.bookings b on b.id = p.booking_id
  left join public.corporate_accounts ca on ca.id = p.corporate_account_id
  where public.has_staff_permission('view_payments')
  order by p.created_at desc
  limit greatest(1, least(limit_count, 500));
$$;

revoke execute on function public.can_approve_refunds() from public;
revoke execute on function public.can_approve_refunds() from anon;
grant execute on function public.can_approve_refunds() to authenticated, service_role;

revoke execute on function public.request_payment_refund(uuid, numeric, text) from public;
revoke execute on function public.request_payment_refund(uuid, numeric, text) from anon;
grant execute on function public.request_payment_refund(uuid, numeric, text) to authenticated, service_role;

revoke execute on function public.approve_payment_refund(uuid, text) from public;
revoke execute on function public.approve_payment_refund(uuid, text) from anon;
grant execute on function public.approve_payment_refund(uuid, text) to authenticated, service_role;

revoke execute on function public.complete_payment_refund(uuid, text, text, text) from public;
revoke execute on function public.complete_payment_refund(uuid, text, text, text) from anon;
grant execute on function public.complete_payment_refund(uuid, text, text, text) to authenticated, service_role;

revoke execute on function public.list_operations_payments(integer) from public;
revoke execute on function public.list_operations_payments(integer) from anon;
grant execute on function public.list_operations_payments(integer) to authenticated, service_role;
