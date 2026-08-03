-- Add a has_proof flag to the payments list so the Payments page can show
-- which customer payments already have proof attached.
drop function if exists public.list_operations_payments(integer);

create function public.list_operations_payments(limit_count integer default 200)
returns table(
  id uuid, booking_id uuid, enquiry_id uuid, customer_id uuid, corporate_account_id uuid,
  payment_reference text, payment_direction text, amount numeric, currency text, method text,
  status text, has_proof boolean, received_at timestamptz, created_at timestamptz, updated_at timestamptz
)
language sql
security definer
set search_path to 'public'
as $function$
  select
    p.id, p.booking_id, p.enquiry_id, p.customer_id, p.corporate_account_id,
    p.payment_reference, p.payment_direction, p.amount, p.currency, p.method,
    p.status, (p.proof_storage_path is not null) as has_proof,
    p.received_at, p.created_at, p.updated_at
  from public.payments p
  where public.has_staff_permission('view_payments')
  order by p.created_at desc
  limit greatest(1, least(limit_count, 500));
$function$;

revoke all on function public.list_operations_payments(integer) from public, anon;
grant execute on function public.list_operations_payments(integer) to authenticated;
