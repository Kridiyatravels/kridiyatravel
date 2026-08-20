-- Keep direct Data API mutations aligned with the security-definer document
-- RPCs. Customer/corporate document reads are intentionally unchanged.

drop policy if exists booking_documents_insert_staff
  on public.booking_documents;

create policy booking_documents_insert_staff
  on public.booking_documents
  for insert
  to authenticated
  with check (
    public.has_staff_permission('generate_documents')
    or public.has_staff_permission('edit_bookings')
  );

drop policy if exists booking_documents_update_staff
  on public.booking_documents;

create policy booking_documents_update_staff
  on public.booking_documents
  for update
  to authenticated
  using (
    public.has_staff_permission('generate_documents')
    or public.has_staff_permission('edit_bookings')
  )
  with check (
    public.has_staff_permission('generate_documents')
    or public.has_staff_permission('edit_bookings')
  );
