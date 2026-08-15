create or replace function public.get_integration_health_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public, cron
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_staff_permission('manage_settings')
    or public.has_staff_permission('view_reports')
    or public.has_staff_permission('view_activity')
  ) then raise exception 'Permission denied'; end if;

  select jsonb_build_object(
    'generated_at', now(),
    'overall_status', case
      when exists (
        select 1 from public.integration_operations
        where status='failed' and started_at >= now()-interval '24 hours'
      ) or exists (
        select 1 from public.staff_notification_email_deliveries
        where status='failed' and attempted_at >= now()-interval '24 hours'
      ) or exists (
        select 1 from public.staff_digest_email_deliveries
        where status='failed' and attempted_at >= now()-interval '24 hours'
      ) then 'degraded'
      when exists (
        select 1 from public.integration_operations
        where status='processing' and started_at < now()-interval '15 minutes'
      ) or exists (
        select 1 from public.staff_notification_email_deliveries
        where status='processing' and attempted_at < now()-interval '15 minutes'
      ) or exists (
        select 1 from public.staff_digest_email_deliveries
        where status='processing' and attempted_at < now()-interval '15 minutes'
      ) then 'attention'
      else 'healthy' end,
    'microsoft_documents', jsonb_build_object(
      'failed_24h', (select count(*) from public.integration_operations
        where integration='microsoft_documents' and status='failed'
          and started_at >= now()-interval '24 hours'),
      'stuck', (select count(*) from public.integration_operations
        where integration='microsoft_documents' and status='processing'
          and started_at < now()-interval '15 minutes'),
      'last_success_at', (select max(completed_at) from public.integration_operations
        where integration='microsoft_documents' and status='succeeded')
    ),
    'staff_notification_email', jsonb_build_object(
      'failed_24h', (select count(*) from public.staff_notification_email_deliveries
        where status='failed' and attempted_at >= now()-interval '24 hours'),
      'stuck', (select count(*) from public.staff_notification_email_deliveries
        where status='processing' and attempted_at < now()-interval '15 minutes'),
      'last_success_at', (select max(sent_at) from public.staff_notification_email_deliveries
        where status='sent')
    ),
    'operations_digest', jsonb_build_object(
      'failed_24h', (select count(*) from public.staff_digest_email_deliveries
        where status='failed' and attempted_at >= now()-interval '24 hours'),
      'stuck', (select count(*) from public.staff_digest_email_deliveries
        where status='processing' and attempted_at < now()-interval '15 minutes'),
      'last_success_at', (select max(sent_at) from public.staff_digest_email_deliveries
        where status='sent')
    ),
    'scheduled_automation', jsonb_build_object(
      'active', exists (select 1 from cron.job
        where jobname='kridiya-operations-automation' and active),
      'failed_24h', coalesce((select count(*) from cron.job_run_details d
        join cron.job j on j.jobid=d.jobid
        where j.jobname='kridiya-operations-automation'
          and d.status='failed' and d.start_time >= now()-interval '24 hours'),0),
      'last_run_status', (select d.status from cron.job_run_details d
        join cron.job j on j.jobid=d.jobid
        where j.jobname='kridiya-operations-automation'
        order by d.start_time desc limit 1),
      'last_run_at', (select d.start_time from cron.job_run_details d
        join cron.job j on j.jobid=d.jobid
        where j.jobname='kridiya-operations-automation'
        order by d.start_time desc limit 1)
    ),
    'recent_failures', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', io.id, 'integration', io.integration, 'operation', io.operation,
        'entity_type', io.entity_type, 'entity_id', io.entity_id,
        'http_status', io.http_status, 'error', io.last_error,
        'started_at', io.started_at
      ) order by io.started_at desc)
      from (select * from public.integration_operations
        where status='failed' order by started_at desc limit 20) io
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

revoke execute on function public.get_integration_health_snapshot()
from public, anon;
grant execute on function public.get_integration_health_snapshot()
to authenticated, service_role;

