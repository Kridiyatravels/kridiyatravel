alter table public.payments
  add column if not exists proof_mime_type text,
  add column if not exists proof_size_bytes bigint check (proof_size_bytes is null or proof_size_bytes between 1 and 10485760),
  add column if not exists proof_source text check (proof_source is null or proof_source in ('customer','staff'));

drop policy if exists booking_payment_proofs_insert_customer on storage.objects;
create policy booking_payment_proofs_insert_customer on storage.objects for insert to authenticated
with check (
  bucket_id='booking-payment-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text
  and coalesce((storage.foldername(name))[2],'') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (
    select 1 from public.payments p join public.bookings b on b.id=p.booking_id
    where p.id=((storage.foldername(name))[2])::uuid and p.payment_direction='customer_in'
      and p.status in ('pending','proof_received') and b.user_id=auth.uid()
  )
);

drop policy if exists booking_payment_proofs_delete_customer on storage.objects;
create policy booking_payment_proofs_delete_customer on storage.objects for delete to authenticated
using (
  bucket_id='booking-payment-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text
  and coalesce((storage.foldername(name))[2],'') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (
    select 1 from public.payments p join public.bookings b on b.id=p.booking_id
    where p.id=((storage.foldername(name))[2])::uuid and b.user_id=auth.uid()
      and p.proof_storage_path is distinct from name
  )
);

create or replace function public.attach_my_payment_proof(p_payment_id uuid,p_storage_path text,p_file_name text,p_mime_type text,p_size_bytes bigint)
returns boolean language plpgsql security definer set search_path=public,storage,pg_temp
as $$
declare v_user uuid:=auth.uid(); v_booking uuid; v_reference text; v_old_path text; v_uploaded timestamptz:=now();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp') then raise exception 'Only PDF, JPG, PNG or WebP proof files are allowed'; end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then raise exception 'Proof file must be 10 MB or smaller'; end if;
  if char_length(btrim(coalesce(p_file_name,''))) not between 1 and 180 then raise exception 'Invalid proof file name'; end if;
  if p_storage_path !~ ('^'||v_user::text||'/'||p_payment_id::text||'/[0-9]+-[A-Za-z0-9._-]+$') then raise exception 'Invalid customer proof path'; end if;
  if not exists(select 1 from storage.objects where bucket_id='booking-payment-proofs' and name=p_storage_path and owner_id=v_user::text) then raise exception 'Uploaded proof file was not found'; end if;

  update public.payments p set proof_storage_path=p_storage_path,proof_file_name=btrim(p_file_name),proof_uploaded_by=v_user,
    proof_uploaded_at=v_uploaded,proof_mime_type=p_mime_type,proof_size_bytes=p_size_bytes,proof_source='customer',proof_storage_provider='supabase',
    status=case when p.status='pending' then 'proof_received' else p.status end,updated_at=now()
  from public.bookings b where p.id=p_payment_id and b.id=p.booking_id and b.user_id=v_user
    and p.payment_direction='customer_in' and p.status in ('pending','proof_received')
  returning p.booking_id,p.payment_reference,p.proof_storage_path into v_booking,v_reference,v_old_path;
  if not found then raise exception 'Open customer payment was not found for this account'; end if;

  update public.bookings set payment_status='proof_received',updated_at=now()
  where id=v_booking and payment_status in ('not_requested','request_sent','proof_received');
  insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,notes,created_by,automation_key)
  values('Verify customer payment proof','payment_reminder','payment',p_payment_id,now()+interval '2 hours','high','Customer uploaded payment proof. Verify funds before marking payment received.',v_user,'customer-proof:'||p_payment_id)
  on conflict (automation_key) where automation_key is not null do update set status='open',due_at=excluded.due_at,priority='high',notes=excluded.notes,updated_at=now();
  insert into public.staff_notifications(audience,category,priority,title,body,entity_type,entity_id,action_url,dedupe_key,metadata,created_by)
  values('company','payment','high','Customer payment proof uploaded','Payment '||coalesce(v_reference,left(p_payment_id::text,8))||' is ready for verification.','payment',p_payment_id,'payments.html?focus='||p_payment_id,'customer-proof:'||p_payment_id||':'||extract(epoch from v_uploaded)::bigint,
    jsonb_build_object('booking_id',v_booking,'file_name',btrim(p_file_name),'size_bytes',p_size_bytes),v_user);
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_user,'payment.customer_proof_uploaded','payment',p_payment_id,jsonb_build_object('booking_id',v_booking,'file_name',btrim(p_file_name),'mime_type',p_mime_type,'size_bytes',p_size_bytes));
  return true;
end $$;

revoke execute on function public.attach_my_payment_proof(uuid,text,text,text,bigint) from public,anon;
grant execute on function public.attach_my_payment_proof(uuid,text,text,text,bigint) to authenticated,service_role;
