-- Kridiya Phase 8: professional operations foundation
-- Additive migration: no existing data is removed.

-- Extend existing enums for future-ready operations.
do $$
begin
  if not exists (select 1 from pg_enum where enumtypid = 'public.booking_service_type'::regtype and enumlabel = 'transfer') then
    alter type public.booking_service_type add value 'transfer';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.booking_service_type'::regtype and enumlabel = 'corporate') then
    alter type public.booking_service_type add value 'corporate';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.staff_role'::regtype and enumlabel = 'operations') then
    alter type public.staff_role add value 'operations';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.staff_role'::regtype and enumlabel = 'finance') then
    alter type public.staff_role add value 'finance';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.staff_role'::regtype and enumlabel = 'marketing') then
    alter type public.staff_role add value 'marketing';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.staff_role'::regtype and enumlabel = 'readonly') then
    alter type public.staff_role add value 'readonly';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'quotation') then
    alter type public.document_type add value 'quotation';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'receipt') then
    alter type public.document_type add value 'receipt';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'refund_note') then
    alter type public.document_type add value 'refund_note';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'payment_request') then
    alter type public.document_type add value 'payment_request';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'hotel_voucher') then
    alter type public.document_type add value 'hotel_voucher';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'visa_confirmation') then
    alter type public.document_type add value 'visa_confirmation';
  end if;
  if not exists (select 1 from pg_enum where enumtypid = 'public.document_type'::regtype and enumlabel = 'corporate_confirmation') then
    alter type public.document_type add value 'corporate_confirmation';
  end if;
end $$;

-- Staff permission switches. Admin/owner always bypass through has_staff_permission().
create table if not exists public.staff_permissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  view_enquiries boolean not null default true,
  edit_enquiries boolean not null default false,
  view_customers boolean not null default true,
  edit_customers boolean not null default false,
  view_corporates boolean not null default false,
  edit_corporates boolean not null default false,
  create_bookings boolean not null default false,
  edit_bookings boolean not null default false,
  view_payments boolean not null default false,
  edit_payments boolean not null default false,
  view_supplier_cost boolean not null default false,
  view_profit boolean not null default false,
  generate_documents boolean not null default false,
  manage_portals boolean not null default false,
  manage_templates boolean not null default false,
  view_reports boolean not null default false,
  export_reports boolean not null default false,
  approve_refunds boolean not null default false,
  approve_discounts boolean not null default false,
  manage_staff boolean not null default false,
  view_activity boolean not null default false,
  manage_settings boolean not null default false,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.staff_permissions enable row level security;

drop policy if exists staff_permissions_select_admin_or_self on public.staff_permissions;
create policy staff_permissions_select_admin_or_self on public.staff_permissions
  for select to authenticated
  using (public.is_admin() or user_id = auth.uid());

drop policy if exists staff_permissions_manage_admin on public.staff_permissions;
create policy staff_permissions_manage_admin on public.staff_permissions
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

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
    join public.staff_profiles sp on sp.user_id = sr.user_id
    where sr.user_id = auth.uid()
      and sp.active = true
      and sr.role in ('owner', 'admin')
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

-- Seed permission rows for existing staff. Owners/admins get full switches for UI clarity.
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
  sr.user_id,
  true,
  sr.role in ('owner', 'admin'),
  true,
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin', 'staff'),
  sr.role in ('owner', 'admin', 'staff'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin', 'staff'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin'),
  sr.role in ('owner', 'admin')
from public.staff_roles sr
on conflict (user_id) do nothing;

-- CRM customers not necessarily tied to customer portal auth accounts.
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid references auth.users(id),
  customer_type text not null default 'individual' check (customer_type in ('individual', 'corporate_contact')),
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  email text,
  phone text,
  whatsapp text,
  nationality text,
  preferred_currency text not null default 'AED' check (char_length(preferred_currency) = 3),
  source text not null default 'manual' check (source in ('website', 'whatsapp', 'email', 'phone', 'walk_in', 'referral', 'corporate', 'manual', 'other')),
  notes text,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create index if not exists idx_customers_email on public.customers (lower(email));
create index if not exists idx_customers_phone on public.customers (phone);
create index if not exists idx_customers_active on public.customers (active) where archived_at is null;

alter table public.customers enable row level security;

drop policy if exists customers_select_staff on public.customers;
create policy customers_select_staff on public.customers
  for select to authenticated
  using (public.has_staff_permission('view_customers'));

drop policy if exists customers_insert_staff on public.customers;
create policy customers_insert_staff on public.customers
  for insert to authenticated
  with check (public.has_staff_permission('edit_customers') or public.has_staff_permission('create_bookings'));

drop policy if exists customers_update_staff on public.customers;
create policy customers_update_staff on public.customers
  for update to authenticated
  using (public.has_staff_permission('edit_customers'))
  with check (public.has_staff_permission('edit_customers'));

-- Corporate accounts and contacts.
create table if not exists public.corporate_accounts (
  id uuid primary key default gen_random_uuid(),
  company_name text not null check (char_length(trim(company_name)) between 2 and 180),
  trade_license_no text,
  trn text,
  billing_email text,
  accounts_email text,
  phone text,
  address text,
  payment_terms text not null default 'payment_before_booking' check (payment_terms in ('payment_before_booking', 'credit_approved', 'monthly_billing')),
  credit_allowed boolean not null default false,
  monthly_billing boolean not null default false,
  lpo_required boolean not null default false,
  status text not null default 'active' check (status in ('active', 'prospect', 'on_hold', 'inactive', 'archived')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create index if not exists idx_corporate_accounts_company on public.corporate_accounts (lower(company_name));
create index if not exists idx_corporate_accounts_status on public.corporate_accounts (status);

alter table public.corporate_accounts enable row level security;

drop policy if exists corporate_accounts_select_staff on public.corporate_accounts;
create policy corporate_accounts_select_staff on public.corporate_accounts
  for select to authenticated
  using (public.has_staff_permission('view_corporates'));

drop policy if exists corporate_accounts_insert_staff on public.corporate_accounts;
create policy corporate_accounts_insert_staff on public.corporate_accounts
  for insert to authenticated
  with check (public.has_staff_permission('edit_corporates'));

drop policy if exists corporate_accounts_update_staff on public.corporate_accounts;
create policy corporate_accounts_update_staff on public.corporate_accounts
  for update to authenticated
  using (public.has_staff_permission('edit_corporates'))
  with check (public.has_staff_permission('edit_corporates'));

create table if not exists public.corporate_contacts (
  id uuid primary key default gen_random_uuid(),
  corporate_account_id uuid not null references public.corporate_accounts(id) on delete cascade,
  customer_id uuid references public.customers(id),
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  job_title text,
  email text,
  phone text,
  whatsapp text,
  is_authorized_contact boolean not null default false,
  is_accounts_contact boolean not null default false,
  active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_corporate_contacts_account on public.corporate_contacts (corporate_account_id);
create index if not exists idx_corporate_contacts_email on public.corporate_contacts (lower(email));

alter table public.corporate_contacts enable row level security;

drop policy if exists corporate_contacts_select_staff on public.corporate_contacts;
create policy corporate_contacts_select_staff on public.corporate_contacts
  for select to authenticated
  using (public.has_staff_permission('view_corporates'));

drop policy if exists corporate_contacts_insert_staff on public.corporate_contacts;
create policy corporate_contacts_insert_staff on public.corporate_contacts
  for insert to authenticated
  with check (public.has_staff_permission('edit_corporates'));

drop policy if exists corporate_contacts_update_staff on public.corporate_contacts;
create policy corporate_contacts_update_staff on public.corporate_contacts
  for update to authenticated
  using (public.has_staff_permission('edit_corporates'))
  with check (public.has_staff_permission('edit_corporates'));

-- B2B portal directory: store links and password-location notes, never raw passwords.
create table if not exists public.b2b_portals (
  id uuid primary key default gen_random_uuid(),
  portal_name text not null check (char_length(trim(portal_name)) between 2 and 160),
  website_url text not null,
  service_scope text not null default 'all',
  username_hint text,
  password_location text,
  owner_notes text,
  status text not null default 'active' check (status in ('active', 'pending', 'inactive', 'archived')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_b2b_portals_name on public.b2b_portals (lower(portal_name));

alter table public.b2b_portals enable row level security;

drop policy if exists b2b_portals_select_staff on public.b2b_portals;
create policy b2b_portals_select_staff on public.b2b_portals
  for select to authenticated
  using (public.is_staff());

drop policy if exists b2b_portals_manage_staff on public.b2b_portals;
create policy b2b_portals_manage_staff on public.b2b_portals
  for all to authenticated
  using (public.has_staff_permission('manage_portals'))
  with check (public.has_staff_permission('manage_portals'));

insert into public.b2b_portals (portal_name, website_url, service_scope, password_location, status)
values
  ('Akbar Travels', 'https://www.akbartravelsonline.com/', 'flights, visa, hotels, packages', 'Password manager', 'active'),
  ('Select My Flight', 'https://selectmyflight.com/', 'visa', 'Password manager', 'active')
on conflict (lower(portal_name)) do nothing;

-- Extend existing bookings table for operations, finance, corporate, and service-specific payloads.
alter table public.bookings
  add column if not exists enquiry_id uuid references public.enquiries(id),
  add column if not exists customer_id uuid references public.customers(id),
  add column if not exists corporate_account_id uuid references public.corporate_accounts(id),
  add column if not exists corporate_contact_id uuid references public.corporate_contacts(id),
  add column if not exists portal_id uuid references public.b2b_portals(id),
  add column if not exists booking_kind text not null default 'individual' check (booking_kind in ('individual', 'corporate')),
  add column if not exists source text not null default 'manual' check (source in ('website', 'whatsapp', 'email', 'phone', 'walk_in', 'referral', 'corporate', 'manual', 'other')),
  add column if not exists priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  add column if not exists lpo_number text,
  add column if not exists approval_person text,
  add column if not exists supplier_name text,
  add column if not exists supplier_cost numeric check (supplier_cost is null or supplier_cost >= 0),
  add column if not exists supplier_currency text not null default 'AED' check (char_length(supplier_currency) = 3),
  add column if not exists selling_price numeric check (selling_price is null or selling_price >= 0),
  add column if not exists payment_status text not null default 'not_requested' check (payment_status in ('not_requested', 'request_sent', 'proof_received', 'partially_paid', 'paid', 'supplier_payment_pending', 'supplier_paid', 'refund_pending', 'refunded', 'failed', 'cancelled')),
  add column if not exists document_status text not null default 'not_started' check (document_status in ('not_started', 'draft', 'generated', 'sent', 'archived')),
  add column if not exists service_payload jsonb not null default '{}'::jsonb,
  add column if not exists follow_up_at timestamptz,
  add column if not exists archived_at timestamptz;

create index if not exists idx_bookings_enquiry on public.bookings (enquiry_id);
create index if not exists idx_bookings_customer on public.bookings (customer_id);
create index if not exists idx_bookings_corporate on public.bookings (corporate_account_id);
create index if not exists idx_bookings_payment_status on public.bookings (payment_status);
create index if not exists idx_bookings_follow_up on public.bookings (follow_up_at) where follow_up_at is not null;

-- Staff policies get tightened through permission helpers while preserving existing staff access.
drop policy if exists bookings_insert_staff on public.bookings;
create policy bookings_insert_staff on public.bookings
  for insert to authenticated
  with check (public.has_staff_permission('create_bookings'));

drop policy if exists bookings_update_staff on public.bookings;
create policy bookings_update_staff on public.bookings
  for update to authenticated
  using (public.has_staff_permission('edit_bookings'))
  with check (public.has_staff_permission('edit_bookings'));

-- Booking passengers/service detail. Existing booking_travellers remains for customer portal compatibility.
create table if not exists public.booking_passengers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  customer_id uuid references public.customers(id),
  passenger_name text not null check (char_length(trim(passenger_name)) between 2 and 160),
  passenger_type text not null default 'adult' check (passenger_type in ('adult', 'child', 'infant')),
  nationality text,
  date_of_birth date,
  passport_number text,
  passport_expiry date,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_booking_passengers_booking on public.booking_passengers (booking_id);
alter table public.booking_passengers enable row level security;

drop policy if exists booking_passengers_select_staff on public.booking_passengers;
create policy booking_passengers_select_staff on public.booking_passengers
  for select to authenticated
  using (public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings'));

drop policy if exists booking_passengers_insert_staff on public.booking_passengers;
create policy booking_passengers_insert_staff on public.booking_passengers
  for insert to authenticated
  with check (public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings'));

drop policy if exists booking_passengers_update_staff on public.booking_passengers;
create policy booking_passengers_update_staff on public.booking_passengers
  for update to authenticated
  using (public.has_staff_permission('edit_bookings'))
  with check (public.has_staff_permission('edit_bookings'));

-- Customer payments, supplier payments, and refunds.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete set null,
  enquiry_id uuid references public.enquiries(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  corporate_account_id uuid references public.corporate_accounts(id) on delete set null,
  payment_reference text unique,
  payment_direction text not null default 'customer_in' check (payment_direction in ('customer_in', 'customer_refund')),
  amount numeric not null check (amount >= 0),
  currency text not null default 'AED' check (char_length(currency) = 3),
  method text not null default 'bank_transfer' check (method in ('bank_transfer', 'cash', 'stripe', 'tabby', 'tamara', 'paypal', 'card_machine', 'other')),
  status text not null default 'pending' check (status in ('draft', 'pending', 'proof_received', 'received', 'failed', 'cancelled', 'refunded')),
  payment_link text,
  proof_storage_path text,
  receipt_document_id uuid references public.documents(id),
  received_at timestamptz,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_payments_booking on public.payments (booking_id);
create index if not exists idx_payments_status on public.payments (status);
create index if not exists idx_payments_received_at on public.payments (received_at);

alter table public.payments enable row level security;

drop policy if exists payments_select_staff on public.payments;
create policy payments_select_staff on public.payments
  for select to authenticated
  using (public.has_staff_permission('view_payments'));

drop policy if exists payments_insert_staff on public.payments;
create policy payments_insert_staff on public.payments
  for insert to authenticated
  with check (public.has_staff_permission('edit_payments'));

drop policy if exists payments_update_staff on public.payments;
create policy payments_update_staff on public.payments
  for update to authenticated
  using (public.has_staff_permission('edit_payments'))
  with check (public.has_staff_permission('edit_payments'));

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  portal_id uuid references public.b2b_portals(id),
  supplier_name text not null check (char_length(trim(supplier_name)) between 2 and 160),
  supplier_reference text,
  amount_payable numeric not null default 0 check (amount_payable >= 0),
  amount_paid numeric not null default 0 check (amount_paid >= 0),
  currency text not null default 'AED' check (char_length(currency) = 3),
  due_date date,
  paid_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'partial', 'paid', 'disputed', 'cancelled')),
  supplier_invoice_path text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_supplier_payments_booking on public.supplier_payments (booking_id);
create index if not exists idx_supplier_payments_status on public.supplier_payments (status);

alter table public.supplier_payments enable row level security;

drop policy if exists supplier_payments_select_staff on public.supplier_payments;
create policy supplier_payments_select_staff on public.supplier_payments
  for select to authenticated
  using (public.has_staff_permission('view_supplier_cost') or public.has_staff_permission('view_payments'));

drop policy if exists supplier_payments_insert_staff on public.supplier_payments;
create policy supplier_payments_insert_staff on public.supplier_payments
  for insert to authenticated
  with check (public.has_staff_permission('edit_payments'));

drop policy if exists supplier_payments_update_staff on public.supplier_payments;
create policy supplier_payments_update_staff on public.supplier_payments
  for update to authenticated
  using (public.has_staff_permission('edit_payments'))
  with check (public.has_staff_permission('edit_payments'));

create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete set null,
  payment_id uuid references public.payments(id) on delete set null,
  amount numeric not null check (amount >= 0),
  currency text not null default 'AED' check (char_length(currency) = 3),
  reason text not null check (char_length(trim(reason)) between 2 and 1000),
  status text not null default 'requested' check (status in ('requested', 'approved', 'rejected', 'paid', 'cancelled')),
  requested_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  paid_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.refunds enable row level security;

drop policy if exists refunds_select_staff on public.refunds;
create policy refunds_select_staff on public.refunds
  for select to authenticated
  using (public.has_staff_permission('view_payments'));

drop policy if exists refunds_insert_staff on public.refunds;
create policy refunds_insert_staff on public.refunds
  for insert to authenticated
  with check (public.has_staff_permission('edit_payments'));

drop policy if exists refunds_update_approver on public.refunds;
create policy refunds_update_approver on public.refunds
  for update to authenticated
  using (public.has_staff_permission('approve_refunds'))
  with check (public.has_staff_permission('approve_refunds'));

-- Approval requests for refunds, discounts, credit exceptions, or sensitive actions.
create table if not exists public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null check (request_type in ('refund', 'discount', 'credit_terms', 'delete_record', 'other')),
  entity_type text,
  entity_id uuid,
  amount numeric check (amount is null or amount >= 0),
  currency text default 'AED' check (currency is null or char_length(currency) = 3),
  reason text not null check (char_length(trim(reason)) between 2 and 1000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid references auth.users(id),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.approval_requests enable row level security;

drop policy if exists approval_requests_select_staff on public.approval_requests;
create policy approval_requests_select_staff on public.approval_requests
  for select to authenticated
  using (public.is_staff());

drop policy if exists approval_requests_insert_staff on public.approval_requests;
create policy approval_requests_insert_staff on public.approval_requests
  for insert to authenticated
  with check (public.is_staff());

drop policy if exists approval_requests_update_admin on public.approval_requests;
create policy approval_requests_update_admin on public.approval_requests
  for update to authenticated
  using (public.has_staff_permission('approve_refunds') or public.has_staff_permission('approve_discounts'))
  with check (public.has_staff_permission('approve_refunds') or public.has_staff_permission('approve_discounts'));

-- Reminders/tasks for follow-ups, payment reminders, document reminders.
create table if not exists public.tasks_reminders (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 2 and 220),
  task_type text not null default 'follow_up' check (task_type in ('follow_up', 'payment_reminder', 'document_request', 'supplier_payment', 'internal', 'other')),
  entity_type text,
  entity_id uuid,
  assigned_to uuid references auth.users(id),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open', 'done', 'cancelled', 'snoozed')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_tasks_assigned_due on public.tasks_reminders (assigned_to, due_at);
create index if not exists idx_tasks_status_due on public.tasks_reminders (status, due_at);

alter table public.tasks_reminders enable row level security;

drop policy if exists tasks_select_staff on public.tasks_reminders;
create policy tasks_select_staff on public.tasks_reminders
  for select to authenticated
  using (public.is_staff());

drop policy if exists tasks_insert_staff on public.tasks_reminders;
create policy tasks_insert_staff on public.tasks_reminders
  for insert to authenticated
  with check (public.is_staff());

drop policy if exists tasks_update_staff on public.tasks_reminders;
create policy tasks_update_staff on public.tasks_reminders
  for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- Template/SOP register for SharePoint, Canva, admin generator, message templates.
create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  template_name text not null check (char_length(trim(template_name)) between 2 and 180),
  category text not null default 'general',
  template_type text not null default 'link' check (template_type in ('admin_tool', 'sharepoint_file', 'canva', 'email', 'whatsapp', 'sop', 'link', 'other')),
  url text,
  status text not null default 'active' check (status in ('draft', 'active', 'needs_update', 'retired', 'archived')),
  owner_user_id uuid references auth.users(id),
  last_reviewed_at timestamptz,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.templates enable row level security;

drop policy if exists templates_select_staff on public.templates;
create policy templates_select_staff on public.templates
  for select to authenticated
  using (public.is_staff());

drop policy if exists templates_manage_staff on public.templates;
create policy templates_manage_staff on public.templates
  for all to authenticated
  using (public.has_staff_permission('manage_templates'))
  with check (public.has_staff_permission('manage_templates'));

-- Backup/export log: records that exports happened and where they were stored.
create table if not exists public.backup_exports (
  id uuid primary key default gen_random_uuid(),
  export_type text not null check (export_type in ('weekly_database', 'monthly_accounts', 'reports', 'manual', 'other')),
  period_label text,
  storage_location text,
  status text not null default 'planned' check (status in ('planned', 'completed', 'failed', 'verified')),
  exported_by uuid references auth.users(id),
  exported_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.backup_exports enable row level security;

drop policy if exists backup_exports_select_admin on public.backup_exports;
create policy backup_exports_select_admin on public.backup_exports
  for select to authenticated
  using (public.has_staff_permission('export_reports'));

drop policy if exists backup_exports_manage_admin on public.backup_exports;
create policy backup_exports_manage_admin on public.backup_exports
  for all to authenticated
  using (public.has_staff_permission('export_reports'))
  with check (public.has_staff_permission('export_reports'));

-- Update timestamps.
do $$
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'set_updated_at') then
    drop trigger if exists set_staff_permissions_updated_at on public.staff_permissions;
    create trigger set_staff_permissions_updated_at before update on public.staff_permissions for each row execute function public.set_updated_at();
    drop trigger if exists set_customers_updated_at on public.customers;
    create trigger set_customers_updated_at before update on public.customers for each row execute function public.set_updated_at();
    drop trigger if exists set_corporate_accounts_updated_at on public.corporate_accounts;
    create trigger set_corporate_accounts_updated_at before update on public.corporate_accounts for each row execute function public.set_updated_at();
    drop trigger if exists set_corporate_contacts_updated_at on public.corporate_contacts;
    create trigger set_corporate_contacts_updated_at before update on public.corporate_contacts for each row execute function public.set_updated_at();
    drop trigger if exists set_b2b_portals_updated_at on public.b2b_portals;
    create trigger set_b2b_portals_updated_at before update on public.b2b_portals for each row execute function public.set_updated_at();
    drop trigger if exists set_booking_passengers_updated_at on public.booking_passengers;
    create trigger set_booking_passengers_updated_at before update on public.booking_passengers for each row execute function public.set_updated_at();
    drop trigger if exists set_payments_updated_at on public.payments;
    create trigger set_payments_updated_at before update on public.payments for each row execute function public.set_updated_at();
    drop trigger if exists set_supplier_payments_updated_at on public.supplier_payments;
    create trigger set_supplier_payments_updated_at before update on public.supplier_payments for each row execute function public.set_updated_at();
    drop trigger if exists set_refunds_updated_at on public.refunds;
    create trigger set_refunds_updated_at before update on public.refunds for each row execute function public.set_updated_at();
    drop trigger if exists set_approval_requests_updated_at on public.approval_requests;
    create trigger set_approval_requests_updated_at before update on public.approval_requests for each row execute function public.set_updated_at();
    drop trigger if exists set_tasks_reminders_updated_at on public.tasks_reminders;
    create trigger set_tasks_reminders_updated_at before update on public.tasks_reminders for each row execute function public.set_updated_at();
    drop trigger if exists set_templates_updated_at on public.templates;
    create trigger set_templates_updated_at before update on public.templates for each row execute function public.set_updated_at();
    drop trigger if exists set_backup_exports_updated_at on public.backup_exports;
    create trigger set_backup_exports_updated_at before update on public.backup_exports for each row execute function public.set_updated_at();
  end if;
end $$;

-- Dashboard summary RPC for admin/staff pages.
create or replace function public.staff_dashboard_summary()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'enquiries_open', (select count(*) from public.enquiries where status <> 'closed'),
    'enquiries_today', (select count(*) from public.enquiries where created_at::date = current_date),
    'bookings_open', (select count(*) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'payments_pending', (select count(*) from public.payments where status in ('pending', 'proof_received')),
    'supplier_payments_pending', (select count(*) from public.supplier_payments where status in ('pending', 'partial')),
    'refunds_pending', (select count(*) from public.refunds where status = 'requested'),
    'tasks_due', (select count(*) from public.tasks_reminders where status = 'open' and due_at <= now()),
    'documents_generated', (select count(*) from public.documents),
    'recent_activity', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (
      select event_type, entity_type, entity_id, metadata, created_at
      from public.audit_events
      order by created_at desc
      limit 8
    ) x)
  )
  where public.is_staff();
$$;

-- Finance-safe view: profit fields only returned by permission-gated function, not public table exposure.
create or replace function public.booking_profit_summary()
returns table (
  booking_id uuid,
  booking_reference text,
  service_type public.booking_service_type,
  selling_price numeric,
  supplier_cost numeric,
  gross_profit numeric,
  currency text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    b.id,
    b.booking_reference,
    b.service_type,
    coalesce(b.selling_price, b.amount, 0) as selling_price,
    coalesce(b.supplier_cost, 0) as supplier_cost,
    coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) as gross_profit,
    b.currency,
    b.created_at
  from public.bookings b
  where public.has_staff_permission('view_profit')
    and b.archived_at is null;
$$;

-- Helpful comments for future developers/admins.
comment on table public.staff_permissions is 'Per-staff admin switches. Owner/admin bypass in has_staff_permission().';
comment on table public.b2b_portals is 'B2B supplier portal directory. Store links and password-location notes only, never raw passwords.';
comment on table public.payments is 'Customer payment and refund transaction tracker. Card details must never be stored here.';
comment on table public.supplier_payments is 'Supplier payable tracker for cost/profit and accounts control.';
comment on column public.bookings.service_payload is 'Flexible per-service details for flight, visa, corporate, hotel, package, Umrah, cruise, insurance, and transfer workflows.';
