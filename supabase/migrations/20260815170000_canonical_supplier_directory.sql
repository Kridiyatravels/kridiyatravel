create table if not exists public.suppliers(
 id uuid primary key default gen_random_uuid(), name text not null, normalized_name text not null unique,
 status text not null default 'active' check(status in('active','on_hold','inactive')),
 email text, phone text, payment_terms text, notes text, created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;
revoke all on public.suppliers from anon,authenticated; grant select on public.suppliers to service_role;
alter table public.bookings add column if not exists supplier_id uuid references public.suppliers(id) on delete set null;
alter table public.supplier_payments add column if not exists supplier_id uuid references public.suppliers(id) on delete set null;

insert into public.suppliers(name,normalized_name)
select min(trim(n)),lower(regexp_replace(trim(n),'\s+',' ','g')) from(
 select supplier_name n from public.bookings where nullif(trim(supplier_name),'') is not null
 union all select supplier_name from public.supplier_payments where nullif(trim(supplier_name),'') is not null
)x group by lower(regexp_replace(trim(n),'\s+',' ','g')) on conflict(normalized_name) do nothing;
update public.bookings b set supplier_id=s.id from public.suppliers s where b.supplier_id is null and lower(regexp_replace(trim(b.supplier_name),'\s+',' ','g'))=s.normalized_name;
update public.supplier_payments p set supplier_id=s.id from public.suppliers s where p.supplier_id is null and lower(regexp_replace(trim(p.supplier_name),'\s+',' ','g'))=s.normalized_name;

create or replace function public.link_canonical_supplier() returns trigger language plpgsql security definer set search_path='public' as $function$
declare v_norm text;
begin
 if nullif(trim(new.supplier_name),'') is null then new.supplier_id:=null; return new; end if;
 v_norm:=lower(regexp_replace(trim(new.supplier_name),'\s+',' ','g'));
 insert into public.suppliers(name,normalized_name,created_by) values(trim(new.supplier_name),v_norm,auth.uid()) on conflict(normalized_name) do update set name=excluded.name,updated_at=now() returning id into new.supplier_id;
 return new;
end;$function$;
drop trigger if exists bookings_link_canonical_supplier on public.bookings;
create trigger bookings_link_canonical_supplier before insert or update of supplier_name on public.bookings for each row execute function public.link_canonical_supplier();
drop trigger if exists supplier_payments_link_canonical_supplier on public.supplier_payments;
create trigger supplier_payments_link_canonical_supplier before insert or update of supplier_name on public.supplier_payments for each row execute function public.link_canonical_supplier();
revoke execute on function public.link_canonical_supplier() from public,anon,authenticated;

create or replace function public.list_supplier_performance()
returns jsonb language plpgsql security definer stable set search_path='public' as $function$
begin
 if auth.uid() is null or not public.has_staff_permission('view_supplier_cost') then raise exception 'Supplier cost permission required'; end if;
 return coalesce((with bm as(select supplier_id,count(*) booking_count,coalesce(sum(supplier_cost),0) recorded_booking_cost from public.bookings where archived_at is null group by supplier_id),
 pm as(select supplier_id,count(*) payable_count,coalesce(sum(amount_payable),0) payable_total,coalesce(sum(amount_paid),0) paid_total,coalesce(sum(amount_payable-amount_paid),0) open_balance,count(*) filter(where status='disputed') dispute_count,count(*) filter(where status='paid') paid_record_count from public.supplier_payments group by supplier_id)
 select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',s.status,'payment_terms',s.payment_terms,'booking_count',coalesce(bm.booking_count,0),'recorded_booking_cost',coalesce(bm.recorded_booking_cost,0),'payable_count',coalesce(pm.payable_count,0),'payable_total',coalesce(pm.payable_total,0),'paid_total',coalesce(pm.paid_total,0),'open_balance',coalesce(pm.open_balance,0),'dispute_count',coalesce(pm.dispute_count,0),'paid_record_count',coalesce(pm.paid_record_count,0)) order by coalesce(pm.open_balance,0) desc,s.name)
 from public.suppliers s left join bm on bm.supplier_id=s.id left join pm on pm.supplier_id=s.id),'[]'::jsonb);
end;$function$;
revoke execute on function public.list_supplier_performance() from public,anon;
grant execute on function public.list_supplier_performance() to authenticated,service_role;
