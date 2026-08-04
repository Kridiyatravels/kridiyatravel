begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.enquiries
  add column if not exists pipeline_stage text not null default 'new',
  add column if not exists priority text not null default 'normal',
  add column if not exists conversion_probability integer,
  add column if not exists preferred_contact_channel text,
  add column if not exists customer_language text,
  add column if not exists travel_deadline date,
  add column if not exists tags text[] not null default '{}'::text[],
  add column if not exists sla_first_response_due_at timestamptz,
  add column if not exists last_activity_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'enquiries_pipeline_stage_check') then
    alter table public.enquiries add constraint enquiries_pipeline_stage_check check (pipeline_stage in (
      'new', 'contacted', 'qualified', 'checking_availability', 'quote_preparation',
      'quote_sent', 'follow_up', 'accepted', 'booking', 'won', 'lost',
      'not_eligible', 'duplicate', 'test_archived', 'no_response'
    ));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_priority_check') then
    alter table public.enquiries add constraint enquiries_priority_check
      check (priority in ('low', 'normal', 'high', 'urgent'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_conversion_probability_check') then
    alter table public.enquiries add constraint enquiries_conversion_probability_check
      check (conversion_probability is null or conversion_probability between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_preferred_contact_check') then
    alter table public.enquiries add constraint enquiries_preferred_contact_check
      check (preferred_contact_channel is null or preferred_contact_channel in ('phone', 'whatsapp', 'email', 'other'));
  end if;
end $$;

create index if not exists enquiries_pipeline_stage_idx on public.enquiries(pipeline_stage, created_at desc);
create index if not exists enquiries_priority_idx on public.enquiries(priority, created_at desc);
create index if not exists enquiries_sla_due_idx on public.enquiries(sla_first_response_due_at)
  where first_response_at is null and sla_first_response_due_at is not null;

-- Keep the public form strictly separated from staff-only workflow controls.
drop policy if exists "enquiries_insert_public" on public.enquiries;
create policy "enquiries_insert_public"
on public.enquiries for insert
to anon, authenticated
with check (
  status = 'received'
  and pipeline_stage = 'new'
  and priority = 'normal'
  and conversion_probability is null
  and preferred_contact_channel is null
  and customer_language is null
  and travel_deadline is null
  and tags = '{}'::text[]
  and (user_id is null or user_id = (select auth.uid()))
  and assigned_staff_id is null
  and first_response_at is null and qualified_at is null
  and quote_sent_at is null and booking_confirmed_at is null
  and next_action is null and next_action_at is null
  and lead_temperature is null and lead_score is null
  and estimated_booking_value is null and estimated_gross_profit is null
  and lost_reason is null and unsubscribe_at is null
  and review_requested_at is null
  and (
    marketing_consent = false
    or (
      marketing_consent_at between now() - interval '10 minutes' and now() + interval '5 minutes'
      and marketing_consent_source = 'website_enquiry'
      and marketing_consent_version = 'privacy-2026-07'
    )
  )
);

create table if not exists public.staff_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  in_app_enabled boolean not null default true,
  email_new_enquiry boolean not null default true,
  email_assignment boolean not null default true,
  email_sla_escalation boolean not null default true,
  email_daily_digest boolean not null default true,
  email_overdue_digest boolean not null default true,
  email_weekly_owner_report boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  timezone text not null default 'Asia/Dubai',
  updated_at timestamptz not null default now()
);

alter table public.staff_notification_preferences enable row level security;

drop policy if exists staff_notification_preferences_select on public.staff_notification_preferences;
create policy staff_notification_preferences_select on public.staff_notification_preferences
  for select to authenticated
  using (public.is_admin() or user_id = (select auth.uid()));

drop policy if exists staff_notification_preferences_insert on public.staff_notification_preferences;
create policy staff_notification_preferences_insert on public.staff_notification_preferences
  for insert to authenticated
  with check (public.is_admin() or user_id = (select auth.uid()));

drop policy if exists staff_notification_preferences_update on public.staff_notification_preferences;
create policy staff_notification_preferences_update on public.staff_notification_preferences
  for update to authenticated
  using (public.is_admin() or user_id = (select auth.uid()))
  with check (public.is_admin() or user_id = (select auth.uid()));

revoke all on public.staff_notification_preferences from public, anon, authenticated;
grant select, insert, update on public.staff_notification_preferences to authenticated;

create table if not exists public.staff_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid references auth.users(id) on delete cascade,
  audience text not null default 'company' check (audience in ('personal', 'company', 'admin')),
  category text not null check (category in (
    'new_enquiry', 'assignment', 'sla', 'follow_up', 'quote', 'payment', 'document',
    'supplier', 'departure', 'sharepoint', 'security', 'system'
  )),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  title text not null check (char_length(trim(title)) between 2 and 180),
  body text not null default '' check (char_length(body) <= 1000),
  entity_type text,
  entity_id uuid,
  action_url text,
  status text not null default 'unread' check (status in ('unread', 'read', 'done', 'snoozed')),
  read_at timestamptz,
  snoozed_until timestamptz,
  dedupe_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists staff_notifications_dedupe_idx
  on public.staff_notifications(dedupe_key) where dedupe_key is not null;
create index if not exists staff_notifications_recipient_idx
  on public.staff_notifications(recipient_id, status, created_at desc);
create index if not exists staff_notifications_company_idx
  on public.staff_notifications(audience, status, created_at desc);

drop trigger if exists staff_notifications_set_updated_at on public.staff_notifications;
create trigger staff_notifications_set_updated_at
before update on public.staff_notifications
for each row execute function public.set_updated_at();

alter table public.staff_notifications enable row level security;

drop policy if exists staff_notifications_select on public.staff_notifications;
create policy staff_notifications_select on public.staff_notifications
  for select to authenticated
  using (
    public.is_staff() and (
      recipient_id = (select auth.uid())
      or (recipient_id is null and audience = 'company')
      or (recipient_id is null and audience = 'admin' and public.is_admin())
    )
  );

drop policy if exists staff_notifications_update on public.staff_notifications;
create policy staff_notifications_update on public.staff_notifications
  for update to authenticated
  using (
    public.is_staff() and (
      recipient_id = (select auth.uid())
      or (recipient_id is null and audience = 'company')
      or (recipient_id is null and audience = 'admin' and public.is_admin())
    )
  )
  with check (
    public.is_staff() and (
      recipient_id = (select auth.uid())
      or (recipient_id is null and audience = 'company')
      or (recipient_id is null and audience = 'admin' and public.is_admin())
    )
  );

revoke all on public.staff_notifications from public, anon, authenticated;
grant select, update on public.staff_notifications to authenticated;

create or replace function private.initialise_enquiry_operations()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.pipeline_stage := coalesce(nullif(new.pipeline_stage, ''), 'new');
  new.priority := coalesce(nullif(new.priority, ''), 'normal');
  new.sla_first_response_due_at := new.created_at + interval '1 hour';
  new.last_activity_at := new.created_at;
  return new;
end;
$$;

revoke all on function private.initialise_enquiry_operations() from public, anon, authenticated;

drop trigger if exists enquiries_initialise_operations on public.enquiries;
create trigger enquiries_initialise_operations
before insert on public.enquiries
for each row execute function private.initialise_enquiry_operations();

create or replace function private.notify_new_enquiry()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.staff_notifications (
    recipient_id, audience, category, priority, title, body,
    entity_type, entity_id, action_url, dedupe_key, metadata
  ) values (
    new.assigned_staff_id,
    case when new.assigned_staff_id is null then 'company' else 'personal' end,
    'new_enquiry',
    case when new.priority in ('high', 'urgent') then new.priority else 'normal' end,
    'New ' || initcap(replace(new.service_type, '_', ' ')) || ' enquiry',
    new.reference || ' - ' || new.full_name || ': ' || left(new.summary, 300),
    'enquiry', new.id, 'admin.html?focus=' || new.id,
    'new-enquiry:' || new.id,
    jsonb_build_object('reference', new.reference, 'service_type', new.service_type)
  ) on conflict (dedupe_key) where dedupe_key is not null do nothing;

  insert into public.tasks_reminders (
    title, task_type, entity_type, entity_id, assigned_to,
    due_at, status, priority, notes, created_by
  ) values (
    'First response: ' || new.reference,
    'follow_up', 'enquiry', new.id, new.assigned_staff_id,
    new.sla_first_response_due_at, 'open',
    case when new.priority in ('high', 'urgent') then new.priority else 'normal' end,
    'Contact the customer and record the first response.', null
  );

  return new;
end;
$$;

revoke all on function private.notify_new_enquiry() from public, anon, authenticated;

drop trigger if exists enquiries_notify_new on public.enquiries;
create trigger enquiries_notify_new
after insert on public.enquiries
for each row execute function private.notify_new_enquiry();

create or replace function public.assign_enquiry(
  p_enquiry_id uuid,
  p_assigned_staff_id uuid,
  p_priority text default null
)
returns public.enquiries
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_row public.enquiries;
begin
  if (select auth.uid()) is null or not public.is_staff() then
    raise exception 'Staff access required';
  end if;
  if p_assigned_staff_id is not null and not exists (
    select 1 from public.staff_profiles where user_id = p_assigned_staff_id and active = true
  ) then
    raise exception 'Assigned staff member is not active';
  end if;
  if p_priority is not null and p_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'Invalid priority';
  end if;

  update public.enquiries
  set assigned_staff_id = p_assigned_staff_id,
      priority = coalesce(p_priority, priority),
      last_activity_at = now()
  where id = p_enquiry_id
  returning * into v_row;

  if not found then raise exception 'Enquiry not found'; end if;

  update public.tasks_reminders
  set assigned_to = p_assigned_staff_id,
      priority = coalesce(p_priority, priority)
  where entity_type = 'enquiry' and entity_id = p_enquiry_id and status in ('open', 'snoozed');

  if p_assigned_staff_id is not null then
    insert into public.staff_notifications (
      recipient_id, audience, category, priority, title, body,
      entity_type, entity_id, action_url, dedupe_key, created_by
    ) values (
      p_assigned_staff_id, 'personal', 'assignment', coalesce(p_priority, v_row.priority),
      'Enquiry assigned to you', v_row.reference || ' - ' || v_row.full_name,
      'enquiry', v_row.id, 'admin.html?focus=' || v_row.id,
      'assignment:' || v_row.id || ':' || p_assigned_staff_id, (select auth.uid())
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end if;

  return v_row;
end;
$$;

revoke all on function public.assign_enquiry(uuid, uuid, text) from public, anon;
grant execute on function public.assign_enquiry(uuid, uuid, text) to authenticated, service_role;

comment on table public.staff_notifications is 'Unified in-app operational notification inbox for Kridiya staff.';
comment on table public.staff_notification_preferences is 'Per-staff operational notification and digest preferences.';

commit;
