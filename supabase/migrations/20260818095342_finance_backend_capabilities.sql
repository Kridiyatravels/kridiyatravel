-- Finance operations read APIs and refund rejection workflow.
--
-- This migration keeps table access private. Every exposed function is a
-- SECURITY DEFINER RPC with an explicit authenticated staff-permission gate.

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
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('view_payments') then
    raise exception 'Payment view permission required';
  end if;

  return query
  select
    p.id,
    p.booking_id,
    p.enquiry_id,
    coalesce(p.customer_id, b.customer_id) as customer_id,
    coalesce(p.corporate_account_id, b.corporate_account_id) as corporate_account_id,
    b.booking_reference,
    b.title as booking_title,
    c.full_name as customer_name,
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
  left join public.customers c on c.id = coalesce(p.customer_id, b.customer_id)
  left join public.corporate_accounts ca on ca.id = coalesce(p.corporate_account_id, b.corporate_account_id)
  order by p.created_at desc, p.id desc
  limit greatest(1, least(coalesce(limit_count, 200), 500));
end;
$function$;

comment on function public.list_operations_payments(integer) is
  'Permission-gated global customer-payment list with individual and corporate customer names.';

revoke execute on function public.list_operations_payments(integer) from public, anon;
grant execute on function public.list_operations_payments(integer) to authenticated, service_role;


create or replace function public.list_operations_supplier_payments(
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_search text default null,
  limit_count integer default 200
)
returns table(
  id uuid,
  booking_id uuid,
  booking_reference text,
  booking_title text,
  service_type text,
  supplier_id uuid,
  supplier_name text,
  supplier_reference text,
  amount_payable numeric,
  amount_paid numeric,
  outstanding_amount numeric,
  currency text,
  activity_date date,
  due_date date,
  paid_at timestamptz,
  status text,
  has_invoice boolean,
  supplier_invoice_file_name text,
  sharepoint_invoice_url text,
  payment_approved_by uuid,
  payment_approved_at timestamptz,
  disbursement_reference text,
  dispute_reference text,
  dispute_reason text,
  dispute_opened_at timestamptz,
  dispute_resolution text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (
    public.has_staff_permission('view_supplier_cost')
    or public.has_staff_permission('view_payments')
  ) then
    raise exception 'Supplier payment view permission required';
  end if;
  if v_status is not null and v_status not in ('pending', 'partial', 'paid', 'disputed', 'cancelled') then
    raise exception 'Invalid supplier payment status';
  end if;
  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then
    raise exception 'Start date must not be after end date';
  end if;

  return query
  select
    sp.id,
    sp.booking_id,
    b.booking_reference,
    b.title as booking_title,
    b.service_type::text as service_type,
    sp.supplier_id,
    sp.supplier_name,
    sp.supplier_reference,
    sp.amount_payable,
    sp.amount_paid,
    greatest(sp.amount_payable - sp.amount_paid, 0::numeric) as outstanding_amount,
    sp.currency,
    coalesce(sp.paid_at::date, sp.due_date, sp.created_at::date) as activity_date,
    sp.due_date,
    sp.paid_at,
    sp.status,
    (
      sp.supplier_invoice_path is not null
      or sp.microsoft_invoice_item_id is not null
      or sp.sharepoint_invoice_url is not null
    ) as has_invoice,
    sp.supplier_invoice_file_name,
    sp.sharepoint_invoice_url,
    sp.payment_approved_by,
    sp.payment_approved_at,
    sp.disbursement_reference,
    sp.dispute_reference,
    sp.dispute_reason,
    sp.dispute_opened_at,
    sp.dispute_resolution,
    sp.created_by,
    sp.created_at,
    sp.updated_at
  from public.supplier_payments sp
  join public.bookings b on b.id = sp.booking_id
  where (v_status is null or sp.status = v_status)
    and (
      p_date_from is null
      or coalesce(sp.paid_at::date, sp.due_date, sp.created_at::date) >= p_date_from
    )
    and (
      p_date_to is null
      or coalesce(sp.paid_at::date, sp.due_date, sp.created_at::date) <= p_date_to
    )
    and (
      v_search is null
      or b.booking_reference ilike '%' || v_search || '%'
      or sp.supplier_name ilike '%' || v_search || '%'
      or coalesce(sp.supplier_reference, '') ilike '%' || v_search || '%'
    )
  order by sp.created_at desc, sp.id desc
  limit greatest(1, least(coalesce(limit_count, 200), 500));
end;
$function$;

comment on function public.list_operations_supplier_payments(text, date, date, text, integer) is
  'Permission-gated global supplier-payment list. Date filters use paid date, then due date, then created date.';

revoke execute on function public.list_operations_supplier_payments(text, date, date, text, integer)
  from public, anon;
grant execute on function public.list_operations_supplier_payments(text, date, date, text, integer)
  to authenticated, service_role;


create or replace function public.list_operations_discount_approvals(limit_count integer default 200)
returns table(
  id uuid,
  booking_id uuid,
  booking_reference text,
  booking_title text,
  service_type text,
  discount_amount numeric,
  currency text,
  reason text,
  status text,
  requested_by uuid,
  requested_by_name text,
  original_selling_price numeric,
  proposed_selling_price numeric,
  supplier_cost numeric,
  request_payload jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('approve_discounts') then
    raise exception 'Discount approval permission required';
  end if;

  return query
  select
    ar.id,
    ar.entity_id as booking_id,
    b.booking_reference,
    b.title as booking_title,
    b.service_type::text as service_type,
    ar.amount as discount_amount,
    ar.currency,
    ar.reason,
    ar.status,
    ar.requested_by,
    requester.full_name as requested_by_name,
    nullif(ar.request_payload ->> 'original_selling_price', '')::numeric as original_selling_price,
    nullif(ar.request_payload ->> 'proposed_selling_price', '')::numeric as proposed_selling_price,
    nullif(ar.request_payload ->> 'supplier_cost', '')::numeric as supplier_cost,
    ar.request_payload,
    ar.created_at,
    ar.updated_at
  from public.approval_requests ar
  join public.bookings b on b.id = ar.entity_id
  left join public.staff_profiles requester on requester.user_id = ar.requested_by
  where ar.request_type = 'discount'
    and ar.entity_type = 'booking'
    and ar.status = 'pending'
    and b.archived_at is null
  order by ar.created_at asc, ar.id asc
  limit greatest(1, least(coalesce(limit_count, 200), 500));
end;
$function$;

comment on function public.list_operations_discount_approvals(integer) is
  'Permission-gated global queue of pending booking discount approval requests.';

revoke execute on function public.list_operations_discount_approvals(integer) from public, anon;
grant execute on function public.list_operations_discount_approvals(integer) to authenticated, service_role;


create or replace function public.reject_payment_refund_internal_20260818(
  p_payment_id uuid,
  p_rejection_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payment public.payments%rowtype;
  v_received_total numeric;
  v_sale_total numeric;
  v_restored_payment_status text;
  v_restored_booking_payment_status text;
  v_reason text := btrim(coalesce(p_rejection_reason, ''));
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;
  if not public.can_approve_refunds() then
    raise exception 'Refund rejection permission required';
  end if;
  if char_length(v_reason) < 10 then
    raise exception 'Rejection reason must be at least 10 characters';
  end if;

  select *
  into v_payment
  from public.payments
  where id = p_payment_id
    and payment_direction = 'customer_in'
  for update;

  if not found then
    raise exception 'Customer payment not found';
  end if;
  if v_payment.status <> 'refund_pending' then
    raise exception 'Only pending refunds can be rejected';
  end if;
  if v_payment.refund_requested_by is null then
    raise exception 'Refund request has no accountable requester';
  end if;
  if v_payment.refund_requested_by = v_actor then
    raise exception 'A refund must be rejected by a different authorized person';
  end if;

  -- request_payment_refund predates explicit original-status capture. Restore the
  -- most conservative valid state supported by the evidence already on the row.
  v_restored_payment_status := case
    when v_payment.received_at is not null then 'received'
    when v_payment.proof_storage_path is not null then 'proof_received'
    else 'pending'
  end;

  update public.payments
  set status = v_restored_payment_status,
      refund_approved_by = null,
      refund_approved_at = null,
      refund_completed_by = null,
      refund_completed_at = null,
      refund_method = null,
      refund_reference = null,
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    select coalesce(b.selling_price, b.amount, 0)
    into v_sale_total
    from public.bookings b
    where b.id = v_payment.booking_id
    for update;

    if found then
      select coalesce(sum(p.amount), 0)
      into v_received_total
      from public.payments p
      where p.booking_id = v_payment.booking_id
        and p.payment_direction = 'customer_in'
        and p.status in ('received', 'chargeback_won');

      v_restored_booking_payment_status := case
        when v_restored_payment_status = 'proof_received' then 'proof_received'
        when v_restored_payment_status = 'pending' then 'request_sent'
        when v_sale_total <= 0 or v_received_total <= 0 then 'not_requested'
        when v_received_total < v_sale_total then 'partially_paid'
        else 'paid'
      end;

      update public.bookings
      set payment_status = v_restored_booking_payment_status,
          updated_at = now()
      where id = v_payment.booking_id;
    end if;
  end if;

  insert into public.audit_events(
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'payment.refund_rejected',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'refund_amount', v_payment.refund_amount,
      'currency', v_payment.currency,
      'requested_by', v_payment.refund_requested_by,
      'request_reason', v_payment.refund_reason,
      'rejection_reason', v_reason,
      'payment_status_before', v_payment.status,
      'payment_status_after', v_restored_payment_status,
      'booking_payment_status_after', v_restored_booking_payment_status
    )
  );

  return p_payment_id;
end;
$function$;

create or replace function public.reject_payment_refund(
  p_payment_id uuid,
  p_rejection_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.reject_payment_refund_internal_20260818(p_payment_id, p_rejection_reason);
end;
$function$;

comment on function public.reject_payment_refund(uuid, text) is
  'Recent-auth, maker-checker refund rejection. Restores the evidence-backed payment state and recomputes the booking payment milestone.';

revoke execute on function public.reject_payment_refund_internal_20260818(uuid, text)
  from public, anon, authenticated;
grant execute on function public.reject_payment_refund_internal_20260818(uuid, text)
  to postgres, service_role;

revoke execute on function public.reject_payment_refund(uuid, text) from public, anon;
grant execute on function public.reject_payment_refund(uuid, text) to authenticated, service_role;
