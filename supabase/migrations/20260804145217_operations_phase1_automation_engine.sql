begin;

alter table public.tasks_reminders
  add column if not exists automation_key text;

create unique index if not exists tasks_reminders_automation_key_idx
  on public.tasks_reminders(automation_key) where automation_key is not null;

create or replace function private.refresh_operations_automations()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sla integer := 0;
  v_followups integer := 0;
  v_stale integer := 0;
begin
  -- One urgent alert per enquiry when the one-hour response SLA is breached.
  insert into public.staff_notifications (
    recipient_id, audience, category, priority, title, body,
    entity_type, entity_id, action_url, dedupe_key, metadata
  )
  select e.assigned_staff_id,
         case when e.assigned_staff_id is null then 'admin' else 'personal' end,
         'sla', 'urgent', 'First-response SLA overdue',
         e.reference || ' - ' || e.full_name || ' has not received a recorded first response.',
         'enquiry', e.id, 'admin.html?focus=' || e.id,
         'sla-first-response:' || e.id,
         jsonb_build_object('reference', e.reference, 'due_at', e.sla_first_response_due_at)
  from public.enquiries e
  where e.first_response_at is null
    and e.sla_first_response_due_at < now()
    and e.status <> 'closed'
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics v_sla = row_count;

  -- Quote follow-up: next business action after 24 hours, then an escalation after 72 hours.
  insert into public.tasks_reminders (
    title, task_type, entity_type, entity_id, assigned_to, due_at,
    status, priority, notes, automation_key
  )
  select 'Quote follow-up: ' || e.reference, 'follow_up', 'enquiry', e.id,
         e.assigned_staff_id, e.quote_sent_at + interval '24 hours', 'open',
         case when e.priority = 'urgent' then 'urgent' else 'high' end,
         'Contact the customer, record the outcome, and schedule the next action.',
         'quote-followup-24h:' || e.id
  from public.enquiries e
  where e.quote_sent_at is not null
    and e.quote_sent_at <= now() - interval '24 hours'
    and e.status in ('quote_sent', 'payment_pending')
  on conflict (automation_key) where automation_key is not null do nothing;
  get diagnostics v_followups = row_count;

  insert into public.staff_notifications (
    recipient_id, audience, category, priority, title, body,
    entity_type, entity_id, action_url, dedupe_key, metadata
  )
  select e.assigned_staff_id,
         case when e.assigned_staff_id is null then 'company' else 'personal' end,
         'follow_up', 'high', 'Quote follow-up due',
         e.reference || ' - follow up the quote sent to ' || e.full_name || '.',
         'enquiry', e.id, 'admin.html?focus=' || e.id,
         'quote-followup-24h:' || e.id,
         jsonb_build_object('reference', e.reference, 'quote_sent_at', e.quote_sent_at)
  from public.enquiries e
  where e.quote_sent_at is not null
    and e.quote_sent_at <= now() - interval '24 hours'
    and e.status in ('quote_sent', 'payment_pending')
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  insert into public.staff_notifications (
    recipient_id, audience, category, priority, title, body,
    entity_type, entity_id, action_url, dedupe_key, metadata
  )
  select null, 'admin', 'follow_up', 'urgent', 'Quote inactive for 72 hours',
         e.reference || ' - review ownership, contact attempt, and close or revive the lead.',
         'enquiry', e.id, 'admin.html?focus=' || e.id,
         'quote-followup-72h:' || e.id,
         jsonb_build_object('reference', e.reference, 'assigned_staff_id', e.assigned_staff_id)
  from public.enquiries e
  where e.quote_sent_at is not null
    and e.quote_sent_at <= now() - interval '72 hours'
    and e.status in ('quote_sent', 'payment_pending')
  on conflict (dedupe_key) where dedupe_key is not null do nothing;

  -- Unquoted enquiries with no activity for 24 hours are a sales risk.
  insert into public.staff_notifications (
    recipient_id, audience, category, priority, title, body,
    entity_type, entity_id, action_url, dedupe_key, metadata
  )
  select e.assigned_staff_id,
         case when e.assigned_staff_id is null then 'admin' else 'personal' end,
         'follow_up', 'high', 'Enquiry needs attention',
         e.reference || ' - no quote or recent activity has been recorded for ' || e.full_name || '.',
         'enquiry', e.id, 'admin.html?focus=' || e.id,
         'stale-enquiry-24h:' || e.id,
         jsonb_build_object('reference', e.reference, 'last_activity_at', e.last_activity_at)
  from public.enquiries e
  where e.status in ('received', 'checking_availability')
    and coalesce(e.last_activity_at, e.created_at) <= now() - interval '24 hours'
    and not exists (select 1 from public.quotes q where q.enquiry_id = e.id)
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics v_stale = row_count;

  return jsonb_build_object('sla_alerts', v_sla, 'followup_tasks', v_followups, 'stale_alerts', v_stale, 'ran_at', now());
end;
$$;

revoke all on function private.refresh_operations_automations() from public, anon, authenticated;

-- Safe staff-triggered refresh is useful as a fallback and for immediate dashboard updates.
create or replace function public.refresh_operations_automations()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  return private.refresh_operations_automations();
end;
$$;

revoke all on function public.refresh_operations_automations() from public, anon;
grant execute on function public.refresh_operations_automations() to authenticated, service_role;

-- pg_cron is available on the hosted project. Recreate the named job idempotently.
do $$
declare v_job_id bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    select jobid into v_job_id from cron.job where jobname = 'kridiya-operations-automation' limit 1;
    if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
    perform cron.schedule(
      'kridiya-operations-automation',
      '*/5 * * * *',
      'select private.refresh_operations_automations()'
    );
  end if;
end $$;

comment on function public.refresh_operations_automations() is
  'Creates deduplicated SLA, stale-lead, and quote follow-up tasks and notifications.';

commit;
