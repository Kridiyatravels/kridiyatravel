create or replace function public.owns_customer_payment_for_upload(p_payment_id text,p_require_open boolean default true)
returns boolean language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare v_payment uuid;
begin
  if auth.uid() is null or coalesce(p_payment_id,'') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
  v_payment:=p_payment_id::uuid;
  return exists(select 1 from public.payments p join public.bookings b on b.id=p.booking_id
    where p.id=v_payment and p.payment_direction='customer_in' and b.user_id=auth.uid()
      and (not p_require_open or p.status in ('pending','proof_received')));
end $$;

create or replace function public.can_delete_unattached_customer_payment_proof(p_payment_id text,p_path text)
returns boolean language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare v_payment uuid;
begin
  if not public.owns_customer_payment_for_upload(p_payment_id,false) then return false; end if;
  v_payment:=p_payment_id::uuid;
  return exists(select 1 from public.payments where id=v_payment and proof_storage_path is distinct from p_path);
end $$;

drop policy if exists booking_payment_proofs_insert_customer on storage.objects;
create policy booking_payment_proofs_insert_customer on storage.objects for insert to authenticated
with check (bucket_id='booking-payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text
  and public.owns_customer_payment_for_upload((storage.foldername(name))[2],true));

drop policy if exists booking_payment_proofs_delete_customer on storage.objects;
create policy booking_payment_proofs_delete_customer on storage.objects for delete to authenticated
using (bucket_id='booking-payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text
  and public.can_delete_unattached_customer_payment_proof((storage.foldername(name))[2],name));

revoke execute on function public.owns_customer_payment_for_upload(text,boolean) from public,anon;
grant execute on function public.owns_customer_payment_for_upload(text,boolean) to authenticated,service_role;
revoke execute on function public.can_delete_unattached_customer_payment_proof(text,text) from public,anon;
grant execute on function public.can_delete_unattached_customer_payment_proof(text,text) to authenticated,service_role;
