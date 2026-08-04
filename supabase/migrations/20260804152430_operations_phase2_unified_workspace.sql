begin;

alter table public.tasks_reminders
  add column if not exists snoozed_until timestamptz,
  add column if not exists escalated_at timestamptz,
  add column if not exists escalation_reason text;

create index if not exists tasks_reminders_workspace_idx
  on public.tasks_reminders(status, assigned_to, due_at, priority);

create or replace function public.list_operations_tasks(p_limit integer default 300)
returns table(
  id uuid, title text, task_type text, entity_type text, entity_id uuid,
  entity_reference text, entity_title text, assigned_to uuid, assigned_to_name text,
  due_at timestamptz, status text, priority text, notes text,
  snoozed_until timestamptz, escalated_at timestamptz, escalation_reason text,
  created_at timestamptz, completed_at timestamptz, due_bucket text, action_url text
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select t.id, t.title, t.task_type, t.entity_type, t.entity_id,
    coalesce(e.reference, b.booking_reference, p.payment_reference, d.document_number, left(t.entity_id::text, 8)) as entity_reference,
    coalesce(e.full_name || ' - ' || e.summary, b.title, p.payment_reference, d.customer_name, initcap(coalesce(t.entity_type, 'general'))) as entity_title,
    t.assigned_to, sp.full_name, t.due_at, t.status, t.priority, t.notes,
    t.snoozed_until, t.escalated_at, t.escalation_reason, t.created_at, t.completed_at,
    case
      when t.status = 'done' then 'completed'
      when t.status = 'snoozed' and t.snoozed_until > now() then 'snoozed'
      when t.due_at is null then 'no_due_date'
      when t.due_at < now() then 'overdue'
      when t.due_at::date = current_date then 'today'
      when t.due_at < now() + interval '8 days' then 'next_7_days'
      else 'later'
    end as due_bucket,
    case t.entity_type
      when 'enquiry' then 'admin.html?focus=' || t.entity_id
      when 'booking' then 'booking-detail.html?id=' || t.entity_id
      when 'payment' then 'payments.html?focus=' || t.entity_id
      when 'document' then 'documents.html?focus=' || t.entity_id
      else 'dashboard.html'
    end as action_url
  from public.tasks_reminders t
  left join public.enquiries e on t.entity_type = 'enquiry' and e.id = t.entity_id
  left join public.bookings b on t.entity_type = 'booking' and b.id = t.entity_id
  left join public.payments p on t.entity_type = 'payment' and p.id = t.entity_id
  left join public.documents d on t.entity_type = 'document' and d.id = t.entity_id
  left join public.staff_profiles sp on sp.user_id = t.assigned_to
  where public.is_staff()
    and (public.is_admin() or t.assigned_to is null or t.assigned_to = auth.uid())
  order by
    case when t.escalated_at is not null and t.status <> 'done' then 0 else 1 end,
    case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
    t.due_at nulls last, t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 300), 1000));
$$;

revoke all on function public.list_operations_tasks(integer) from public, anon;
grant execute on function public.list_operations_tasks(integer) to authenticated, service_role;

create or replace function public.bulk_update_operations_tasks(
  p_task_ids uuid[], p_action text, p_assigned_to uuid default null,
  p_snoozed_until timestamptz default null, p_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_task_ids is null or cardinality(p_task_ids) < 1 or cardinality(p_task_ids) > 100 then
    raise exception 'Select between 1 and 100 tasks';
  end if;
  if p_action not in ('done','reopen','snooze','reassign','escalate') then raise exception 'Invalid task action'; end if;
  if p_action in ('reassign','escalate') and not public.is_admin() then raise exception 'Owner/admin access required'; end if;
  if p_action = 'reassign' and p_assigned_to is not null and not exists (
    select 1 from public.staff_profiles where user_id = p_assigned_to and active = true
  ) then raise exception 'Assigned staff member is not active'; end if;
  if p_action = 'snooze' and (p_snoozed_until is null or p_snoozed_until <= now()) then raise exception 'Choose a future snooze time'; end if;

  update public.tasks_reminders t set
    status = case p_action when 'done' then 'done' when 'reopen' then 'open' when 'snooze' then 'snoozed' else t.status end,
    completed_at = case when p_action = 'done' then now() when p_action = 'reopen' then null else t.completed_at end,
    snoozed_until = case when p_action = 'snooze' then p_snoozed_until when p_action = 'reopen' then null else t.snoozed_until end,
    assigned_to = case when p_action = 'reassign' then p_assigned_to else t.assigned_to end,
    escalated_at = case when p_action = 'escalate' then now() when p_action = 'reopen' then null else t.escalated_at end,
    escalation_reason = case when p_action = 'escalate' then nullif(trim(coalesce(p_reason,'')),'') when p_action = 'reopen' then null else t.escalation_reason end,
    priority = case when p_action = 'escalate' then 'urgent' else t.priority end,
    updated_at = now()
  where t.id = any(p_task_ids)
    and (public.is_admin() or t.assigned_to is null or t.assigned_to = auth.uid());
  get diagnostics v_count = row_count;

  insert into public.audit_events(actor_user_id,event_type,entity_type,metadata)
  values(auth.uid(),'task.bulk_' || p_action,'task',jsonb_build_object('task_ids',p_task_ids,'count',v_count,'assigned_to',p_assigned_to,'snoozed_until',p_snoozed_until,'reason',p_reason));
  return v_count;
end;
$$;

revoke all on function public.bulk_update_operations_tasks(uuid[],text,uuid,timestamptz,text) from public, anon;
grant execute on function public.bulk_update_operations_tasks(uuid[],text,uuid,timestamptz,text) to authenticated, service_role;

-- Align legacy booking helpers with the live task status vocabulary.
create or replace function public.complete_booking_task(p_task_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare v_booking_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings')) then raise exception 'Booking task permission required'; end if;
  update public.tasks_reminders set status='done',completed_at=now(),updated_at=now()
  where id=p_task_id and entity_type='booking' and status<>'done' returning entity_id into v_booking_id;
  if not found then raise exception 'Open booking task not found'; end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(auth.uid(),'booking.task_completed','booking',v_booking_id,jsonb_build_object('task_id',p_task_id));
  return true;
end; $$;

revoke all on function public.complete_booking_task(uuid) from public, anon;
grant execute on function public.complete_booking_task(uuid) to authenticated, service_role;

comment on function public.list_operations_tasks(integer) is 'Role-aware unified work queue across operational entities.';
commit;
