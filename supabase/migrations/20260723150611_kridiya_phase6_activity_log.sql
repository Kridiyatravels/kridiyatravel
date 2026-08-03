create or replace function public.is_admin()
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
      and sr.role in ('owner', 'admin')
  );
$$;

revoke execute on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "audit_events_select_staff" on public.audit_events;
drop policy if exists "audit_events_select_admin" on public.audit_events;
create policy "audit_events_select_admin"
on public.audit_events for select
to authenticated
using (public.is_admin());

drop policy if exists "audit_events_insert_staff" on public.audit_events;
create policy "audit_events_insert_staff"
on public.audit_events for insert
to authenticated
with check (public.is_staff());

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
           u.email, ae.metadata, ae.created_at
    from public.audit_events ae
    left join auth.users u on u.id = ae.actor_user_id
    order by ae.created_at desc
    limit limit_count;
end;
$$;

revoke execute on function public.list_audit_events(int) from anon, authenticated;
grant execute on function public.list_audit_events(int) to authenticated;
