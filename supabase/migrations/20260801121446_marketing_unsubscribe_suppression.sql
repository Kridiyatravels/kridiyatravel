-- Kridiya Travel: public unsubscribe capture and staff-only suppression enforcement.

begin;

create table if not exists public.marketing_suppression_events (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'website_unsubscribe',
  requested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint marketing_suppression_email_length
    check (char_length(trim(email)) between 5 and 320),
  constraint marketing_suppression_email_normalized
    check (email = lower(trim(email))),
  constraint marketing_suppression_source_public
    check (source = 'website_unsubscribe'),
  constraint marketing_suppression_requested_at_recent
    check (requested_at between created_at - interval '10 minutes' and created_at + interval '5 minutes')
);

create index if not exists marketing_suppression_events_email_idx
  on public.marketing_suppression_events (email);
create index if not exists marketing_suppression_events_created_at_idx
  on public.marketing_suppression_events (created_at desc);

alter table public.marketing_suppression_events enable row level security;

drop policy if exists "marketing_suppression_insert_public" on public.marketing_suppression_events;
create policy "marketing_suppression_insert_public"
on public.marketing_suppression_events for insert
to anon, authenticated
with check (
  source = 'website_unsubscribe'
  and email = lower(trim(email))
  and requested_at between now() - interval '10 minutes' and now() + interval '5 minutes'
);

drop policy if exists "marketing_suppression_select_staff" on public.marketing_suppression_events;
create policy "marketing_suppression_select_staff"
on public.marketing_suppression_events for select
to authenticated
using (public.is_staff());

revoke all on public.marketing_suppression_events from anon, authenticated;
grant insert on public.marketing_suppression_events to anon, authenticated;
grant select on public.marketing_suppression_events to authenticated;

-- Keep enquiry-level consent state aligned when an unsubscribe is submitted.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.apply_marketing_suppression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.enquiries
  set marketing_consent = false,
      marketing_consent_at = null,
      marketing_consent_source = null,
      marketing_consent_version = null,
      unsubscribe_at = new.requested_at
  where lower(trim(email)) = new.email
    and unsubscribe_at is null;
  return new;
end;
$$;

revoke all on function private.apply_marketing_suppression() from public, anon, authenticated;

drop trigger if exists marketing_suppression_apply_to_enquiries
  on public.marketing_suppression_events;
create trigger marketing_suppression_apply_to_enquiries
after insert on public.marketing_suppression_events
for each row execute function private.apply_marketing_suppression();

-- This is the only list staff should export for promotional email campaigns.
create or replace view public.marketing_eligible_contacts
with (security_invoker = true)
as
with consented as (
  select lower(trim(email)) as email, max(consent_at) as consent_at
  from public.marketing_subscription_events
  where consent = true
  group by lower(trim(email))
  union all
  select lower(trim(email)) as email, max(marketing_consent_at) as consent_at
  from public.enquiries
  where marketing_consent = true
    and marketing_consent_at is not null
  group by lower(trim(email))
), latest as (
  select email, max(consent_at) as latest_consent_at
  from consented
  group by email
)
select latest.email, latest.latest_consent_at
from latest
where not exists (
  select 1
  from public.marketing_suppression_events suppressed
  where suppressed.email = latest.email
);

revoke all on public.marketing_eligible_contacts from anon, authenticated;
grant select on public.marketing_eligible_contacts to authenticated;

commit;
