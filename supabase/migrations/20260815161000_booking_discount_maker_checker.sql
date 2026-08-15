-- Activate the canonical approval ledger for booking price reductions.
alter table public.approval_requests add column if not exists request_payload jsonb not null default '{}'::jsonb;
revoke insert,update,delete on public.approval_requests from anon,authenticated;
drop policy if exists approval_requests_insert_staff on public.approval_requests;
drop policy if exists approval_requests_update_approver on public.approval_requests;

create or replace function public.request_booking_discount(p_booking_id uuid,p_proposed_selling_price numeric,p_reason text)
returns uuid language plpgsql security definer set search_path='public' as $function$
declare v public.bookings%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_staff_permission('edit_bookings') then raise exception 'Booking edit permission required'; end if;
 if char_length(trim(coalesce(p_reason,'')))<10 then raise exception 'Discount reason must be at least 10 characters'; end if;
 select * into v from public.bookings where id=p_booking_id and archived_at is null for update;
 if not found then raise exception 'Booking not found'; end if;
 if v.selling_price is null or p_proposed_selling_price is null or p_proposed_selling_price>=v.selling_price then raise exception 'Proposed price must be lower than the current selling price'; end if;
 if p_proposed_selling_price<coalesce(v.supplier_cost,0) then raise exception 'Below-cost pricing requires the negative-margin exception workflow'; end if;
 if exists(select 1 from public.approval_requests where request_type='discount' and entity_type='booking' and entity_id=p_booking_id and status='pending') then raise exception 'A discount request is already pending for this booking'; end if;
 insert into public.approval_requests(request_type,entity_type,entity_id,amount,currency,reason,status,requested_by,request_payload)
 values('discount','booking',p_booking_id,v.selling_price-p_proposed_selling_price,v.currency,trim(p_reason),'pending',auth.uid(),
   jsonb_build_object('booking_reference',v.booking_reference,'original_selling_price',v.selling_price,'proposed_selling_price',p_proposed_selling_price,'supplier_cost',v.supplier_cost)) returning id into v_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(auth.uid(),'booking.discount_requested','approval_request',v_id,
   jsonb_build_object('booking_id',p_booking_id,'original_selling_price',v.selling_price,'proposed_selling_price',p_proposed_selling_price,'discount_amount',v.selling_price-p_proposed_selling_price,'reason',trim(p_reason)));
 return v_id;
end;$function$;

create or replace function public.decide_booking_discount(p_approval_request_id uuid,p_approve boolean,p_decision_note text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare a public.approval_requests%rowtype; v public.bookings%rowtype; v_original numeric; v_proposed numeric; v_status text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 perform public.require_recent_auth(1800);
 if not public.has_staff_permission('approve_discounts') then raise exception 'Discount approval permission required'; end if;
 if char_length(trim(coalesce(p_decision_note,'')))<10 then raise exception 'Decision note must be at least 10 characters'; end if;
 select * into a from public.approval_requests where id=p_approval_request_id for update;
 if not found or a.request_type<>'discount' or a.entity_type<>'booking' then raise exception 'Booking discount request not found'; end if;
 if a.status<>'pending' then raise exception 'Only pending discount requests can be decided'; end if;
 if a.requested_by=auth.uid() then raise exception 'Discount requester cannot decide the same request'; end if;
 v_original:=(a.request_payload->>'original_selling_price')::numeric; v_proposed:=(a.request_payload->>'proposed_selling_price')::numeric;
 select * into v from public.bookings where id=a.entity_id and archived_at is null for update;
 if not found then raise exception 'Booking not found'; end if;
 if v.selling_price is distinct from v_original then raise exception 'Booking price changed after this discount was requested'; end if;
 if p_approve and v_proposed<coalesce(v.supplier_cost,0) then raise exception 'Supplier cost changed; below-cost pricing requires the negative-margin workflow'; end if;
 v_status:=case when p_approve then 'approved' else 'rejected' end;
 update public.approval_requests set status=v_status,decided_by=auth.uid(),decided_at=now(),decision_note=trim(p_decision_note),updated_at=now() where id=a.id;
 if p_approve then update public.bookings set selling_price=v_proposed,updated_at=now() where id=v.id; end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(auth.uid(),'booking.discount_'||v_status,'approval_request',a.id,
   jsonb_build_object('booking_id',v.id,'requester_user_id',a.requested_by,'original_selling_price',v_original,'proposed_selling_price',v_proposed,'discount_amount',a.amount,'decision_note',trim(p_decision_note)));
 return jsonb_build_object('id',a.id,'status',v_status,'booking_id',v.id,'selling_price',case when p_approve then v_proposed else v_original end);
end;$function$;

create or replace function public.list_booking_discount_approvals(p_booking_id uuid)
returns jsonb language plpgsql security definer stable set search_path='public' as $function$
begin
 if auth.uid() is null or not public.has_staff_permission('view_bookings') then raise exception 'Permission denied'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount',amount,'currency',currency,'reason',reason,'status',status,'requested_by',requested_by,'decided_by',decided_by,'decided_at',decided_at,'decision_note',decision_note,'created_at',created_at,'request_payload',request_payload) order by created_at desc) from public.approval_requests where request_type='discount' and entity_type='booking' and entity_id=p_booking_id),'[]'::jsonb);
end;$function$;

revoke execute on function public.request_booking_discount(uuid,numeric,text) from public,anon; grant execute on function public.request_booking_discount(uuid,numeric,text) to authenticated,service_role;
revoke execute on function public.decide_booking_discount(uuid,boolean,text) from public,anon; grant execute on function public.decide_booking_discount(uuid,boolean,text) to authenticated,service_role;
revoke execute on function public.list_booking_discount_approvals(uuid) from public,anon; grant execute on function public.list_booking_discount_approvals(uuid) to authenticated,service_role;
