begin;

-- Plaintext legacy PINs are unavailable, so affected users must receive a new
-- PIN through reset-staff-pin before they can sign in again.
alter table public.staff_profiles
  add column if not exists pin_reset_required boolean not null default false;

update public.staff_profiles sp
set pin_reset_required = true
where sp.active = true
  and not exists (
    select 1 from public.staff_pin_credentials pc where pc.user_id = sp.user_id
  );

insert into public.audit_events (target_user_id, event_type, entity_type, entity_id, metadata)
select sp.user_id, 'staff.pin_reset_required', 'user', sp.user_id,
       jsonb_build_object('reason', 'legacy_pin_retired')
from public.staff_profiles sp
where sp.active = true and sp.pin_reset_required = true
  and not exists (
    select 1 from public.audit_events ae
    where ae.target_user_id = sp.user_id
      and ae.event_type = 'staff.pin_reset_required'
      and ae.metadata ->> 'reason' = 'legacy_pin_retired'
  );

alter table public.staff_pin_credentials
  add column if not exists failed_auth_attempts integer not null default 0,
  add column if not exists locked_until timestamptz;

create table if not exists public.staff_pin_login_security_state (
  singleton boolean primary key default true check (singleton),
  blocked_until timestamptz,
  backoff_level integer not null default 0 check (backoff_level between 0 and 8),
  updated_at timestamptz not null default now()
);
insert into public.staff_pin_login_security_state (singleton) values (true)
on conflict (singleton) do nothing;
alter table public.staff_pin_login_security_state enable row level security;
revoke all on public.staff_pin_login_security_state from public, anon, authenticated;
grant all on public.staff_pin_login_security_state to service_role;

create or replace function public.staff_pin_login_begin(p_ip_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state public.staff_pin_login_security_state%rowtype;
  v_global_failures integer;
  v_ip_failures integer;
  v_backoff_seconds integer;
  v_attempt_id uuid;
begin
  if p_ip_hash is null or char_length(p_ip_hash) <> 64 then
    raise exception 'Invalid address hash';
  end if;

  select * into v_state from public.staff_pin_login_security_state
  where singleton = true for update;

  if v_state.blocked_until is not null and v_state.blocked_until > now() then
    return jsonb_build_object(
      'allowed', false,
      'scope', 'global',
      'retry_after_seconds', greatest(1, ceil(extract(epoch from v_state.blocked_until - now())))::integer
    );
  end if;

  select count(*) into v_global_failures
  from public.staff_pin_login_attempts
  where success = false and attempted_at >= now() - interval '15 minutes';

  if v_global_failures >= 50 then
    v_backoff_seconds := least(3600, 60 * (2 ^ least(v_state.backoff_level, 6))::integer);
    update public.staff_pin_login_security_state
    set blocked_until = now() + make_interval(secs => v_backoff_seconds),
        backoff_level = least(backoff_level + 1, 8), updated_at = now()
    where singleton = true;
    insert into public.audit_events (event_type, entity_type, metadata)
    values ('security.staff_pin_global_limit', 'authentication',
      jsonb_build_object('failed_attempts', v_global_failures, 'backoff_seconds', v_backoff_seconds));
    return jsonb_build_object('allowed', false, 'scope', 'global', 'retry_after_seconds', v_backoff_seconds);
  end if;

  select count(*) into v_ip_failures
  from public.staff_pin_login_attempts
  where ip_hash = p_ip_hash and success = false
    and attempted_at >= now() - interval '15 minutes';
  if v_ip_failures >= 5 then
    return jsonb_build_object('allowed', false, 'scope', 'ip', 'retry_after_seconds', 900);
  end if;

  insert into public.staff_pin_login_attempts (ip_hash, success)
  values (p_ip_hash, false) returning id into v_attempt_id;
  return jsonb_build_object('allowed', true, 'attempt_id', v_attempt_id);
end;
$$;

create or replace function public.staff_pin_login_finish(
  p_attempt_id uuid,
  p_user_id uuid default null,
  p_success boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_success then
    update public.staff_pin_login_attempts set success = true where id = p_attempt_id;
    if p_user_id is not null then
      update public.staff_pin_credentials
      set failed_auth_attempts = 0, locked_until = null
      where user_id = p_user_id;
    end if;
    update public.staff_pin_login_security_state
    set backoff_level = 0, blocked_until = null, updated_at = now()
    where singleton = true;
  elsif p_user_id is not null then
    update public.staff_pin_credentials
    set failed_auth_attempts = failed_auth_attempts + 1,
        locked_until = case
          when failed_auth_attempts + 1 >= 5 then now() + interval '30 minutes'
          else locked_until
        end
    where user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.staff_set_pin(p_user_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then raise exception 'PIN must contain exactly six digits'; end if;
  insert into public.staff_pin_credentials (user_id, pin_hash, updated_at, failed_auth_attempts, locked_until)
  values (p_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf')), now(), 0, null)
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, updated_at = now(), failed_auth_attempts = 0, locked_until = null;
  update public.staff_profiles set pin_reset_required = false where user_id = p_user_id;
end;
$$;

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

create or replace function public.staff_identity_for_pin(p_pin text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('user_id', u.id, 'email', u.email)
  from public.staff_pin_credentials pc
  join public.staff_profiles sp on sp.user_id = pc.user_id
  join auth.users u on u.id = pc.user_id
  where sp.active = true
    and sp.pin_reset_required = false
    and (pc.locked_until is null or pc.locked_until <= now())
    and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash)
  limit 1;
$$;

revoke execute on function public.staff_pin_login_begin(text) from public, anon, authenticated;
revoke execute on function public.staff_pin_login_finish(uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.staff_set_pin(uuid, text) from public, anon, authenticated;
revoke execute on function public.staff_pin_in_use(text, uuid) from public, anon, authenticated;
revoke execute on function public.staff_identity_for_pin(text) from public, anon, authenticated;
grant execute on function public.staff_pin_login_begin(text) to service_role;
grant execute on function public.staff_pin_login_finish(uuid, uuid, boolean) to service_role;
grant execute on function public.staff_set_pin(uuid, text) to service_role;
grant execute on function public.staff_pin_in_use(text, uuid) to service_role;
grant execute on function public.staff_identity_for_pin(text) to service_role;

create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule(
  'cleanup-staff-pin-login-attempts',
  '17 * * * *',
  $$delete from public.staff_pin_login_attempts where attempted_at < now() - interval '24 hours'$$
);

commit;
