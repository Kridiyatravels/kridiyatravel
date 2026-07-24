-- Add private booking document storage for staff-managed booking files.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'booking-documents',
  'booking-documents',
  false,
  10485760,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists booking_documents_insert_staff on storage.objects;
drop policy if exists booking_documents_select_staff on storage.objects;
drop policy if exists booking_documents_update_staff on storage.objects;
drop policy if exists booking_documents_delete_staff on storage.objects;

create policy booking_documents_insert_staff
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'booking-documents'
  and (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'))
);

create policy booking_documents_select_staff
on storage.objects for select
to authenticated
using (
  bucket_id = 'booking-documents'
  and (
    public.has_staff_permission('generate_documents')
    or public.has_staff_permission('edit_bookings')
    or public.has_staff_permission('view_reports')
  )
);

create policy booking_documents_update_staff
on storage.objects for update
to authenticated
using (
  bucket_id = 'booking-documents'
  and (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'))
)
with check (
  bucket_id = 'booking-documents'
  and (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'))
);

create policy booking_documents_delete_staff
on storage.objects for delete
to authenticated
using (
  bucket_id = 'booking-documents'
  and (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'))
);

revoke execute on function public.record_booking_document(uuid, text, text, text, text, boolean) from public;
revoke execute on function public.record_booking_document(uuid, text, text, text, text, boolean) from anon;
grant execute on function public.record_booking_document(uuid, text, text, text, text, boolean) to authenticated;

revoke execute on function public.delete_booking_document(uuid) from public;
revoke execute on function public.delete_booking_document(uuid) from anon;
grant execute on function public.delete_booking_document(uuid) to authenticated;
