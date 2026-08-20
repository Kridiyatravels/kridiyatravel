begin;

drop policy if exists "enquiries_update_staff" on public.enquiries;

create policy "enquiries_update_staff"
on public.enquiries
for update
to authenticated
using ((select public.has_staff_permission('edit_enquiries')))
with check ((select public.has_staff_permission('edit_enquiries')));

revoke update on table public.enquiries from authenticated;

commit;
