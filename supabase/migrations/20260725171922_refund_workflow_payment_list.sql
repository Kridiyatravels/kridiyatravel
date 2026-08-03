drop function if exists public.list_operations_payments(integer);

create function public.list_operations_payments(limit_count integer default 200)
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

revoke execute on function public.list_operations_payments(integer) from public;
revoke execute on function public.list_operations_payments(integer) from anon;
grant execute on function public.list_operations_payments(integer) to authenticated, service_role;
