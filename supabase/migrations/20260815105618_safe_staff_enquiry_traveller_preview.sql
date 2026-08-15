create or replace function public.list_enquiry_primary_travellers()
returns table(
  enquiry_id uuid,
  traveller_id uuid,
  full_name text,
  date_of_birth date,
  nationality text,
  passport_expiry date
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select e.id,t.id,t.full_name,t.date_of_birth,t.nationality,t.passport_expiry
  from public.enquiries e
  join public.travellers t on t.id=e.primary_traveller_id
  where auth.uid() is not null and public.is_staff()
$$;

revoke execute on function public.list_enquiry_primary_travellers() from public,anon;
grant execute on function public.list_enquiry_primary_travellers() to authenticated,service_role;

