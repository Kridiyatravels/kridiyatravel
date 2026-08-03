-- Kridiya Travel: marketing attribution, consent and RevOps foundation.
-- Apply after the existing enquiry and staff-management migrations.

begin;

alter table public.enquiries
  add column if not exists first_touch_source text,
  add column if not exists first_touch_medium text,
  add column if not exists first_touch_campaign text,
  add column if not exists last_touch_source text,
  add column if not exists last_touch_medium text,
  add column if not exists last_touch_campaign text,
  add column if not exists utm_id text,
  add column if not exists utm_source text,
  add column if not exists utm_medium text,
  add column if not exists utm_campaign text,
  add column if not exists utm_content text,
  add column if not exists utm_term text,
  add column if not exists gclid text,
  add column if not exists fbclid text,
  add column if not exists msclkid text,
  add column if not exists ttclid text,
  add column if not exists landing_page text,
  add column if not exists referrer text,
  add column if not exists traffic_type text,
  add column if not exists source_basis text,
  add column if not exists source_confidence text,
  add column if not exists self_reported_source text,
  add column if not exists assigned_staff_id uuid references auth.users(id) on delete set null,
  add column if not exists first_response_at timestamptz,
  add column if not exists qualified_at timestamptz,
  add column if not exists quote_sent_at timestamptz,
  add column if not exists booking_confirmed_at timestamptz,
  add column if not exists next_action text,
  add column if not exists next_action_at timestamptz,
  add column if not exists lead_temperature text,
  add column if not exists lead_score integer,
  add column if not exists estimated_booking_value numeric(14,2),
  add column if not exists estimated_gross_profit numeric(14,2),
  add column if not exists lost_reason text,
  add column if not exists marketing_consent boolean not null default false,
  add column if not exists marketing_consent_at timestamptz,
  add column if not exists marketing_consent_source text,
  add column if not exists marketing_consent_version text,
  add column if not exists unsubscribe_at timestamptz,
  add column if not exists review_requested_at timestamptz,
  add column if not exists referral_source_customer_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'enquiries_traffic_type_check' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_traffic_type_check
      check (traffic_type is null or traffic_type in ('paid', 'organic', 'direct', 'referral', 'unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_source_confidence_check' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_source_confidence_check
      check (source_confidence is null or source_confidence in ('high', 'medium', 'low'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_lead_temperature_check' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_lead_temperature_check
      check (lead_temperature is null or lead_temperature in ('cold', 'warm', 'hot'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_lead_score_check' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_lead_score_check
      check (lead_score is null or lead_score between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_lost_reason_check' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_lost_reason_check
      check (lost_reason is null or lost_reason in (
        'price', 'no_response', 'dates_changed', 'not_available',
        'booked_elsewhere', 'duplicate', 'invalid_enquiry',
        'visa_ineligible', 'payment_issue', 'other'
      ));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'enquiries_marketing_consent_consistency' and conrelid = 'public.enquiries'::regclass) then
    alter table public.enquiries add constraint enquiries_marketing_consent_consistency
      check (
        (marketing_consent = false and marketing_consent_at is null and marketing_consent_source is null and marketing_consent_version is null)
        or
        (marketing_consent = true and marketing_consent_at is not null and marketing_consent_source is not null and marketing_consent_version is not null)
      );
  end if;
end $$;

create index if not exists enquiries_assigned_staff_idx on public.enquiries(assigned_staff_id);
create index if not exists enquiries_next_action_idx on public.enquiries(next_action_at) where next_action_at is not null;
create index if not exists enquiries_utm_campaign_idx on public.enquiries(utm_campaign) where utm_campaign is not null;
create index if not exists enquiries_lost_reason_idx on public.enquiries(lost_reason) where lost_reason is not null;

-- Public visitors may supply attribution and optional marketing consent,
-- but cannot set staff-only workflow or financial values.
drop policy if exists "enquiries_insert_public" on public.enquiries;
create policy "enquiries_insert_public"
on public.enquiries for insert
to anon, authenticated
with check (
  status = 'received'
  and (user_id is null or user_id = auth.uid())
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

create table if not exists public.marketing_subscription_events (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  consent boolean not null default true,
  consent_at timestamptz not null default now(),
  consent_source text not null default 'website_footer',
  consent_version text not null default 'privacy-2026-07',
  first_touch_source text,
  first_touch_medium text,
  first_touch_campaign text,
  last_touch_source text,
  last_touch_medium text,
  last_touch_campaign text,
  landing_page text,
  referrer text,
  created_at timestamptz not null default now(),
  constraint marketing_subscription_email_length check (char_length(trim(email)) between 5 and 320),
  constraint marketing_subscription_public_consent check (consent = true)
);

create index if not exists marketing_subscription_events_email_idx on public.marketing_subscription_events(lower(email));
create index if not exists marketing_subscription_events_created_at_idx on public.marketing_subscription_events(created_at desc);

alter table public.marketing_subscription_events enable row level security;

drop policy if exists "marketing_subscription_insert_public" on public.marketing_subscription_events;
create policy "marketing_subscription_insert_public"
on public.marketing_subscription_events for insert
to anon, authenticated
  with check (
  consent = true
  and consent_source = 'website_footer'
  and consent_version = 'privacy-2026-07'
  and consent_at between now() - interval '10 minutes' and now() + interval '5 minutes'
);

drop policy if exists "marketing_subscription_select_staff" on public.marketing_subscription_events;
create policy "marketing_subscription_select_staff"
on public.marketing_subscription_events for select
to authenticated
using (public.is_staff());

revoke all on public.marketing_subscription_events from anon, authenticated;
grant insert on public.marketing_subscription_events to anon, authenticated;
grant select on public.marketing_subscription_events to authenticated;

commit;
