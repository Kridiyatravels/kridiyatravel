begin;

alter table public.marketing_suppression_events
  drop constraint if exists marketing_suppression_source_public;
alter table public.marketing_suppression_events
  add constraint marketing_suppression_source_public
  check (source in ('website_unsubscribe', 'signed_unsubscribe'));

drop policy if exists "marketing_suppression_insert_public" on public.marketing_suppression_events;
-- Keep the existing public website path available during the zero-downtime
-- rollout. A follow-up migration removes this policy and grant only after the
-- signed frontend is live and verified.
grant insert on public.marketing_suppression_events to service_role;

create table if not exists public.marketing_unsubscribe_requests (
  id bigint generated always as identity primary key,
  ip_hash text not null check (ip_hash ~ '^[0-9a-f]{64}$'),
  email_hash text not null check (email_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index if not exists marketing_unsubscribe_requests_ip_time_idx
  on public.marketing_unsubscribe_requests (ip_hash, created_at desc);
create index if not exists marketing_unsubscribe_requests_email_time_idx
  on public.marketing_unsubscribe_requests (email_hash, created_at desc);
alter table public.marketing_unsubscribe_requests enable row level security;
revoke all on public.marketing_unsubscribe_requests from public, anon, authenticated;
grant select, insert, delete on public.marketing_unsubscribe_requests to service_role;

create or replace function public.admit_marketing_unsubscribe(
  p_ip_hash text,
  p_email_hash text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_ip_hash !~ '^[0-9a-f]{64}$' or p_email_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  -- Serialize requests for the same address or client so concurrent calls
  -- cannot race past the limits.
  perform pg_advisory_xact_lock(hashtextextended(p_ip_hash, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_email_hash, 1));

  delete from public.marketing_unsubscribe_requests
  where created_at < now() - interval '24 hours';

  if (select count(*) from public.marketing_unsubscribe_requests
      where ip_hash = p_ip_hash
        and created_at >= now() - interval '15 minutes') >= 5 then
    return false;
  end if;

  if (select count(*) from public.marketing_unsubscribe_requests
      where email_hash = p_email_hash
        and created_at >= now() - interval '1 hour') >= 3 then
    return false;
  end if;

  insert into public.marketing_unsubscribe_requests (ip_hash, email_hash)
  values (p_ip_hash, p_email_hash);
  return true;
end;
$$;
revoke execute on function public.admit_marketing_unsubscribe(text, text)
  from public, anon, authenticated;
grant execute on function public.admit_marketing_unsubscribe(text, text)
  to service_role;

-- Repeated confirmation links are idempotent and reveal no subscription state.
create unique index if not exists marketing_suppression_signed_email_idx
  on public.marketing_suppression_events (email)
  where source = 'signed_unsubscribe';

commit;
