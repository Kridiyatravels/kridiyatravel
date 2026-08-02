begin;

-- Captures the live-only function in migration history and closes the direct-RPC
-- privilege escalation. Owner is the sole role allowed to grant owner; all
-- other callers may grant only roles strictly below their own rank.
create or replace function public.setup_staff_account_record(
  target_user_id uuid,
  full_name text,
  department text default null,
  role public.staff_role default 'staff'::public.staff_role
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_role public.staff_role;
  v_actor_rank integer;
  v_target_rank integer;
begin
  select sr.role into v_actor_role
  from public.staff_roles sr where sr.user_id = v_actor;

  v_actor_rank := case v_actor_role
    when 'owner' then 4 when 'admin' then 3 when 'staff' then 2 when 'support' then 1 else 0 end;
  v_target_rank := case role
    when 'owner' then 4 when 'admin' then 3 when 'staff' then 2 when 'support' then 1 else 99 end;

  if v_actor_rank < 3 then
    raise exception 'Only admins can set up staff accounts';
  end if;
  if char_length(trim(coalesce(full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;
  if role = 'owner' and v_actor_role <> 'owner' then
    raise exception 'Only an owner can grant the owner role';
  end if;
  if v_actor_role <> 'owner' and v_target_rank >= v_actor_rank then
    raise exception 'Cannot grant a role at or above your own';
  end if;

  insert into public.staff_profiles (
    user_id, full_name, department, active, created_by, deleted_at, hold_until, hold_reason
  )
  values (
    target_user_id, trim(full_name), nullif(trim(coalesce(department, '')), ''),
    true, v_actor, null, null, null
  )
  on conflict (user_id) do update
    set full_name = excluded.full_name,
        department = excluded.department,
        active = true,
        deleted_at = null,
        hold_until = null,
        hold_reason = null,
        updated_at = now();

  insert into public.staff_roles (user_id, role)
  values (target_user_id, role)
  on conflict (user_id) do update set role = excluded.role;

  insert into public.staff_permissions (user_id)
  values (target_user_id)
  on conflict (user_id) do nothing;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (v_actor, target_user_id, 'staff.created', 'user', target_user_id,
          jsonb_build_object('full_name', full_name, 'role', role, 'department', department));

  return 'created';
end;
$$;

revoke execute on function public.setup_staff_account_record(uuid, text, text, public.staff_role)
  from public, anon;
grant execute on function public.setup_staff_account_record(uuid, text, text, public.staff_role)
  to authenticated;

commit;
