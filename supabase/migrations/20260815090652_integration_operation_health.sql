create table if not exists public.integration_operations (
  id uuid primary key default gen_random_uuid(),
  integration text not null,
  operation text not null,
  entity_type text,
  entity_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'processing'
    check (status in ('processing','succeeded','failed')),
  http_status integer,
  last_error text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.integration_operations is
  'Service-only durable health ledger for external integration actions. Never stores file contents, tokens or credentials.';

create index if not exists integration_operations_health_idx
on public.integration_operations (integration, status, started_at desc);

create index if not exists integration_operations_entity_idx
on public.integration_operations (entity_type, entity_id, started_at desc)
where entity_id is not null;

alter table public.integration_operations enable row level security;
revoke all on table public.integration_operations from public, anon, authenticated;
grant select, insert, update on table public.integration_operations to service_role;

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
        where status='failed' and created_at >= now()-interval '24 hours'
      ) or exists (
        select 1 from public.staff_digest_email_deliveries
        where status='failed' and created_at >= now()-interval '24 hours'
      ) then 'degraded'
      when exists (
        select 1 from public.integration_operations
        where status='processing' and started_at < now()-interval '15 minutes'
      ) or exists (
        select 1 from public.staff_notification_email_deliveries
        where status='processing' and created_at < now()-interval '15 minutes'
      ) or exists (
        select 1 from public.staff_digest_email_deliveries
        where status='processing' and created_at < now()-interval '15 minutes'
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
        where status='failed' and created_at >= now()-interval '24 hours'),
      'stuck', (select count(*) from public.staff_notification_email_deliveries
        where status='processing' and created_at < now()-interval '15 minutes'),
      'last_success_at', (select max(sent_at) from public.staff_notification_email_deliveries
        where status='sent')
    ),
    'operations_digest', jsonb_build_object(
      'failed_24h', (select count(*) from public.staff_digest_email_deliveries
        where status='failed' and created_at >= now()-interval '24 hours'),
      'stuck', (select count(*) from public.staff_digest_email_deliveries
        where status='processing' and created_at < now()-interval '15 minutes'),
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
