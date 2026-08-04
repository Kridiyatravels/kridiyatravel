begin;

create or replace function public.operations_command_metrics()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select case when auth.uid() is null or not public.is_staff() then null else jsonb_build_object(
    'is_admin', public.is_admin(),
    'enquiries_30d', (select count(*) from public.enquiries where created_at >= now() - interval '30 days'),
    'enquiries_won_30d', (select count(*) from public.enquiries where created_at >= now() - interval '30 days' and pipeline_stage in ('won', 'booking')),
    'conversion_rate_30d', (
      select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where pipeline_stage in ('won', 'booking')) / count(*), 1) end
      from public.enquiries where created_at >= now() - interval '30 days'
    ),
    'sla_breaches_open', (
      select count(*) from public.enquiries
      where status <> 'closed' and first_response_at is null
        and sla_first_response_due_at is not null and sla_first_response_due_at < now()
    ),
    'sla_met_30d', (
      select count(*) from public.enquiries
      where created_at >= now() - interval '30 days'
        and first_response_at is not null and sla_first_response_due_at is not null
        and first_response_at <= sla_first_response_due_at
    ),
    'sla_responded_30d', (
      select count(*) from public.enquiries
      where created_at >= now() - interval '30 days'
        and first_response_at is not null and sla_first_response_due_at is not null
    ),
    'my_active_tasks', (select count(*) from public.tasks_reminders where assigned_to = auth.uid() and status in ('open', 'snoozed')),
    'my_overdue_tasks', (select count(*) from public.tasks_reminders where assigned_to = auth.uid() and status in ('open', 'snoozed') and due_at < now()),
    'my_due_today', (select count(*) from public.tasks_reminders where assigned_to = auth.uid() and status in ('open', 'snoozed') and due_at::date = current_date),
    'my_completed_7d', (select count(*) from public.tasks_reminders where assigned_to = auth.uid() and status = 'done' and completed_at >= now() - interval '7 days'),
    'workload', case when public.is_admin() then (
      select coalesce(jsonb_agg(row_to_json(w) order by w.overdue desc, w.active_tasks desc, w.full_name), '[]'::jsonb)
      from (
        select sp.user_id, sp.full_name,
          count(t.id) filter (where t.status in ('open', 'snoozed'))::integer as active_tasks,
          count(t.id) filter (where t.status in ('open', 'snoozed') and t.due_at < now())::integer as overdue,
          count(t.id) filter (where t.status = 'done' and t.completed_at >= now() - interval '7 days')::integer as completed_7d
        from public.staff_profiles sp
        left join public.tasks_reminders t on t.assigned_to = sp.user_id
        where sp.active = true and sp.deleted_at is null
        group by sp.user_id, sp.full_name
      ) w
    ) else '[]'::jsonb end
  ) end;
$$;

revoke all on function public.operations_command_metrics() from public, anon, authenticated;
grant execute on function public.operations_command_metrics() to authenticated;

comment on function public.operations_command_metrics() is
  'Role-aware conversion, SLA, personal workload, and admin staff-load metrics for the operations command centre.';

commit;
