-- Add booking workflow tasks and timeline RPCs for staff follow-up tracking.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.get_booking_workflow(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'task_type', t.task_type,
        'entity_type', t.entity_type,
        'entity_id', t.entity_id,
        'assigned_to', t.assigned_to,
        'assigned_to_name', sp.full_name,
        'due_at', t.due_at,
        'status', t.status,
        'priority', t.priority,
        'notes', t.notes,
        'created_by', t.created_by,
        'created_by_name', creator.full_name,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'completed_at', t.completed_at
      ) order by case when t.status = 'completed' then 1 else 0 end, t.due_at nulls last, t.created_at desc)
      from public.tasks_reminders t
      left join public.staff_profiles sp on sp.user_id = t.assigned_to
      left join public.staff_profiles creator on creator.user_id = t.created_by
      where t.entity_type = 'booking'
        and t.entity_id = b.id
    ), '[]'::jsonb),
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ae.id,
        'event_type', ae.event_type,
        'entity_type', ae.entity_type,
        'entity_id', ae.entity_id,
        'actor_user_id', ae.actor_user_id,
        'actor_name', actor.full_name,
        'metadata', ae.metadata,
        'created_at', ae.created_at
      ) order by ae.created_at desc)
      from public.audit_events ae
      left join public.staff_profiles actor on actor.user_id = ae.actor_user_id
      where ae.entity_type = 'booking'
        and ae.entity_id = b.id
      limit 80
    ), '[]'::jsonb),
    'can_edit_tasks', public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings'),
    'can_view_activity', public.has_staff_permission('view_reports') or public.has_staff_permission('edit_bookings')
  )
  from public.bookings b
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    );
$function$;

create or replace function public.create_booking_task(
  p_booking_id uuid,
  p_title text,
  p_task_type text default 'follow_up',
  p_due_at timestamptz default null,
  p_priority text default 'normal',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings')) then
    raise exception 'Booking task permission required';
  end if;
  if nullif(trim(coalesce(p_title, '')), '') is null then
    raise exception 'Task title is required';
  end if;
  if not exists (select 1 from public.bookings where id = p_booking_id and archived_at is null) then
    raise exception 'Booking not found';
  end if;

  insert into public.tasks_reminders (
    title, task_type, entity_type, entity_id, assigned_to,
    due_at, status, priority, notes, created_by
  ) values (
    trim(p_title), coalesce(nullif(trim(coalesce(p_task_type, '')), ''), 'follow_up'), 'booking', p_booking_id, auth.uid(),
    p_due_at, 'pending', coalesce(nullif(trim(coalesce(p_priority, '')), ''), 'normal'), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;

  if p_due_at is not null then
    update public.bookings
    set follow_up_at = p_due_at,
        updated_at = now()
    where id = p_booking_id;
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'booking.task_created',
    'booking',
    p_booking_id,
    jsonb_build_object('task_id', v_id, 'title', p_title, 'task_type', p_task_type, 'due_at', p_due_at, 'priority', p_priority)
  );

  return v_id;
end;
$function$;

create or replace function public.complete_booking_task(p_task_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_booking_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings')) then
    raise exception 'Booking task permission required';
  end if;

  update public.tasks_reminders
  set status = 'completed',
      completed_at = now(),
      updated_at = now()
  where id = p_task_id
    and entity_type = 'booking'
    and status <> 'completed'
  returning entity_id into v_booking_id;

  if not found then
    raise exception 'Open booking task not found';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.task_completed', 'booking', v_booking_id, jsonb_build_object('task_id', p_task_id));

  return true;
end;
$function$;

revoke execute on function public.get_booking_workflow(uuid) from public;
revoke execute on function public.get_booking_workflow(uuid) from anon;
grant execute on function public.get_booking_workflow(uuid) to authenticated;

revoke execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) from public;
revoke execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) from anon;
grant execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) to authenticated;

revoke execute on function public.complete_booking_task(uuid) from public;
revoke execute on function public.complete_booking_task(uuid) from anon;
grant execute on function public.complete_booking_task(uuid) to authenticated;
