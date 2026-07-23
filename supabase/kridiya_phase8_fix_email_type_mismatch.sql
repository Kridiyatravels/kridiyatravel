-- Kridiya Travel - fix email type mismatch (phase 8)
-- auth.users.email is `character varying`, not `text`. list_staff() and
-- list_audit_events() declared their email columns as `text` and
-- selected u.email without a cast, which fails PL/pgSQL's strict
-- RETURN QUERY type check ("structure of query does not match
-- function result type") the moment either function is actually
-- called - the bug was invisible until real data existed to trigger it.

begin;

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
    select sr.user_id, u.email::text, sr.role,
           coalesce(sp.full_name, u.email::text), sp.department,
           coalesce(sp.active, true), sr.created_at
    from public.staff_roles sr
    join auth.users u on u.id = sr.user_id
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    order by sr.created_at asc;
end;
$$;

create or replace function public.list_audit_events(limit_count int default 200)
returns table(
  id uuid,
  event_type text,
  entity_type text,
  entity_id uuid,
  actor_email text,
  metadata jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can view the activity log';
  end if;
  return query
    select ae.id, ae.event_type, ae.entity_type, ae.entity_id,
           u.email::text, ae.metadata, ae.created_at
    from public.audit_events ae
    left join auth.users u on u.id = ae.actor_user_id
    order by ae.created_at desc
    limit limit_count;
end;
$$;

commit;
