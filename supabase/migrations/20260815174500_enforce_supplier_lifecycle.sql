create or replace function public.enforce_supplier_active() returns trigger language plpgsql security definer set search_path='public' as $function$
declare v_status text;
begin
 if new.supplier_id is null then return new; end if;
 select status into v_status from public.suppliers where id=new.supplier_id;
 if v_status<>'active' then
  if tg_table_name='bookings' and (tg_op='INSERT' or new.supplier_id is distinct from old.supplier_id) then raise exception 'Supplier is not active for new booking assignment'; end if;
  if tg_table_name='supplier_payments' and (tg_op='INSERT' or new.amount_paid>coalesce(old.amount_paid,0)) then raise exception 'Supplier is not active for new payable or payment release'; end if;
 end if; return new;
end;$function$;
drop trigger if exists bookings_supplier_active_guard on public.bookings;
create trigger bookings_supplier_active_guard before insert or update of supplier_id on public.bookings for each row execute function public.enforce_supplier_active();
drop trigger if exists supplier_payments_supplier_active_guard on public.supplier_payments;
create trigger supplier_payments_supplier_active_guard before insert or update of supplier_id,amount_paid on public.supplier_payments for each row execute function public.enforce_supplier_active();
revoke execute on function public.enforce_supplier_active() from public,anon,authenticated;

create or replace function public.update_supplier_profile(p_supplier_id uuid,p_status text,p_email text,p_phone text,p_payment_terms text,p_notes text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare v public.suppliers%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if; perform public.require_recent_auth(1800);
 if not public.has_staff_permission('manage_settings') then raise exception 'Owner/settings permission required'; end if;
 if p_status not in('active','on_hold','inactive') then raise exception 'Invalid supplier status'; end if;
 select * into v from public.suppliers where id=p_supplier_id for update; if not found then raise exception 'Supplier not found'; end if;
 if p_status in('on_hold','inactive') and char_length(trim(coalesce(p_notes,'')))<10 then raise exception 'Hold/inactive reason must be at least 10 characters'; end if;
 update public.suppliers set status=p_status,email=nullif(trim(coalesce(p_email,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),payment_terms=nullif(trim(coalesce(p_payment_terms,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=p_supplier_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(auth.uid(),'supplier.profile_updated','supplier',p_supplier_id,jsonb_build_object('name',v.name,'previous_status',v.status,'status',p_status,'payment_terms',nullif(trim(coalesce(p_payment_terms,'')),''),'reason',nullif(trim(coalesce(p_notes,'')),'')));
 return jsonb_build_object('id',p_supplier_id,'status',p_status);
end;$function$;
revoke execute on function public.update_supplier_profile(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.update_supplier_profile(uuid,text,text,text,text,text) to authenticated,service_role;

create or replace function public.list_supplier_performance() returns jsonb language plpgsql security definer stable set search_path='public' as $function$
begin
 if auth.uid() is null or not public.has_staff_permission('view_supplier_cost') then raise exception 'Supplier cost permission required'; end if;
 return coalesce((with bm as(select supplier_id,count(*) booking_count,coalesce(sum(supplier_cost),0) recorded_booking_cost from public.bookings where archived_at is null group by supplier_id),pm as(select supplier_id,count(*) payable_count,coalesce(sum(amount_payable),0) payable_total,coalesce(sum(amount_paid),0) paid_total,coalesce(sum(amount_payable-amount_paid),0) open_balance,count(*) filter(where status='disputed') dispute_count,count(*) filter(where status='paid') paid_record_count from public.supplier_payments group by supplier_id)
 select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',s.status,'email',s.email,'phone',s.phone,'payment_terms',s.payment_terms,'notes',s.notes,'booking_count',coalesce(bm.booking_count,0),'recorded_booking_cost',coalesce(bm.recorded_booking_cost,0),'payable_count',coalesce(pm.payable_count,0),'payable_total',coalesce(pm.payable_total,0),'paid_total',coalesce(pm.paid_total,0),'open_balance',coalesce(pm.open_balance,0),'dispute_count',coalesce(pm.dispute_count,0),'paid_record_count',coalesce(pm.paid_record_count,0)) order by coalesce(pm.open_balance,0) desc,s.name) from public.suppliers s left join bm on bm.supplier_id=s.id left join pm on pm.supplier_id=s.id),'[]'::jsonb);
end;$function$;
revoke execute on function public.list_supplier_performance() from public,anon;
grant execute on function public.list_supplier_performance() to authenticated,service_role;
