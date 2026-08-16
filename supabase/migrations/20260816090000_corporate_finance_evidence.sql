insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('corporate-finance-evidence','corporate-finance-evidence',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create table public.corporate_finance_evidence (
 id uuid primary key default gen_random_uuid(), corporate_account_id uuid not null references public.corporate_accounts(id) on delete cascade,
 booking_id uuid not null references public.bookings(id) on delete cascade, submitted_by uuid not null references auth.users(id) on delete restrict,
 evidence_type text not null check(evidence_type in ('payment_proof','lpo')), reference text,
 storage_path text not null unique, file_name text not null, mime_type text not null check(mime_type in ('application/pdf','image/jpeg','image/png')),
 size_bytes bigint not null check(size_bytes between 1 and 10485760), status text not null default 'pending' check(status in ('pending','verified','rejected')),
 reviewed_by uuid references auth.users(id) on delete set null, review_note text, reviewed_at timestamptz, task_id uuid references public.tasks_reminders(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index corporate_finance_evidence_company_idx on public.corporate_finance_evidence(corporate_account_id,status,created_at desc);
alter table public.corporate_finance_evidence enable row level security;
revoke all on public.corporate_finance_evidence from anon,authenticated; grant all on public.corporate_finance_evidence to service_role;

create or replace function public.can_upload_corporate_finance_evidence(p_booking_id text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select auth.uid() is not null and exists(select 1 from public.bookings b join public.corporate_portal_members m on m.corporate_account_id=b.corporate_account_id where b.id::text=p_booking_id and m.user_id=auth.uid() and m.status='active' and (m.can_view_finance or m.can_request))
$$;
revoke execute on function public.can_upload_corporate_finance_evidence(text) from public,anon; grant execute on function public.can_upload_corporate_finance_evidence(text) to authenticated;

drop policy if exists corporate_finance_evidence_insert_member on storage.objects;
create policy corporate_finance_evidence_insert_member on storage.objects for insert to authenticated with check(bucket_id='corporate-finance-evidence' and (storage.foldername(name))[1]=auth.uid()::text and public.can_upload_corporate_finance_evidence((storage.foldername(name))[2]));
drop policy if exists corporate_finance_evidence_delete_unattached on storage.objects;
create policy corporate_finance_evidence_delete_unattached on storage.objects for delete to authenticated using(bucket_id='corporate-finance-evidence' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.corporate_finance_evidence e where e.storage_path=name));
drop policy if exists corporate_finance_evidence_select_staff on storage.objects;
create policy corporate_finance_evidence_select_staff on storage.objects for select to authenticated using(bucket_id='corporate-finance-evidence' and (public.has_staff_permission('view_payments') or public.has_staff_permission('edit_payments') or public.has_staff_permission('view_corporates')));

create or replace function public.attach_my_corporate_finance_evidence(p_corporate_account_id uuid,p_booking_id uuid,p_evidence_type text,p_reference text,p_storage_path text,p_file_name text,p_mime_type text,p_size_bytes bigint)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_task uuid; v_type text:=lower(btrim(coalesce(p_evidence_type,'')));
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.bookings b join public.corporate_portal_members m on m.corporate_account_id=b.corporate_account_id where b.id=p_booking_id and b.corporate_account_id=p_corporate_account_id and m.user_id=v_user and m.status='active' and (m.can_view_finance or m.can_request)) then raise exception 'Booking finance access required'; end if;
 if v_type not in ('payment_proof','lpo') then raise exception 'Invalid evidence type'; end if;
 if p_mime_type not in ('application/pdf','image/jpeg','image/png') or p_size_bytes not between 1 and 10485760 then raise exception 'File must be PDF, JPG or PNG and no larger than 10 MB'; end if;
 if p_storage_path !~ ('^'||v_user::text||'/'||p_booking_id::text||'/[A-Za-z0-9._-]+$') then raise exception 'Invalid storage path'; end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='corporate-finance-evidence' and o.name=p_storage_path and o.owner_id=v_user::text) then raise exception 'Uploaded file not found'; end if;
 if exists(select 1 from public.corporate_finance_evidence e where e.booking_id=p_booking_id and e.evidence_type=v_type and e.status='pending') then raise exception 'This booking already has pending evidence of that type'; end if;
 insert into public.corporate_finance_evidence(corporate_account_id,booking_id,submitted_by,evidence_type,reference,storage_path,file_name,mime_type,size_bytes) values(p_corporate_account_id,p_booking_id,v_user,v_type,nullif(btrim(coalesce(p_reference,'')),''),p_storage_path,btrim(p_file_name),p_mime_type,p_size_bytes) returning id into v_id;
 insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,notes,created_by,automation_key) values('Verify corporate '||replace(v_type,'_',' '),'follow_up','corporate_finance_evidence',v_id,now()+interval '2 hours','high','Verify uploaded company finance evidence before changing payment or booking status.',v_user,'corporate-finance:'||v_id) returning id into v_task;
 update public.corporate_finance_evidence set task_id=v_task where id=v_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'corporate_finance_evidence_submitted','corporate_finance_evidence',v_id,jsonb_build_object('corporate_account_id',p_corporate_account_id,'booking_id',p_booking_id,'evidence_type',v_type)); return v_id;
end $$;

create or replace function public.list_my_corporate_finance_evidence(p_corporate_account_id uuid)
returns table(id uuid,booking_id uuid,evidence_type text,reference text,file_name text,status text,review_note text,created_at timestamptz,reviewed_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$ select e.id,e.booking_id,e.evidence_type,e.reference,e.file_name,e.status,e.review_note,e.created_at,e.reviewed_at from public.corporate_finance_evidence e where e.corporate_account_id=p_corporate_account_id and exists(select 1 from public.corporate_portal_members m where m.user_id=auth.uid() and m.corporate_account_id=e.corporate_account_id and m.status='active' and (m.can_view_finance or m.can_request)) order by e.created_at desc $$;

create or replace function public.list_corporate_finance_evidence(p_status text default 'pending')
returns table(id uuid,company_name text,booking_id uuid,booking_reference text,evidence_type text,reference text,storage_path text,file_name text,status text,review_note text,created_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$ select e.id,a.company_name,e.booking_id,b.booking_reference,e.evidence_type,e.reference,e.storage_path,e.file_name,e.status,e.review_note,e.created_at from public.corporate_finance_evidence e join public.corporate_accounts a on a.id=e.corporate_account_id join public.bookings b on b.id=e.booking_id where public.is_staff() and (p_status is null or e.status=p_status) order by e.created_at desc limit 300 $$;

create or replace function public.review_corporate_finance_evidence(p_evidence_id uuid,p_status text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_status text:=lower(btrim(coalesce(p_status,'')));
begin if v_user is null or not (public.has_staff_permission('edit_payments') or public.has_staff_permission('edit_corporates')) then raise exception 'Finance edit permission required'; end if; if v_status not in ('verified','rejected') then raise exception 'Invalid review status'; end if; if char_length(btrim(coalesce(p_note,'')))<3 then raise exception 'Review note is required'; end if;
 update public.corporate_finance_evidence set status=v_status,reviewed_by=v_user,review_note=btrim(p_note),reviewed_at=now(),updated_at=now() where id=p_evidence_id and status='pending'; if not found then raise exception 'Pending evidence not found'; end if;
 update public.tasks_reminders set status='done',completed_at=coalesce(completed_at,now()) where entity_type='corporate_finance_evidence' and entity_id=p_evidence_id and status<>'done';
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'corporate_finance_evidence_'||v_status,'corporate_finance_evidence',p_evidence_id,jsonb_build_object('note',btrim(p_note))); end $$;

revoke execute on function public.attach_my_corporate_finance_evidence(uuid,uuid,text,text,text,text,text,bigint) from public,anon;
revoke execute on function public.list_my_corporate_finance_evidence(uuid) from public,anon;
revoke execute on function public.list_corporate_finance_evidence(text) from public,anon;
revoke execute on function public.review_corporate_finance_evidence(uuid,text,text) from public,anon;
grant execute on function public.attach_my_corporate_finance_evidence(uuid,uuid,text,text,text,text,text,bigint) to authenticated;
grant execute on function public.list_my_corporate_finance_evidence(uuid) to authenticated;
grant execute on function public.list_corporate_finance_evidence(text) to authenticated;
grant execute on function public.review_corporate_finance_evidence(uuid,text,text) to authenticated;
