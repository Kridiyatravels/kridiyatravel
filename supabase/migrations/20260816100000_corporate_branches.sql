create table public.corporate_branches (
 id uuid primary key default gen_random_uuid(), corporate_account_id uuid not null references public.corporate_accounts(id) on delete cascade,
 branch_name text not null check(char_length(btrim(branch_name)) between 2 and 160), branch_code text,
 city text, country text not null default 'United Arab Emirates', address text, phone text, billing_email text,
 status text not null default 'active' check(status in ('active','on_hold','inactive')), notes text,
 created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), archived_at timestamptz,
 unique(corporate_account_id,branch_name)
);
create index corporate_branches_account_idx on public.corporate_branches(corporate_account_id,status);
alter table public.corporate_branches enable row level security; revoke all on public.corporate_branches from anon,authenticated; grant all on public.corporate_branches to service_role;

create or replace function public.list_corporate_branches(p_corporate_account_id uuid default null)
returns setof public.corporate_branches language sql stable security definer set search_path=public,pg_temp as $$
 select b.* from public.corporate_branches b where public.is_staff() and b.archived_at is null and (p_corporate_account_id is null or b.corporate_account_id=p_corporate_account_id) order by b.branch_name
$$;
create or replace function public.list_my_corporate_branches(p_corporate_account_id uuid)
returns table(id uuid,branch_name text,branch_code text,city text,country text,address text,phone text,billing_email text,status text)
language sql stable security definer set search_path=public,pg_temp as $$
 select b.id,b.branch_name,b.branch_code,b.city,b.country,b.address,b.phone,b.billing_email,b.status from public.corporate_branches b where b.corporate_account_id=p_corporate_account_id and b.archived_at is null and exists(select 1 from public.corporate_portal_members m where m.user_id=auth.uid() and m.corporate_account_id=b.corporate_account_id and m.status='active') order by b.branch_name
$$;
create or replace function public.save_corporate_branch(p_corporate_account_id uuid,p_branch_id uuid,p_branch_name text,p_branch_code text,p_city text,p_country text,p_address text,p_phone text,p_billing_email text,p_status text,p_notes text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid();v_id uuid;v_status text:=lower(btrim(coalesce(p_status,'active')));
begin if v_user is null or not public.has_staff_permission('edit_corporates') then raise exception 'Corporate edit permission required'; end if; if char_length(btrim(coalesce(p_branch_name,''))) not between 2 and 160 then raise exception 'Branch name is required'; end if; if v_status not in ('active','on_hold','inactive') then raise exception 'Invalid branch status'; end if;
 if p_branch_id is null then insert into public.corporate_branches(corporate_account_id,branch_name,branch_code,city,country,address,phone,billing_email,status,notes,created_by) values(p_corporate_account_id,btrim(p_branch_name),nullif(btrim(coalesce(p_branch_code,'')),''),nullif(btrim(coalesce(p_city,'')),''),coalesce(nullif(btrim(coalesce(p_country,'')),''),'United Arab Emirates'),nullif(btrim(coalesce(p_address,'')),''),nullif(btrim(coalesce(p_phone,'')),''),nullif(lower(btrim(coalesce(p_billing_email,''))),''),v_status,nullif(btrim(coalesce(p_notes,'')),''),v_user) returning id into v_id;
 else update public.corporate_branches set branch_name=btrim(p_branch_name),branch_code=nullif(btrim(coalesce(p_branch_code,'')),''),city=nullif(btrim(coalesce(p_city,'')),''),country=coalesce(nullif(btrim(coalesce(p_country,'')),''),'United Arab Emirates'),address=nullif(btrim(coalesce(p_address,'')),''),phone=nullif(btrim(coalesce(p_phone,'')),''),billing_email=nullif(lower(btrim(coalesce(p_billing_email,''))),''),status=v_status,notes=nullif(btrim(coalesce(p_notes,'')),''),updated_at=now() where id=p_branch_id and corporate_account_id=p_corporate_account_id and archived_at is null returning id into v_id; if not found then raise exception 'Branch not found'; end if; end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,case when p_branch_id is null then 'corporate_branch_created' else 'corporate_branch_updated' end,'corporate_branch',v_id,jsonb_build_object('corporate_account_id',p_corporate_account_id,'status',v_status)); return v_id; end $$;
revoke execute on function public.list_corporate_branches(uuid) from public,anon; revoke execute on function public.list_my_corporate_branches(uuid) from public,anon; revoke execute on function public.save_corporate_branch(uuid,uuid,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.list_corporate_branches(uuid) to authenticated; grant execute on function public.list_my_corporate_branches(uuid) to authenticated; grant execute on function public.save_corporate_branch(uuid,uuid,text,text,text,text,text,text,text,text,text) to authenticated;
