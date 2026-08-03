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

revoke execute on function public.can_approve_refunds() from public;
revoke execute on function public.can_approve_refunds() from anon;
grant execute on function public.can_approve_refunds() to authenticated, service_role;
