update storage.buckets set public=false,file_size_limit=10485760,
 allowed_mime_types=array['application/pdf','image/jpeg','image/png','image/webp']
where id='enquiry-uploads';

create table public.enquiry_attachments (
 id uuid primary key default gen_random_uuid(), enquiry_id uuid not null references public.enquiries(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, storage_path text not null unique,
 file_name text not null check(char_length(file_name) between 1 and 180), mime_type text not null check(mime_type in ('application/pdf','image/jpeg','image/png','image/webp')),
 size_bytes bigint not null check(size_bytes between 1 and 10485760), status text not null default 'uploaded' check(status in ('uploaded','reviewed','archived')),
 created_at timestamptz not null default now()
);
create index enquiry_attachments_enquiry_idx on public.enquiry_attachments(enquiry_id,created_at);
alter table public.enquiry_attachments enable row level security;
create policy enquiry_attachments_staff_select on public.enquiry_attachments for select to authenticated using(public.is_staff());
revoke all on public.enquiry_attachments from public,anon,authenticated;
grant select on public.enquiry_attachments to authenticated;
grant all on public.enquiry_attachments to service_role;

create or replace function public.can_delete_unattached_enquiry_upload(p_path text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and p_path like auth.uid()::text||'/%'
   and not exists(select 1 from public.enquiry_attachments where storage_path=p_path)
$$;
drop policy if exists enquiry_uploads_delete_unattached_own on storage.objects;
create policy enquiry_uploads_delete_unattached_own on storage.objects for delete to authenticated
using(bucket_id='enquiry-uploads' and public.can_delete_unattached_enquiry_upload(name));

create or replace function public.attach_my_enquiry_file(p_enquiry_id uuid,p_storage_path text,p_file_name text,p_mime_type text,p_size_bytes bigint)
returns uuid language plpgsql security definer set search_path=public,storage,pg_temp as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_reference text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if p_mime_type not in ('application/pdf','image/jpeg','image/png','image/webp') then raise exception 'Only PDF, JPG, PNG or WebP files are allowed'; end if;
 if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then raise exception 'Attachment must be 10 MB or smaller'; end if;
 if char_length(btrim(coalesce(p_file_name,''))) not between 1 and 180 then raise exception 'Invalid file name'; end if;
 if p_storage_path !~ ('^'||v_user::text||'/'||p_enquiry_id::text||'/[0-9]+-[A-Za-z0-9._-]+$') then raise exception 'Invalid attachment path'; end if;
 select reference into v_reference from public.enquiries where id=p_enquiry_id and user_id=v_user;
 if not found then raise exception 'Enquiry not found for this account'; end if;
 if not exists(select 1 from storage.objects where bucket_id='enquiry-uploads' and name=p_storage_path and owner_id=v_user::text) then raise exception 'Uploaded attachment was not found'; end if;
 if (select count(*) from public.enquiry_attachments where enquiry_id=p_enquiry_id and status<>'archived')>=3 then raise exception 'Maximum three attachments per enquiry'; end if;
 insert into public.enquiry_attachments(enquiry_id,user_id,storage_path,file_name,mime_type,size_bytes)
 values(p_enquiry_id,v_user,p_storage_path,btrim(p_file_name),p_mime_type,p_size_bytes) returning id into v_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
 values(v_user,'enquiry.attachment_uploaded','enquiry',p_enquiry_id,jsonb_build_object('attachment_id',v_id,'reference',v_reference,'file_name',btrim(p_file_name),'mime_type',p_mime_type,'size_bytes',p_size_bytes));
 return v_id;
end $$;

revoke execute on function public.attach_my_enquiry_file(uuid,text,text,text,bigint) from public,anon;
grant execute on function public.attach_my_enquiry_file(uuid,text,text,text,bigint) to authenticated,service_role;
revoke execute on function public.can_delete_unattached_enquiry_upload(text) from public,anon;
grant execute on function public.can_delete_unattached_enquiry_upload(text) to authenticated,service_role;
