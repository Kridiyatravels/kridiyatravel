begin;

-- The operations digest Edge Function uses the Supabase secret/service role.
-- RLS bypass does not replace SQL table privileges, so grant only the access
-- required to load recipients/tasks and maintain idempotent delivery history.
grant select on table
  public.staff_profiles,
  public.staff_notification_preferences,
  public.staff_roles,
  public.tasks_reminders
to service_role;

grant select, insert, update, delete on table
  public.staff_digest_email_deliveries
to service_role;

grant insert on table public.audit_events to service_role;

commit;
