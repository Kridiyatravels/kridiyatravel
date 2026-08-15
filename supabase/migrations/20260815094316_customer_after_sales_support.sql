create table public.customer_support_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  customer_user_id uuid not null references auth.users(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  enquiry_id uuid references public.enquiries(id) on delete set null,
  category text not null check (category in ('amendment','cancellation','complaint','privacy','emergency','other')),
  urgency text not null default 'normal' check (urgency in ('normal','urgent','emergency')),
  subject text not null check (char_length(btrim(subject)) between 3 and 180),
  description text not null check (char_length(btrim(description)) between 10 and 4000),
  status text not null default 'submitted' check (status in ('submitted','acknowledged','in_progress','waiting_customer','resolved','closed','cancelled')),
  assigned_to uuid references auth.users(id) on delete set null,
  resolution text check (resolution is null or char_length(resolution) <= 4000),
  task_id uuid references public.tasks_reminders(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (booking_id is null or enquiry_id is null)
);

create index customer_support_requests_customer_idx on public.customer_support_requests(customer_user_id, created_at desc);
create index customer_support_requests_work_idx on public.customer_support_requests(status, urgency, created_at);
create index customer_support_requests_booking_idx on public.customer_support_requests(booking_id) where booking_id is not null;
create index customer_support_requests_enquiry_idx on public.customer_support_requests(enquiry_id) where enquiry_id is not null;

create trigger customer_support_requests_set_updated_at before update on public.customer_support_requests
for each row execute function public.set_updated_at();

alter table public.customer_support_requests enable row level security;
create policy customer_support_requests_staff_select on public.customer_support_requests for select to authenticated using (public.is_staff());
create policy customer_support_requests_staff_update on public.customer_support_requests for update to authenticated using (public.is_staff()) with check (public.is_staff());

revoke all on public.customer_support_requests from public, anon, authenticated;
grant select, update on public.customer_support_requests to authenticated;
grant all on public.customer_support_requests to service_role;

create or replace function public.create_my_support_request(
  p_category text,
  p_subject text,
  p_description text,
  p_urgency text default 'normal',
  p_booking_id uuid default null,
  p_enquiry_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_task uuid;
  v_customer uuid;
  v_category text := lower(btrim(coalesce(p_category,'')));
  v_urgency text := lower(btrim(coalesce(p_urgency,'normal')));
  v_priority text;
  v_due timestamptz;
  v_reference text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if v_category not in ('amendment','cancellation','complaint','privacy','emergency','other') then raise exception 'Invalid support category'; end if;
  if v_urgency not in ('normal','urgent','emergency') then raise exception 'Invalid urgency'; end if;
  if char_length(btrim(coalesce(p_subject,''))) not between 3 and 180 then raise exception 'Subject must be 3 to 180 characters'; end if;
  if char_length(btrim(coalesce(p_description,''))) not between 10 and 4000 then raise exception 'Description must be 10 to 4000 characters'; end if;
  if p_booking_id is not null and p_enquiry_id is not null then raise exception 'Choose either a booking or an enquiry'; end if;

  select id into v_customer from public.customers where auth_user_id = v_user and active = true and archived_at is null order by created_at limit 1;
  if p_booking_id is not null then
    select booking_reference into v_reference from public.bookings where id = p_booking_id and user_id = v_user;
    if not found then raise exception 'Booking not found for this account'; end if;
  elsif p_enquiry_id is not null then
    select reference into v_reference from public.enquiries where id = p_enquiry_id and user_id = v_user;
    if not found then raise exception 'Enquiry not found for this account'; end if;
  else
    v_reference := 'Account request';
  end if;

  if exists (
    select 1 from public.customer_support_requests r
    where r.customer_user_id = v_user and r.category = v_category
      and r.booking_id is not distinct from p_booking_id and r.enquiry_id is not distinct from p_enquiry_id
      and r.subject = btrim(p_subject) and r.status not in ('resolved','closed','cancelled')
      and r.created_at > now() - interval '10 minutes'
  ) then raise exception 'This request was already submitted recently'; end if;

  if v_category = 'emergency' then v_urgency := 'emergency'; end if;
  v_priority := case when v_urgency = 'emergency' then 'urgent' when v_urgency = 'urgent' then 'high' else 'normal' end;
  v_due := now() + case when v_urgency = 'emergency' then interval '15 minutes' when v_urgency = 'urgent' then interval '2 hours' else interval '1 day' end;

  insert into public.customer_support_requests(customer_id,customer_user_id,booking_id,enquiry_id,category,urgency,subject,description)
  values(v_customer,v_user,p_booking_id,p_enquiry_id,v_category,v_urgency,btrim(p_subject),btrim(p_description)) returning id into v_id;

  insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,notes,created_by,automation_key)
  values('Customer ' || initcap(v_category) || ': ' || left(btrim(p_subject),160),'follow_up','customer_support_request',v_id,v_due,v_priority,
    'Customer-submitted request linked to ' || v_reference || '. Open the support request record before contacting the customer.',v_user,'customer-support:' || v_id)
  returning id into v_task;
  update public.customer_support_requests set task_id = v_task where id = v_id;

  insert into public.staff_notifications(audience,category,priority,title,body,entity_type,entity_id,action_url,dedupe_key,metadata,created_by)
  values('company','follow_up',v_priority,'New customer ' || v_category || ' request',left(btrim(p_subject) || ' - ' || v_reference,1000),
    'customer_support_request',v_id,'dashboard.html','customer-support:' || v_id,
    jsonb_build_object('category',v_category,'urgency',v_urgency,'booking_id',p_booking_id,'enquiry_id',p_enquiry_id),v_user);

  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_user,'customer_support_request_created','customer_support_request',v_id,jsonb_build_object('category',v_category,'urgency',v_urgency,'booking_id',p_booking_id,'enquiry_id',p_enquiry_id));
  return v_id;
end $$;

create or replace function public.list_my_support_requests()
returns table(id uuid, booking_id uuid, enquiry_id uuid, category text, urgency text, subject text, description text, status text, resolution text, created_at timestamptz, updated_at timestamptz, resolved_at timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  select r.id,r.booking_id,r.enquiry_id,r.category,r.urgency,r.subject,r.description,r.status,r.resolution,r.created_at,r.updated_at,r.resolved_at
  from public.customer_support_requests r where r.customer_user_id = auth.uid() order by r.created_at desc limit 100
$$;

create or replace function public.cancel_my_support_request(p_request_id uuid, p_expected_updated_at timestamptz)
returns boolean language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user uuid := auth.uid(); v_task uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  update public.customer_support_requests set status='cancelled'
  where id=p_request_id and customer_user_id=v_user and status in ('submitted','acknowledged')
    and updated_at=p_expected_updated_at returning task_id into v_task;
  if not found then raise exception 'Request changed, cannot be cancelled, or was not found'; end if;
  update public.tasks_reminders set status='cancelled' where id=v_task and status in ('open','snoozed');
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_user,'customer_support_request_cancelled','customer_support_request',p_request_id,'{}'::jsonb);
  return true;
end $$;

revoke execute on function public.create_my_support_request(text,text,text,text,uuid,uuid) from public, anon;
revoke execute on function public.list_my_support_requests() from public, anon;
revoke execute on function public.cancel_my_support_request(uuid,timestamptz) from public, anon;
grant execute on function public.create_my_support_request(text,text,text,text,uuid,uuid) to authenticated, service_role;
grant execute on function public.list_my_support_requests() to authenticated, service_role;
grant execute on function public.cancel_my_support_request(uuid,timestamptz) to authenticated, service_role;

comment on table public.customer_support_requests is 'Customer-initiated after-sales, complaint, privacy, cancellation, and emergency requests routed into staff operations.';
