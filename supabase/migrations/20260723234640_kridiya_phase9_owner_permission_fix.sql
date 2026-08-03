-- Kridiya Phase 9: make owner/admin permission bypass reliable even if a legacy owner has no staff profile row.

create or replace function public.has_staff_permission(permission_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed boolean;
begin
  if auth.uid() is null then
    return false;
  end if;

  if exists (
    select 1
    from public.staff_roles sr
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    where sr.user_id = auth.uid()
      and sr.role in ('owner', 'admin')
      and coalesce(sp.active, true) = true
  ) then
    return true;
  end if;

  execute format('select coalesce(%I, false) from public.staff_permissions where user_id = $1', permission_name)
    into allowed
    using auth.uid();

  return coalesce(allowed, false);
exception when undefined_column then
  return false;
end;
$$;

insert into public.staff_profiles (user_id, full_name, department, active)
select u.id, 'Indirani Alagarsamy', 'Owner', true
from auth.users u
join public.staff_roles sr on sr.user_id = u.id
where lower(u.email) = lower('indirani83@outlook.com')
  and sr.role = 'owner'
on conflict (user_id) do update
set full_name = coalesce(public.staff_profiles.full_name, excluded.full_name),
    department = coalesce(public.staff_profiles.department, excluded.department),
    active = true,
    updated_at = now();

insert into public.staff_permissions (
  user_id,
  view_enquiries, edit_enquiries, view_customers, edit_customers,
  view_corporates, edit_corporates, create_bookings, edit_bookings,
  view_payments, edit_payments, view_supplier_cost, view_profit,
  generate_documents, manage_portals, manage_templates, view_reports,
  export_reports, approve_refunds, approve_discounts, manage_staff,
  view_activity, manage_settings
)
select
  u.id,
  true, true, true, true,
  true, true, true, true,
  true, true, true, true,
  true, true, true, true,
  true, true, true, true,
  true, true
from auth.users u
join public.staff_roles sr on sr.user_id = u.id
where lower(u.email) = lower('indirani83@outlook.com')
  and sr.role = 'owner'
on conflict (user_id) do update
set view_enquiries = true,
    edit_enquiries = true,
    view_customers = true,
    edit_customers = true,
    view_corporates = true,
    edit_corporates = true,
    create_bookings = true,
    edit_bookings = true,
    view_payments = true,
    edit_payments = true,
    view_supplier_cost = true,
    view_profit = true,
    generate_documents = true,
    manage_portals = true,
    manage_templates = true,
    view_reports = true,
    export_reports = true,
    approve_refunds = true,
    approve_discounts = true,
    manage_staff = true,
    view_activity = true,
    manage_settings = true,
    updated_at = now();
