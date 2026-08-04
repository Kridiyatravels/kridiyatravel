begin;

-- assign_enquiry is an atomic workflow command: it updates the enquiry,
-- synchronises its open tasks, and creates a recipient-scoped notification.
-- Direct INSERT access to staff_notifications intentionally remains denied.
-- The function already validates authentication, staff membership, target
-- staff activity, and priority before touching any rows.
alter function public.assign_enquiry(uuid, uuid, text) security definer;

revoke all on function public.assign_enquiry(uuid, uuid, text) from public, anon;
grant execute on function public.assign_enquiry(uuid, uuid, text) to authenticated, service_role;

comment on function public.assign_enquiry(uuid, uuid, text) is
  'Authorized atomic enquiry assignment command; synchronizes related tasks and recipient notification without exposing direct notification inserts.';

commit;
