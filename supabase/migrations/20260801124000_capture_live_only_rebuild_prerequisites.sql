-- Capture live-only prerequisites that existed in production before later
-- hardening/snapshot migrations referenced them. This migration is historical
-- and idempotent: production already has every object represented here.

alter table public.staff_profiles
  add column if not exists job_title text,
  add column if not exists phone text,
  add column if not exists notes text,
  add column if not exists hold_until timestamptz,
  add column if not exists hold_reason text,
  add column if not exists deleted_at timestamptz;

create or replace function public.staff_email_for_pin(p_pin text)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  matched_email text;
begin
  if p_pin !~ '^[0-9]{6}$' then
    return null;
  end if;

  select au.email::text into matched_email
  from public.staff_profiles sp
  join auth.users au on au.id = sp.user_id
  where sp.active = true
    and sp.deleted_at is null
    and (sp.hold_until is null or sp.hold_until <= now())
    and au.encrypted_password = crypt(p_pin, au.encrypted_password)
  limit 1;

  return matched_email;
end;
$$;

create or replace function public.staff_management_admin_count(
  except_user_id uuid default null
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.staff_roles sr
  left join public.staff_profiles sp on sp.user_id = sr.user_id
  where sr.role in ('owner', 'admin')
    and (except_user_id is null or sr.user_id <> except_user_id)
    and coalesce(sp.active, true) = true
    and coalesce(sp.deleted_at is null, true)
    and (sp.hold_until is null or sp.hold_until <= now());
$$;

alter table public.quotes
  alter column enquiry_id drop not null,
  add column if not exists booking_id uuid references public.bookings(id) on delete set null;

create index if not exists quotes_booking_id_idx on public.quotes(booking_id);

alter table public.quotes
  drop constraint if exists quotes_enquiry_or_booking_check,
  add constraint quotes_enquiry_or_booking_check
    check (enquiry_id is not null or booking_id is not null);

create table if not exists public.staff_template_overrides (
  template_key text primary key,
  subject text,
  body text not null,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

grant all on table public.staff_template_overrides to service_role;
