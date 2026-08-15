create table if not exists public.corporate_desk_cases (
  id uuid primary key default gen_random_uuid(),
  corporate_account_id uuid not null references public.corporate_accounts(id) on delete cascade,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  booking_id uuid references public.bookings(id) on delete set null,
  category text not null check (category in ('amendment','cancellation','document','finance','complaint','emergency','other')),
  urgency text not null default 'normal' check (urgency in ('normal','urgent','emergency')),
  subject text not null check (char_length(btrim(subject)) between 3 and 180),
  description text not null check (char_length(btrim(description)) between 10 and 4000),
  status text not null default 'submitted' check (status in ('submitted','acknowledged','in_progress','waiting_company','resolved','closed')),
  assigned_to uuid references auth.users(id) on delete set null,
  staff_response text check (staff_response is null or char_length(btrim(staff_response)) between 3 and 4000),
  task_id uuid references public.tasks_reminders(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists corporate_desk_cases_company_created_idx on public.corporate_desk_cases(corporate_account_id, created_at desc);
create index if not exists corporate_desk_cases_status_idx on public.corporate_desk_cases(status, urgency, created_at);
alter table public.corporate_desk_cases enable row level security;
revoke all on public.corporate_desk_cases from anon, authenticated;
grant all on public.corporate_desk_cases to service_role;

create or replace function public.create_my_corporate_desk_case(p_corporate_account_id uuid,p_category text,p_urgency text,p_subject text,p_description text,p_booking_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_task uuid; v_priority text; v_due timestamptz; v_category text:=lower(btrim(coalesce(p_category,''))); v_urgency text:=lower(btrim(coalesce(p_urgency,'normal')));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.corporate_portal_members m join public.corporate_accounts a on a.id=m.corporate_account_id where m.user_id=v_user and m.corporate_account_id=p_corporate_account_id and m.status='active' and m.can_request and a.archived_at is null) then raise exception 'Active company request access required'; end if;
  if v_category not in ('amendment','cancellation','document','finance','complaint','emergency','other') then raise exception 'Invalid category'; end if;
  if v_urgency not in ('normal','urgent','emergency') then raise exception 'Invalid urgency'; end if;
  if v_category='emergency' then v_urgency:='emergency'; end if;
  if char_length(btrim(coalesce(p_subject,''))) not between 3 and 180 then raise exception 'Subject must be 3 to 180 characters'; end if;
  if char_length(btrim(coalesce(p_description,''))) not between 10 and 4000 then raise exception 'Description must be 10 to 4000 characters'; end if;
  if p_booking_id is not null and not exists(select 1 from public.bookings b where b.id=p_booking_id and b.corporate_account_id=p_corporate_account_id) then raise exception 'Booking is not part of this company'; end if;
  if exists(select 1 from public.corporate_desk_cases c where c.corporate_account_id=p_corporate_account_id and c.submitted_by=v_user and c.subject=btrim(p_subject) and c.status not in ('resolved','closed') and c.created_at>now()-interval '10 minutes') then raise exception 'This case was already submitted recently'; end if;
  insert into public.corporate_desk_cases(corporate_account_id,submitted_by,booking_id,category,urgency,subject,description) values(p_corporate_account_id,v_user,p_booking_id,v_category,v_urgency,btrim(p_subject),btrim(p_description)) returning id into v_id;
  v_priority:=case when v_urgency='emergency' then 'urgent' when v_urgency='urgent' then 'high' else 'normal' end;
  v_due:=now()+case when v_urgency='emergency' then interval '15 minutes' when v_urgency='urgent' then interval '2 hours' else interval '1 day' end;
  insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,notes,created_by,automation_key) values('Corporate desk: '||left(btrim(p_subject),160),'follow_up','corporate_desk_case',v_id,v_due,v_priority,'Company portal case. Open Corporate Desk queue before responding.',v_user,'corporate-desk:'||v_id) returning id into v_task;
  update public.corporate_desk_cases set task_id=v_task where id=v_id;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'corporate_desk_case_created','corporate_desk_case',v_id,jsonb_build_object('corporate_account_id',p_corporate_account_id,'category',v_category,'urgency',v_urgency,'booking_id',p_booking_id));
  return v_id;
end $$;

create or replace function public.list_my_corporate_desk_cases(p_corporate_account_id uuid,p_limit integer default 100)
returns setof public.corporate_desk_cases language sql stable security definer set search_path=public,pg_temp as $$
 select c.* from public.corporate_desk_cases c where c.corporate_account_id=p_corporate_account_id and exists(select 1 from public.corporate_portal_members m where m.user_id=auth.uid() and m.corporate_account_id=c.corporate_account_id and m.status='active') order by c.created_at desc limit least(greatest(coalesce(p_limit,100),1),200)
$$;

create or replace function public.list_corporate_desk_cases(p_status text default null,p_limit integer default 200)
returns table(id uuid,corporate_account_id uuid,company_name text,submitted_by uuid,booking_id uuid,category text,urgency text,subject text,description text,status text,assigned_to uuid,staff_response text,task_id uuid,resolved_at timestamptz,created_at timestamptz,updated_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
 select c.id,c.corporate_account_id,a.company_name,c.submitted_by,c.booking_id,c.category,c.urgency,c.subject,c.description,c.status,c.assigned_to,c.staff_response,c.task_id,c.resolved_at,c.created_at,c.updated_at from public.corporate_desk_cases c join public.corporate_accounts a on a.id=c.corporate_account_id where public.is_staff() and (p_status is null or c.status=p_status) order by case c.urgency when 'emergency' then 0 when 'urgent' then 1 else 2 end,c.created_at desc limit least(greatest(coalesce(p_limit,200),1),500)
$$;

create or replace function public.update_corporate_desk_case(p_case_id uuid,p_status text,p_staff_response text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_old text; v_status text:=lower(btrim(coalesce(p_status,'')));
begin
 if v_user is null or not public.is_staff() then raise exception 'Staff access required'; end if;
 if v_status not in ('acknowledged','in_progress','waiting_company','resolved','closed') then raise exception 'Invalid status'; end if;
 if v_status in ('waiting_company','resolved','closed') and char_length(btrim(coalesce(p_staff_response,'')))<3 then raise exception 'A staff response is required'; end if;
 select status into v_old from public.corporate_desk_cases where id=p_case_id for update; if not found then raise exception 'Case not found'; end if;
 update public.corporate_desk_cases set status=v_status,assigned_to=coalesce(assigned_to,v_user),staff_response=case when p_staff_response is null then staff_response else btrim(p_staff_response) end,resolved_at=case when v_status in ('resolved','closed') then now() else null end,updated_at=now() where id=p_case_id;
 if v_status in ('resolved','closed') then update public.tasks_reminders set status='done',completed_at=coalesce(completed_at,now()) where entity_type='corporate_desk_case' and entity_id=p_case_id and status<>'done'; end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'corporate_desk_case_updated','corporate_desk_case',p_case_id,jsonb_build_object('from_status',v_old,'to_status',v_status));
end $$;

revoke execute on function public.create_my_corporate_desk_case(uuid,text,text,text,text,uuid) from public,anon;
revoke execute on function public.list_my_corporate_desk_cases(uuid,integer) from public,anon;
revoke execute on function public.list_corporate_desk_cases(text,integer) from public,anon;
revoke execute on function public.update_corporate_desk_case(uuid,text,text) from public,anon;
grant execute on function public.create_my_corporate_desk_case(uuid,text,text,text,text,uuid) to authenticated;
grant execute on function public.list_my_corporate_desk_cases(uuid,integer) to authenticated;
grant execute on function public.list_corporate_desk_cases(text,integer) to authenticated;
grant execute on function public.update_corporate_desk_case(uuid,text,text) to authenticated;
