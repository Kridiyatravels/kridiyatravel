create table public.customer_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email_enabled boolean not null default true,
  whatsapp_enabled boolean not null default true,
  booking_updates boolean not null default true,
  payment_updates boolean not null default true,
  document_updates boolean not null default true,
  support_updates boolean not null default true,
  marketing_email boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.customer_notification_preferences enable row level security;
revoke all on public.customer_notification_preferences from public,anon,authenticated;
grant all on public.customer_notification_preferences to service_role;

create table public.customer_communication_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('portal','email','whatsapp','sms')),
  category text not null check (category in ('booking','quote','payment','document','support','security','marketing','system')),
  subject text not null check (char_length(btrim(subject)) between 2 and 180),
  delivery_status text not null check (delivery_status in ('available','queued','sent','delivered','failed','read')),
  entity_type text,
  entity_id uuid,
  dedupe_key text,
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index customer_communication_history_dedupe_idx on public.customer_communication_history(dedupe_key) where dedupe_key is not null;
create index customer_communication_history_user_idx on public.customer_communication_history(user_id,created_at desc);
alter table public.customer_communication_history enable row level security;
create policy customer_communication_history_staff_select on public.customer_communication_history for select to authenticated using (public.is_staff());
revoke all on public.customer_communication_history from public,anon,authenticated;
grant select on public.customer_communication_history to authenticated;
grant all on public.customer_communication_history to service_role;

create or replace function public.get_my_notification_preferences()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_row public.customer_notification_preferences%rowtype;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 insert into public.customer_notification_preferences(user_id) values(v_user) on conflict(user_id) do nothing;
 select * into v_row from public.customer_notification_preferences where user_id=v_user;
 return to_jsonb(v_row)-'user_id';
end $$;

create or replace function public.save_my_notification_preferences(p_email_enabled boolean,p_whatsapp_enabled boolean,p_booking_updates boolean,p_payment_updates boolean,p_document_updates boolean,p_support_updates boolean,p_marketing_email boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_result jsonb;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 insert into public.customer_notification_preferences(user_id,email_enabled,whatsapp_enabled,booking_updates,payment_updates,document_updates,support_updates,marketing_email)
 values(v_user,p_email_enabled,p_whatsapp_enabled,p_booking_updates,p_payment_updates,p_document_updates,p_support_updates,p_marketing_email)
 on conflict(user_id) do update set email_enabled=excluded.email_enabled,whatsapp_enabled=excluded.whatsapp_enabled,booking_updates=excluded.booking_updates,payment_updates=excluded.payment_updates,document_updates=excluded.document_updates,support_updates=excluded.support_updates,marketing_email=excluded.marketing_email,updated_at=now();
 update public.profiles set newsletter_opt_in=p_marketing_email,updated_at=now() where id=v_user;
 select to_jsonb(p)-'user_id' into v_result from public.customer_notification_preferences p where p.user_id=v_user;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'customer.notification_preferences_updated','profile',v_user,jsonb_build_object('email_enabled',p_email_enabled,'whatsapp_enabled',p_whatsapp_enabled,'marketing_email',p_marketing_email));
 return v_result;
end $$;

create or replace function public.list_my_communication_history(p_limit integer default 50)
returns table(id uuid,channel text,category text,subject text,delivery_status text,entity_type text,entity_id uuid,available_at timestamptz,sent_at timestamptz,delivered_at timestamptz,failed_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
 select h.id,h.channel,h.category,h.subject,h.delivery_status,h.entity_type,h.entity_id,h.available_at,h.sent_at,h.delivered_at,h.failed_at
 from public.customer_communication_history h where h.user_id=auth.uid() order by h.created_at desc limit greatest(1,least(coalesce(p_limit,50),100))
$$;

create or replace function public.record_customer_portal_milestone()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_category text; v_subject text; v_type text; v_id uuid; v_key text;
begin
 if tg_table_name='bookings' then v_user:=new.user_id; v_category:='booking'; v_subject:='Booking status: '||initcap(replace(new.status::text,'_',' ')); v_type:='booking'; v_id:=new.id; v_key:='booking:'||new.id||':'||new.status::text||':'||extract(epoch from new.updated_at)::bigint;
 elsif tg_table_name='payments' then select b.user_id into v_user from public.bookings b where b.id=new.booking_id; v_category:='payment'; v_subject:='Payment status: '||initcap(replace(new.status,'_',' ')); v_type:='payment'; v_id:=new.id; v_key:='payment:'||new.id||':'||new.status||':'||extract(epoch from new.updated_at)::bigint;
 elsif tg_table_name='booking_documents' then select b.user_id into v_user from public.bookings b where b.id=new.booking_id; v_category:='document'; v_subject:='Document available: '||coalesce(new.file_name,initcap(replace(new.document_type,'_',' '))); v_type:='document'; v_id:=new.id; v_key:='document:'||new.id||':released';
 elsif tg_table_name='customer_support_requests' then v_user:=new.customer_user_id; v_category:='support'; v_subject:='Support request: '||initcap(replace(new.status,'_',' ')); v_type:='customer_support_request'; v_id:=new.id; v_key:='support:'||new.id||':'||new.status||':'||extract(epoch from new.updated_at)::bigint;
 elsif tg_table_name='quotes' then select e.user_id into v_user from public.enquiries e where e.id=new.enquiry_id; v_category:='quote'; v_subject:='Quote available: '||new.title; v_type:='quote'; v_id:=new.id; v_key:='quote:'||new.id||':v'||new.quote_version;
 end if;
 if v_user is not null then insert into public.customer_communication_history(user_id,channel,category,subject,delivery_status,entity_type,entity_id,dedupe_key) values(v_user,'portal',v_category,left(v_subject,180),'available',v_type,v_id,v_key) on conflict(dedupe_key) where dedupe_key is not null do nothing; end if;
 return new;
end $$;

create trigger customer_comm_booking after update of status on public.bookings for each row when(old.status is distinct from new.status) execute function public.record_customer_portal_milestone();
create trigger customer_comm_payment after update of status on public.payments for each row when(old.status is distinct from new.status) execute function public.record_customer_portal_milestone();
create trigger customer_comm_document after insert or update of visible_to_customer on public.booking_documents for each row when(new.visible_to_customer=true) execute function public.record_customer_portal_milestone();
create trigger customer_comm_support after update of status on public.customer_support_requests for each row when(old.status is distinct from new.status) execute function public.record_customer_portal_milestone();
create trigger customer_comm_quote after insert or update of status on public.quotes for each row when(new.status='sent') execute function public.record_customer_portal_milestone();

revoke execute on function public.get_my_notification_preferences() from public,anon;
revoke execute on function public.save_my_notification_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean) from public,anon;
revoke execute on function public.list_my_communication_history(integer) from public,anon;
revoke execute on function public.record_customer_portal_milestone() from public,anon,authenticated;
grant execute on function public.get_my_notification_preferences(),public.save_my_notification_preferences(boolean,boolean,boolean,boolean,boolean,boolean,boolean),public.list_my_communication_history(integer) to authenticated,service_role;
grant execute on function public.record_customer_portal_milestone() to service_role;
