-- Harden staff/admin RPC execute permissions.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

revoke execute on function public.is_admin() from public;
revoke execute on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated, service_role;

revoke execute on function public.is_staff() from public;
revoke execute on function public.is_staff() from anon;
grant execute on function public.is_staff() to authenticated, service_role;

revoke execute on function public.has_staff_permission(text) from public;
revoke execute on function public.has_staff_permission(text) from anon;
grant execute on function public.has_staff_permission(text) to authenticated, service_role;

revoke execute on function public.list_staff() from public;
revoke execute on function public.list_staff() from anon;
grant execute on function public.list_staff() to authenticated, service_role;

revoke execute on function public.grant_staff_by_email(text, public.staff_role) from public;
revoke execute on function public.grant_staff_by_email(text, public.staff_role) from anon;
grant execute on function public.grant_staff_by_email(text, public.staff_role) to authenticated, service_role;

revoke execute on function public.revoke_staff(uuid) from public;
revoke execute on function public.revoke_staff(uuid) from anon;
grant execute on function public.revoke_staff(uuid) to authenticated, service_role;

revoke execute on function public.list_audit_events(integer) from public;
revoke execute on function public.list_audit_events(integer) from anon;
grant execute on function public.list_audit_events(integer) to authenticated, service_role;

revoke execute on function public.staff_email_for_pin(text) from public;
revoke execute on function public.staff_email_for_pin(text) from anon;
revoke execute on function public.staff_email_for_pin(text) from authenticated;
grant execute on function public.staff_email_for_pin(text) to service_role;

revoke execute on function public.staff_dashboard_summary() from public;
revoke execute on function public.staff_dashboard_summary() from anon;
grant execute on function public.staff_dashboard_summary() to authenticated, service_role;

revoke execute on function public.list_corporate_accounts() from public;
revoke execute on function public.list_corporate_accounts() from anon;
grant execute on function public.list_corporate_accounts() to authenticated, service_role;

revoke execute on function public.create_corporate_account(text, text, text, text, text, text, text, text, boolean, boolean, boolean, text, text) from public;
revoke execute on function public.create_corporate_account(text, text, text, text, text, text, text, text, boolean, boolean, boolean, text, text) from anon;
grant execute on function public.create_corporate_account(text, text, text, text, text, text, text, text, boolean, boolean, boolean, text, text) to authenticated, service_role;

revoke execute on function public.create_corporate_contact(uuid, text, text, text, text, text, boolean, boolean, text) from public;
revoke execute on function public.create_corporate_contact(uuid, text, text, text, text, text, boolean, boolean, text) from anon;
grant execute on function public.create_corporate_contact(uuid, text, text, text, text, text, boolean, boolean, text) to authenticated, service_role;

revoke execute on function public.list_operations_bookings(integer) from public;
revoke execute on function public.list_operations_bookings(integer) from anon;
grant execute on function public.list_operations_bookings(integer) to authenticated, service_role;

revoke execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text) from public;
revoke execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text) from anon;
grant execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text) to authenticated, service_role;

revoke execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid) from public;
revoke execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid) from anon;
grant execute on function public.create_operations_booking(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid) to authenticated, service_role;

revoke execute on function public.list_operations_payments(integer) from public;
revoke execute on function public.list_operations_payments(integer) from anon;
grant execute on function public.list_operations_payments(integer) to authenticated, service_role;

revoke execute on function public.update_operations_booking_status(uuid, public.booking_status, text, text, text, text) from public;
revoke execute on function public.update_operations_booking_status(uuid, public.booking_status, text, text, text, text) from anon;
grant execute on function public.update_operations_booking_status(uuid, public.booking_status, text, text, text, text) to authenticated, service_role;

revoke execute on function public.record_booking_passenger(uuid, text, text, text, date, text, date, text) from public;
revoke execute on function public.record_booking_passenger(uuid, text, text, text, date, text, date, text) from anon;
grant execute on function public.record_booking_passenger(uuid, text, text, text, date, text, date, text) to authenticated, service_role;

revoke execute on function public.delete_booking_passenger(uuid) from public;
revoke execute on function public.delete_booking_passenger(uuid) from anon;
grant execute on function public.delete_booking_passenger(uuid) to authenticated, service_role;

revoke execute on function public.record_customer_payment(uuid, numeric, text, text, text, text, text) from public;
revoke execute on function public.record_customer_payment(uuid, numeric, text, text, text, text, text) from anon;
grant execute on function public.record_customer_payment(uuid, numeric, text, text, text, text, text) to authenticated, service_role;

revoke execute on function public.record_supplier_payment(uuid, text, numeric, numeric, text, text, text, date, text) from public;
revoke execute on function public.record_supplier_payment(uuid, text, numeric, numeric, text, text, text, date, text) from anon;
grant execute on function public.record_supplier_payment(uuid, text, numeric, numeric, text, text, text, date, text) to authenticated, service_role;

revoke execute on function public.generate_booking_receipt_document(uuid, uuid) from public;
revoke execute on function public.generate_booking_receipt_document(uuid, uuid) from anon;
grant execute on function public.generate_booking_receipt_document(uuid, uuid) to authenticated, service_role;

revoke execute on function public.generate_booking_payment_request_document(uuid, numeric, text) from public;
revoke execute on function public.generate_booking_payment_request_document(uuid, numeric, text) from anon;
grant execute on function public.generate_booking_payment_request_document(uuid, numeric, text) to authenticated, service_role;

revoke execute on function public.get_operations_booking_detail(uuid) from public;
revoke execute on function public.get_operations_booking_detail(uuid) from anon;
grant execute on function public.get_operations_booking_detail(uuid) to authenticated, service_role;

revoke execute on function public.update_booking_corporate_controls(uuid, text, text) from public;
revoke execute on function public.update_booking_corporate_controls(uuid, text, text) from anon;
grant execute on function public.update_booking_corporate_controls(uuid, text, text) to authenticated, service_role;

revoke execute on function public.get_booking_workflow(uuid) from public;
revoke execute on function public.get_booking_workflow(uuid) from anon;
grant execute on function public.get_booking_workflow(uuid) to authenticated, service_role;

revoke execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) from public;
revoke execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) from anon;
grant execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text) to authenticated, service_role;

revoke execute on function public.complete_booking_task(uuid) from public;
revoke execute on function public.complete_booking_task(uuid) from anon;
grant execute on function public.complete_booking_task(uuid) to authenticated, service_role;

revoke execute on function public.list_dashboard_booking_tasks(integer) from public;
revoke execute on function public.list_dashboard_booking_tasks(integer) from anon;
grant execute on function public.list_dashboard_booking_tasks(integer) to authenticated, service_role;

revoke execute on function public.staff_monitoring_summary(integer) from public;
revoke execute on function public.staff_monitoring_summary(integer) from anon;
grant execute on function public.staff_monitoring_summary(integer) to authenticated, service_role;

revoke execute on function public.record_booking_document(uuid, text, text, text, text, boolean) from public;
revoke execute on function public.record_booking_document(uuid, text, text, text, text, boolean) from anon;
grant execute on function public.record_booking_document(uuid, text, text, text, text, boolean) to authenticated, service_role;

revoke execute on function public.delete_booking_document(uuid) from public;
revoke execute on function public.delete_booking_document(uuid) from anon;
grant execute on function public.delete_booking_document(uuid) to authenticated, service_role;
