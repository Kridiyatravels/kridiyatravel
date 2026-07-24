-- Add dashboard booking task list for staff reminders.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.list_dashboard_booking_tasks(limit_count integer default 80)
returns table(
  id uuid,
  title text,
  task_type text,
  entity_id uuid,
  booking_reference text,
  booking_title text,
  service_type public.booking_service_type,
  booking_kind text,
  assigned_to uuid,
  assigned_to_name text,
  due_at timestamp with time zone,
  status text,
  priority text,
  notes text,
  created_at timestamp with time zone,
  due_bucket text
)
language sql
security definer
set search_path to 'public'
as $function$
  select
    t.id,
    t.title,
    t.task_type,
    t.entity_id,
    b.booking_reference,
    b.title as booking_title,
    b.service_type,
    b.booking_kind,
    t.assigned_to,
    sp.full_name as assigned_to_name,
    t.due_at,
    t.status,
    t.priority,
    t.notes,
    t.created_at,
    case
      when t.due_at is null then 'no_due_date'
      when t.due_at < now() then 'overdue'
      when t.due_at < date_trunc('day', now()) + interval '1 day' then 'today'
      when t.due_at < date_trunc('day', now()) + interval '8 days' then 'next_7_days'
      else 'later'
    end as due_bucket
  from public.tasks_reminders t
  join public.bookings b on b.id = t.entity_id
  left join public.staff_profiles sp on sp.user_id = t.assigned_to
  where t.entity_type = 'booking'
    and t.status <> 'completed'
    and b.archived_at is null
    and (
      public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('create_bookings')
      or public.has_staff_permission('view_reports')
      or t.assigned_to = auth.uid()
    )
  order by
    case
      when t.due_at is not null and t.due_at < now() then 0
      when t.due_at is not null and t.due_at < date_trunc('day', now()) + interval '1 day' then 1
      when t.due_at is null then 3
      else 2
    end,
    t.due_at nulls last,
    case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
    t.created_at desc
  limit greatest(1, least(limit_count, 200));
$function$;

revoke execute on function public.list_dashboard_booking_tasks(integer) from public;
revoke execute on function public.list_dashboard_booking_tasks(integer) from anon;
grant execute on function public.list_dashboard_booking_tasks(integer) to authenticated;
