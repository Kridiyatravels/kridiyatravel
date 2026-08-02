begin;

alter table public.marketing_suppression_events
  drop constraint if exists marketing_suppression_source_public;
alter table public.marketing_suppression_events
  add constraint marketing_suppression_source_public
  check (source in ('website_unsubscribe', 'signed_unsubscribe'));

drop policy if exists "marketing_suppression_insert_public" on public.marketing_suppression_events;
revoke insert on public.marketing_suppression_events from anon, authenticated;
grant insert on public.marketing_suppression_events to service_role;

-- Repeated confirmation links are idempotent and reveal no subscription state.
create unique index if not exists marketing_suppression_signed_email_idx
  on public.marketing_suppression_events (email)
  where source = 'signed_unsubscribe';

commit;
