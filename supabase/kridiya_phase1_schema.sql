-- Kridiya Travel account system - Supabase phase 1 schema
-- Run this in a new Supabase project's SQL editor.
-- This file stores customer profiles and bookings, not raw card data.

begin;

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  create type public.booking_service_type as enum (
    'flight', 'hotel', 'holiday', 'visa', 'umrah', 'cruise', 'insurance', 'other'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.booking_status as enum (
    'enquiry',
    'quote_sent',
    'payment_pending',
    'confirmed',
    'paid',
    'ticketed',
    'completed',
    'cancelled',
    'refunded'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.payment_provider as enum ('razorpay', 'stripe');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.staff_role as enum ('owner', 'admin', 'staff', 'support');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  preferred_email text,
  phone text,
  whatsapp text,
  nationality text,
  preferred_currency text not null default 'AED',
  newsletter_opt_in boolean not null default false,
  marketing_consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint profiles_full_name_length check (char_length(trim(full_name)) between 2 and 160),
  constraint profiles_currency_length check (char_length(preferred_currency) = 3)
);

create table if not exists public.staff_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.staff_role not null default 'staff',
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  booking_reference text not null unique,
  service_type public.booking_service_type not null,
  title text not null,
  route_or_destination text,
  travel_start date,
  travel_end date,
  adults integer not null default 1,
  children integer not null default 0,
  infants integer not null default 0,
  amount numeric(12, 2),
  currency text not null default 'AED',
  status public.booking_status not null default 'enquiry',
  supplier_reference text,
  customer_notes text,
  staff_notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bookings_reference_length check (char_length(trim(booking_reference)) between 4 and 40),
  constraint bookings_title_length check (char_length(trim(title)) between 3 and 220),
  constraint bookings_pax_nonnegative check (adults >= 0 and children >= 0 and infants >= 0),
  constraint bookings_has_passenger check ((adults + children + infants) > 0),
  constraint bookings_currency_length check (char_length(currency) = 3)
);

create index if not exists bookings_user_id_idx on public.bookings(user_id);
create index if not exists bookings_status_idx on public.bookings(status);
create index if not exists bookings_created_at_idx on public.bookings(created_at desc);

create table if not exists public.booking_travellers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  traveller_name text not null,
  passenger_type text not null default 'adult',
  nationality text,
  date_of_birth date,
  created_at timestamptz not null default now(),
  constraint booking_travellers_name_length check (char_length(trim(traveller_name)) between 2 and 160),
  constraint booking_travellers_passenger_type check (passenger_type in ('adult', 'child', 'infant'))
);

create index if not exists booking_travellers_booking_id_idx on public.booking_travellers(booking_id);
create index if not exists booking_travellers_user_id_idx on public.booking_travellers(user_id);

create table if not exists public.booking_documents (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null,
  file_name text not null,
  storage_path text,
  external_reference text,
  visible_to_customer boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint booking_documents_type_length check (char_length(trim(document_type)) between 2 and 80),
  constraint booking_documents_file_name_length check (char_length(trim(file_name)) between 2 and 220)
);

create index if not exists booking_documents_booking_id_idx on public.booking_documents(booking_id);
create index if not exists booking_documents_user_id_idx on public.booking_documents(user_id);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider public.payment_provider not null,
  provider_customer_id text not null,
  provider_payment_method_id text not null,
  brand text,
  last4 text,
  exp_month integer,
  exp_year integer,
  billing_name text,
  is_default boolean not null default false,
  consent_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint payment_methods_last4 check (last4 is null or last4 ~ '^[0-9]{4}$'),
  constraint payment_methods_exp_month check (exp_month is null or exp_month between 1 and 12),
  constraint payment_methods_unique_provider_method unique (provider, provider_payment_method_id)
);

create index if not exists payment_methods_user_id_idx on public.payment_methods(user_id);

create table if not exists public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  consent_type text not null,
  consent_version text not null,
  accepted boolean not null,
  accepted_at timestamptz not null default now(),
  ip_hash text,
  user_agent text,
  constraint consents_type_length check (char_length(trim(consent_type)) between 2 and 80),
  constraint consents_version_length check (char_length(trim(consent_version)) between 1 and 40)
);

create index if not exists consents_user_id_idx on public.consents(user_id);

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  status text not null default 'requested',
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  constraint account_deletion_status check (status in ('requested', 'verifying', 'completed', 'rejected'))
);

create index if not exists account_deletion_requests_user_id_idx
  on public.account_deletion_requests(user_id);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint audit_events_type_length check (char_length(trim(event_type)) between 2 and 120)
);

create index if not exists audit_events_target_user_id_idx on public.audit_events(target_user_id);
create index if not exists audit_events_created_at_idx on public.audit_events(created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
before update on public.bookings
for each row execute function public.set_updated_at();

drop trigger if exists payment_methods_set_updated_at on public.payment_methods;
create trigger payment_methods_set_updated_at
before update on public.payment_methods
for each row execute function public.set_updated_at();

create or replace function public.is_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.staff_roles sr
    where sr.user_id = auth.uid()
      and sr.role in ('owner', 'admin', 'staff', 'support')
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, preferred_email, phone, whatsapp)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
      nullif(trim(new.raw_user_meta_data->>'name'), ''),
      split_part(new.email, '@', 1)
    ),
    new.email,
    nullif(trim(new.raw_user_meta_data->>'phone'), ''),
    nullif(trim(new.raw_user_meta_data->>'whatsapp'), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.staff_roles enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_travellers enable row level security;
alter table public.booking_documents enable row level security;
alter table public.payment_methods enable row level security;
alter table public.consents enable row level security;
alter table public.account_deletion_requests enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists "profiles_select_own_or_staff" on public.profiles;
create policy "profiles_select_own_or_staff"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_staff());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert to authenticated
with check (id = auth.uid());

drop policy if exists "profiles_update_own_or_staff" on public.profiles;
create policy "profiles_update_own_or_staff"
on public.profiles for update to authenticated
using (id = auth.uid() or public.is_staff())
with check (id = auth.uid() or public.is_staff());

drop policy if exists "staff_roles_select_staff" on public.staff_roles;
create policy "staff_roles_select_staff"
on public.staff_roles for select to authenticated
using (public.is_staff());

drop policy if exists "bookings_select_own_or_staff" on public.bookings;
create policy "bookings_select_own_or_staff"
on public.bookings for select to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "bookings_insert_staff" on public.bookings;
create policy "bookings_insert_staff"
on public.bookings for insert to authenticated
with check (public.is_staff());

drop policy if exists "bookings_update_staff" on public.bookings;
create policy "bookings_update_staff"
on public.bookings for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "booking_travellers_select_own_or_staff" on public.booking_travellers;
create policy "booking_travellers_select_own_or_staff"
on public.booking_travellers for select to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "booking_travellers_insert_staff" on public.booking_travellers;
create policy "booking_travellers_insert_staff"
on public.booking_travellers for insert to authenticated
with check (public.is_staff());

drop policy if exists "booking_travellers_update_staff" on public.booking_travellers;
create policy "booking_travellers_update_staff"
on public.booking_travellers for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "booking_documents_select_visible_own_or_staff" on public.booking_documents;
create policy "booking_documents_select_visible_own_or_staff"
on public.booking_documents for select to authenticated
using ((user_id = auth.uid() and visible_to_customer = true) or public.is_staff());

drop policy if exists "booking_documents_insert_staff" on public.booking_documents;
create policy "booking_documents_insert_staff"
on public.booking_documents for insert to authenticated
with check (public.is_staff());

drop policy if exists "booking_documents_update_staff" on public.booking_documents;
create policy "booking_documents_update_staff"
on public.booking_documents for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "payment_methods_select_own_or_staff" on public.payment_methods;
create policy "payment_methods_select_own_or_staff"
on public.payment_methods for select to authenticated
using ((user_id = auth.uid() and deleted_at is null) or public.is_staff());

drop policy if exists "payment_methods_manage_staff" on public.payment_methods;
create policy "payment_methods_manage_staff"
on public.payment_methods for all to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "consents_select_own_or_staff" on public.consents;
create policy "consents_select_own_or_staff"
on public.consents for select to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "consents_insert_own" on public.consents;
create policy "consents_insert_own"
on public.consents for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "account_deletion_select_own_or_staff" on public.account_deletion_requests;
create policy "account_deletion_select_own_or_staff"
on public.account_deletion_requests for select to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "account_deletion_insert_own" on public.account_deletion_requests;
create policy "account_deletion_insert_own"
on public.account_deletion_requests for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "account_deletion_update_staff" on public.account_deletion_requests;
create policy "account_deletion_update_staff"
on public.account_deletion_requests for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "audit_events_select_staff" on public.audit_events;
create policy "audit_events_select_staff"
on public.audit_events for select to authenticated
using (public.is_staff());

drop policy if exists "audit_events_insert_staff" on public.audit_events;
create policy "audit_events_insert_staff"
on public.audit_events for insert to authenticated
with check (public.is_staff());

revoke all on public.profiles from anon, authenticated;
revoke all on public.staff_roles from anon, authenticated;
revoke all on public.bookings from anon, authenticated;
revoke all on public.booking_travellers from anon, authenticated;
revoke all on public.booking_documents from anon, authenticated;
revoke all on public.payment_methods from anon, authenticated;
revoke all on public.consents from anon, authenticated;
revoke all on public.account_deletion_requests from anon, authenticated;
revoke all on public.audit_events from anon, authenticated;

grant usage on schema public to anon, authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select on public.staff_roles to authenticated;

grant select, insert, update on public.bookings to authenticated;
grant select, insert, update on public.booking_travellers to authenticated;
grant select, insert, update on public.booking_documents to authenticated;

-- Customers may see only safe card display fields. Provider IDs are for Edge
-- Functions and staff use; no raw card numbers are stored in this table.
grant select (
  id,
  user_id,
  provider,
  brand,
  last4,
  exp_month,
  exp_year,
  billing_name,
  is_default,
  consent_at,
  created_at,
  updated_at,
  deleted_at
) on public.payment_methods to authenticated;
grant insert, update, delete on public.payment_methods to authenticated;

grant select, insert on public.consents to authenticated;
grant select, insert, update on public.account_deletion_requests to authenticated;
grant select, insert on public.audit_events to authenticated;

comment on table public.payment_methods is
  'Stores provider token/payment method references only. Never store raw card number, CVV, PIN, OTP, or full card data.';

commit;
