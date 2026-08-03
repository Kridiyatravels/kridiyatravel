begin;

drop policy if exists "marketing_suppression_insert_public"
  on public.marketing_suppression_events;
revoke insert on public.marketing_suppression_events
  from anon, authenticated;

commit;
