create table if not exists public.staff_pin_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  updated_at timestamptz not null default now()
);
alter table public.staff_pin_credentials enable row level security;
revoke all on table public.staff_pin_credentials from public, anon, authenticated;
grant all on table public.staff_pin_credentials to service_role;

create or replace function public.staff_pin_in_use(p_pin text, p_exclude_user_id uuid default null)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from public.staff_pin_credentials pc
    join public.staff_profiles sp on sp.user_id = pc.user_id
    where sp.active = true
      and (p_exclude_user_id is null or pc.user_id <> p_exclude_user_id)
      and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash)
  );
$$;

create or replace function public.staff_set_pin(p_user_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then raise exception 'PIN must contain exactly six digits'; end if;
  insert into public.staff_pin_credentials (user_id, pin_hash, updated_at)
  values (p_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf')), now())
  on conflict (user_id) do update set pin_hash = excluded.pin_hash, updated_at = now();
end;
$$;

create or replace function public.staff_identity_for_pin(p_pin text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_result jsonb;
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then return null; end if;
  select jsonb_build_object('user_id', u.id, 'email', u.email, 'legacy', false) into v_result
  from public.staff_pin_credentials pc
  join public.staff_profiles sp on sp.user_id = pc.user_id
  join auth.users u on u.id = pc.user_id
  where sp.active = true and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash) limit 1;
  if v_result is not null then return v_result; end if;
  select jsonb_build_object('user_id', u.id, 'email', u.email, 'legacy', true) into v_result
  from public.staff_profiles sp join auth.users u on u.id = sp.user_id
  left join public.staff_pin_credentials pc on pc.user_id = sp.user_id
  where sp.active = true and pc.user_id is null
    and u.encrypted_password = extensions.crypt(p_pin, u.encrypted_password) limit 1;
  return v_result;
end;
$$;

revoke execute on function public.staff_pin_in_use(text, uuid) from public, anon, authenticated;
revoke execute on function public.staff_set_pin(uuid, text) from public, anon, authenticated;
revoke execute on function public.staff_identity_for_pin(text) from public, anon, authenticated;
grant execute on function public.staff_pin_in_use(text, uuid) to service_role;
grant execute on function public.staff_set_pin(uuid, text) to service_role;
grant execute on function public.staff_identity_for_pin(text) to service_role;
-- The legacy helper remains service-role-only during this rollout so the
-- currently deployed login function keeps working until its replacement is live.
