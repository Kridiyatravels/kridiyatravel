-- Kridiya Travel - staff profiles + PIN login support (phase 7)
-- staff_profiles holds the human-facing identity (name, department) for
-- a staff account. Real account creation/PIN handling happens in Edge
-- Functions using the service role - this migration only adds the data
-- layer and the anon-safe picker used by the PIN login screen.

begin;

create table if not exists public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null,
  department text,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_profiles_full_name_length check (char_length(trim(full_name)) between 2 and 160)
);

create index if not exists staff_profiles_user_id_idx on public.staff_profiles(user_id);

drop trigger if exists staff_profiles_set_updated_at on public.staff_profiles;
create trigger staff_profiles_set_updated_at
before update on public.staff_profiles
for each row execute function public.set_updated_at();

alter table public.staff_profiles enable row level security;

drop policy if exists "staff_profiles_select_admin_or_self" on public.staff_profiles;
create policy "staff_profiles_select_admin_or_self"
on public.staff_profiles for select
to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists "staff_profiles_manage_admin" on public.staff_profiles;
create policy "staff_profiles_manage_admin"
on public.staff_profiles for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on public.staff_profiles from anon, authenticated;
grant select, insert, update, delete on public.staff_profiles to authenticated;

-- Anonymous, pre-login picker: name + department only, active staff only.
-- Deliberately excludes email and user_id so nothing sensitive is exposed
-- to an unauthenticated visitor - just enough to build a "who are you"
-- dropdown on the PIN login screen.
create or replace function public.list_staff_for_login()
returns table(id uuid, full_name text, department text)
language sql
security definer
set search_path = public
stable
as $$
  select sp.id, sp.full_name, sp.department
  from public.staff_profiles sp
  where sp.active = true
  order by sp.full_name asc;
$$;

revoke execute on function public.list_staff_for_login() from authenticated;
grant execute on function public.list_staff_for_login() to anon, authenticated;

-- Richer staff list for the admin panel: role + profile info together.
create or replace function public.list_staff()
returns table(
  user_id uuid,
  email text,
  role public.staff_role,
  full_name text,
  department text,
  active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Only staff can view the staff list';
  end if;
  return query
    select sr.user_id, u.email, sr.role,
           coalesce(sp.full_name, u.email), sp.department,
           coalesce(sp.active, true), sr.created_at
    from public.staff_roles sr
    join auth.users u on u.id = sr.user_id
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    order by sr.created_at asc;
end;
$$;

revoke execute on function public.list_staff() from anon;
grant execute on function public.list_staff() to authenticated;

-- Tighten staff management to admin/owner only (previously any staff
-- could grant/revoke staff access - now matches "only admin manages staff").
create or replace function public.grant_staff_by_email(target_email text, target_role public.staff_role default 'staff')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only admins can grant staff access';
  end if;
  select id into target_id from auth.users where lower(email) = lower(trim(target_email)) limit 1;
  if target_id is null then
    return 'not_found';
  end if;
  insert into public.staff_roles (user_id, role)
  values (target_id, target_role)
  on conflict (user_id) do update set role = excluded.role;
  return 'granted';
end;
$$;

create or replace function public.revoke_staff(target_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can revoke staff access';
  end if;
  if target_user_id = auth.uid() then
    return 'cannot_remove_self';
  end if;
  update public.staff_profiles set active = false where user_id = target_user_id;
  delete from public.staff_roles where user_id = target_user_id;
  return 'revoked';
end;
$$;

commit;
