-- Track customer chargebacks as an authoritative finance lifecycle.
alter table public.payments
  add column if not exists chargeback_reference text,
  add column if not exists chargeback_reason text,
  add column if not exists chargeback_reported_by uuid references auth.users(id) on delete set null,
  add column if not exists chargeback_reported_at timestamptz,
  add column if not exists chargeback_resolved_by uuid references auth.users(id) on delete set null,
  add column if not exists chargeback_resolved_at timestamptz,
  add column if not exists chargeback_resolution text;

alter table public.payments drop constraint if exists payments_status_check;
alter table public.payments add constraint payments_status_check check (status in (
  'draft','pending','proof_received','received','failed','cancelled',
  'refund_pending','refund_approved','refunded','chargeback_open','chargeback_won','chargeback_lost'
));
alter table public.payments add constraint payments_chargeback_resolution_check
  check (chargeback_resolution is null or chargeback_resolution in ('won','lost'));

create or replace function public.validate_booking_payment_status()
returns trigger language plpgsql security definer set search_path=public as $function$
declare sale_total numeric:=coalesce(new.selling_price,new.amount); received_total numeric; supplier_fully_paid boolean; refund_open boolean; refund_completed boolean;
begin
  if new.payment_status=old.payment_status then return new; end if;
  if coalesce(sale_total,0)<=0 and new.payment_status in ('paid','partially_paid') then
    new.payment_status := 'not_requested';
    return new;
  end if;
  select coalesce(sum(p.amount),0) into received_total from public.payments p
    where p.booking_id=new.id and p.payment_direction='customer_in' and p.status in ('received','chargeback_won');
  select exists(select 1 from public.supplier_payments sp where sp.booking_id=new.id and sp.status='paid' and sp.amount_paid>=sp.amount_payable) into supplier_fully_paid;
  select exists(select 1 from public.payments p where p.booking_id=new.id and p.status in ('refund_pending','refund_approved')),
         exists(select 1 from public.payments p where p.booking_id=new.id and p.status='refunded') into refund_open,refund_completed;
  if new.payment_status='paid' and received_total<sale_total then raise exception 'Paid status requires customer receipts covering the booking total'; end if;
  if new.payment_status='partially_paid' and (received_total<=0 or (sale_total is not null and received_total>=sale_total)) then raise exception 'Partially paid status requires a positive outstanding customer balance'; end if;
  if new.payment_status='supplier_paid' and not supplier_fully_paid then raise exception 'Supplier paid status requires a fully paid supplier record'; end if;
  if new.payment_status='refund_pending' and not refund_open then raise exception 'Refund pending status requires an open payment refund'; end if;
  if new.payment_status='refunded' and not refund_completed then raise exception 'Refunded status requires a completed payment refund'; end if;
  return new;
end;$function$;
revoke execute on function public.validate_booking_payment_status() from public,anon,authenticated;

create or replace function public.report_payment_chargeback(p_payment_id uuid, p_reference text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v public.payments%rowtype; v_received numeric; v_sale numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  if not public.has_staff_permission('edit_payments') then raise exception 'Permission denied'; end if;
  if nullif(trim(coalesce(p_reference,'')),'') is null then raise exception 'Provider dispute reference is required'; end if;
  if char_length(trim(coalesce(p_reason,''))) < 10 then raise exception 'Chargeback reason must be at least 10 characters'; end if;
  select * into v from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment not found'; end if;
  if v.payment_direction <> 'customer_in' or v.status <> 'received' then raise exception 'Only received customer payments can enter chargeback'; end if;
  update public.payments set status='chargeback_open', chargeback_reference=trim(p_reference),
    chargeback_reason=trim(p_reason), chargeback_reported_by=auth.uid(), chargeback_reported_at=now(),
    chargeback_resolved_by=null, chargeback_resolved_at=null, chargeback_resolution=null, updated_at=now()
  where id=p_payment_id;
  if v.booking_id is not null then
    select coalesce(sum(amount) filter (where payment_direction='customer_in' and status in ('received','chargeback_won')),0)
      into v_received from public.payments where booking_id=v.booking_id;
    select coalesce(selling_price,amount,0) into v_sale from public.bookings where id=v.booking_id;
    update public.bookings set payment_status=case when v_received<=0 then 'not_requested' when v_received<v_sale then 'partially_paid' else 'paid' end, updated_at=now() where id=v.booking_id;
  end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(auth.uid(),'payment.chargeback_reported','payment',p_payment_id,
    jsonb_build_object('booking_id',v.booking_id,'payment_reference',v.payment_reference,'amount',v.amount,'currency',v.currency,'chargeback_reference',trim(p_reference),'reason',trim(p_reason)));
  return jsonb_build_object('id',p_payment_id,'status','chargeback_open');
end;$function$;

create or replace function public.resolve_payment_chargeback(p_payment_id uuid, p_resolution text, p_note text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v public.payments%rowtype; v_status text; v_received numeric; v_sale numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  if not public.is_admin() then raise exception 'Owner or admin resolution required'; end if;
  if p_resolution not in ('won','lost') then raise exception 'Resolution must be won or lost'; end if;
  if char_length(trim(coalesce(p_note,''))) < 10 then raise exception 'Resolution note must be at least 10 characters'; end if;
  select * into v from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment not found'; end if;
  if v.status <> 'chargeback_open' then raise exception 'Only open chargebacks can be resolved'; end if;
  if v.chargeback_reported_by=auth.uid() then raise exception 'Chargeback reporter cannot resolve the same dispute'; end if;
  v_status := case when p_resolution='won' then 'chargeback_won' else 'chargeback_lost' end;
  update public.payments set status=v_status, chargeback_resolution=p_resolution,
    chargeback_resolved_by=auth.uid(), chargeback_resolved_at=now(),
    notes=case when notes is null then trim(p_note) else notes||E'\n'||trim(p_note) end, updated_at=now()
  where id=p_payment_id;
  if v.booking_id is not null then
    select coalesce(sum(amount) filter (where payment_direction='customer_in' and status in ('received','chargeback_won')),0)
      into v_received from public.payments where booking_id=v.booking_id;
    select coalesce(selling_price,amount,0) into v_sale from public.bookings where id=v.booking_id;
    update public.bookings set payment_status=case when v_received<=0 then 'not_requested' when v_received<v_sale then 'partially_paid' else 'paid' end, updated_at=now() where id=v.booking_id;
  end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(auth.uid(),'payment.chargeback_resolved','payment',p_payment_id,
    jsonb_build_object('reporter_user_id',v.chargeback_reported_by,'resolution',p_resolution,'note',trim(p_note),'amount',v.amount,'currency',v.currency));
  return jsonb_build_object('id',p_payment_id,'status',v_status,'resolution',p_resolution);
end;$function$;

revoke execute on function public.report_payment_chargeback(uuid,text,text) from public,anon;
grant execute on function public.report_payment_chargeback(uuid,text,text) to authenticated,service_role;
revoke execute on function public.resolve_payment_chargeback(uuid,text,text) from public,anon;
grant execute on function public.resolve_payment_chargeback(uuid,text,text) to authenticated,service_role;
