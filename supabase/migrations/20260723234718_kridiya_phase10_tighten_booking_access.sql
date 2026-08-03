-- Kridiya Phase 10: tighten booking access after adding finance-sensitive fields.
-- Staff can still work bookings through permissions, but broad legacy select is removed.

drop policy if exists bookings_select_own_or_staff on public.bookings;
create policy bookings_select_own_or_staff on public.bookings
  for select to authenticated
  using (
    (user_id = auth.uid())
    or public.has_staff_permission('create_bookings')
    or public.has_staff_permission('edit_bookings')
    or public.has_staff_permission('view_payments')
    or public.has_staff_permission('view_reports')
  );

-- A list RPC for staff UI that masks finance fields unless the viewer has finance permission.
create or replace function public.list_operations_bookings(limit_count integer default 200)
returns table (
  id uuid,
  booking_reference text,
  enquiry_id uuid,
  customer_id uuid,
  corporate_account_id uuid,
  booking_kind text,
  service_type public.booking_service_type,
  title text,
  route_or_destination text,
  travel_start date,
  travel_end date,
  status public.booking_status,
  payment_status text,
  document_status text,
  supplier_name text,
  supplier_cost numeric,
  selling_price numeric,
  gross_profit numeric,
  currency text,
  priority text,
  follow_up_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    b.id,
    b.booking_reference,
    b.enquiry_id,
    b.customer_id,
    b.corporate_account_id,
    b.booking_kind,
    b.service_type,
    b.title,
    b.route_or_destination,
    b.travel_start,
    b.travel_end,
    b.status,
    b.payment_status,
    b.document_status,
    b.supplier_name,
    case when public.has_staff_permission('view_supplier_cost') then b.supplier_cost else null end as supplier_cost,
    case when public.has_staff_permission('view_payments') or public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount) else null end as selling_price,
    case when public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) else null end as gross_profit,
    b.currency,
    b.priority,
    b.follow_up_at,
    b.created_at,
    b.updated_at
  from public.bookings b
  where b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    )
  order by b.created_at desc
  limit greatest(1, least(limit_count, 500));
$$;

-- Customer/payment list RPC with the same masking pattern for dashboard/report UIs.
create or replace function public.list_operations_payments(limit_count integer default 200)
returns table (
  id uuid,
  booking_id uuid,
  enquiry_id uuid,
  customer_id uuid,
  corporate_account_id uuid,
  payment_reference text,
  payment_direction text,
  amount numeric,
  currency text,
  method text,
  status text,
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
    p.payment_reference,
    p.payment_direction,
    p.amount,
    p.currency,
    p.method,
    p.status,
    p.received_at,
    p.created_at,
    p.updated_at
  from public.payments p
  where public.has_staff_permission('view_payments')
  order by p.created_at desc
  limit greatest(1, least(limit_count, 500));
$$;
