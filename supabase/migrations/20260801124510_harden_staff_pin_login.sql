-- Kridiya Travel: remove direct public PIN lookup access and add a
-- server-only rate-limit store for the staff PIN Edge Function.

begin;

create table if not exists public.staff_pin_login_attempts (
  id uuid primary key default gen_random_uuid(),
  ip_hash text not null,
  success boolean not null default false,
  attempted_at timestamptz not null default now(),
  constraint staff_pin_login_ip_hash_format
    check (ip_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists staff_pin_login_attempts_lookup_idx
  on public.staff_pin_login_attempts (ip_hash, attempted_at desc)
  where success = false;
create index if not exists staff_pin_login_attempts_cleanup_idx
  on public.staff_pin_login_attempts (attempted_at);

alter table public.staff_pin_login_attempts enable row level security;

-- There are deliberately no browser grants. Only the Edge Function's
-- server-side secret key may read or write these rate-limit records.
revoke all on public.staff_pin_login_attempts from public, anon, authenticated;
grant select, insert, update, delete on public.staff_pin_login_attempts to service_role;

-- This function compares bcrypt PIN hashes and reads auth.users. It must not
-- be callable directly through the public Data API.
revoke execute on function public.staff_email_for_pin(text)
  from public, anon, authenticated;
grant execute on function public.staff_email_for_pin(text) to service_role;

-- Internal helper used by privileged staff-management functions. It has no
-- caller check of its own, so remove direct signed-in access.
revoke execute on function public.staff_management_admin_count(uuid)
  from public, anon, authenticated;
grant execute on function public.staff_management_admin_count(uuid) to service_role;

commit;
