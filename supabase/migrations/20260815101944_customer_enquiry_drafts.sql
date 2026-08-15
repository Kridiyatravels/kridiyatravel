create table public.customer_enquiry_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  form_key text not null check (char_length(form_key) between 2 and 80),
  service_type text not null check (service_type in ('flight','hotel','holiday','visa','umrah','cruise','other')),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object' and pg_column_size(payload)<=32768),
  expires_at timestamptz not null default now()+interval '30 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,form_key)
);
create index customer_enquiry_drafts_expiry_idx on public.customer_enquiry_drafts(expires_at);
alter table public.customer_enquiry_drafts enable row level security;
revoke all on public.customer_enquiry_drafts from public,anon,authenticated;
grant all on public.customer_enquiry_drafts to service_role;

create or replace function public.save_my_enquiry_draft(p_form_key text,p_service_type text,p_payload jsonb)
returns timestamptz language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_updated timestamptz;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if char_length(btrim(coalesce(p_form_key,''))) not between 2 and 80 then raise exception 'Invalid form key'; end if;
 if p_service_type not in ('flight','hotel','holiday','visa','umrah','cruise','other') then raise exception 'Invalid service type'; end if;
 if jsonb_typeof(coalesce(p_payload,'null'::jsonb))<>'object' or pg_column_size(p_payload)>32768 then raise exception 'Invalid or oversized draft'; end if;
 if p_payload ?| array['passport','passport_number','card_number','cvv','password','otp'] then raise exception 'Sensitive fields cannot be saved in a draft'; end if;
 insert into public.customer_enquiry_drafts(user_id,form_key,service_type,payload,expires_at)
 values(v_user,btrim(p_form_key),p_service_type,p_payload,now()+interval '30 days')
 on conflict(user_id,form_key) do update set service_type=excluded.service_type,payload=excluded.payload,expires_at=excluded.expires_at,updated_at=now()
 returning updated_at into v_updated; return v_updated;
end $$;

create or replace function public.get_my_enquiry_draft(p_form_key text)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('form_key',d.form_key,'service_type',d.service_type,'payload',d.payload,'updated_at',d.updated_at,'expires_at',d.expires_at)
 from public.customer_enquiry_drafts d where d.user_id=auth.uid() and d.form_key=p_form_key and d.expires_at>now()
$$;

create or replace function public.delete_my_enquiry_draft(p_form_key text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin delete from public.customer_enquiry_drafts where user_id=auth.uid() and form_key=p_form_key; return found; end $$;

revoke execute on function public.save_my_enquiry_draft(text,text,jsonb),public.get_my_enquiry_draft(text),public.delete_my_enquiry_draft(text) from public,anon;
grant execute on function public.save_my_enquiry_draft(text,text,jsonb),public.get_my_enquiry_draft(text),public.delete_my_enquiry_draft(text) to authenticated,service_role;
