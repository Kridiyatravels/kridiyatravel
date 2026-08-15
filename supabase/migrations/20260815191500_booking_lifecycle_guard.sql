create or replace function public.enforce_booking_status_lifecycle() returns trigger language plpgsql security definer set search_path='public' as $function$
declare old_rank int;new_rank int;v_reason text;begin
 if new.status=old.status then return new;end if;
 old_rank:=array_position(array['enquiry','quote_sent','payment_pending','confirmed','paid','ticketed','completed']::text[],old.status::text);
 new_rank:=array_position(array['enquiry','quote_sent','payment_pending','confirmed','paid','ticketed','completed']::text[],new.status::text);
 if old.status::text in('completed','cancelled','refunded') then raise exception 'Terminal bookings cannot be reopened or changed';end if;
 if old_rank is not null and new_rank is not null and new_rank<old_rank then raise exception 'Booking status cannot move backward';end if;
 if new.status::text='completed' and (new.payment_status not in('paid','supplier_paid') or new.document_status not in('sent','archived')) then raise exception 'Completion requires paid customer status and sent/archived documents';end if;
 if new.status::text='refunded' and new.payment_status<>'refunded' then raise exception 'Refunded booking status requires completed refund evidence';end if;
 if new.status::text='cancelled' then v_reason:=nullif(trim(coalesce(new.staff_notes,'')),'');if v_reason is null or char_length(v_reason)<10 then raise exception 'Cancellation requires an internal reason of at least 10 characters';end if;end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(auth.uid(),'booking.status_transitioned','booking',new.id,jsonb_build_object('booking_reference',new.booking_reference,'from_status',old.status,'to_status',new.status,'payment_status',new.payment_status,'document_status',new.document_status,'reason',case when new.status::text='cancelled' then v_reason else null end));
 return new;end;$function$;
drop trigger if exists bookings_status_lifecycle_guard on public.bookings;
create trigger bookings_status_lifecycle_guard before update of status on public.bookings for each row execute function public.enforce_booking_status_lifecycle();
revoke execute on function public.enforce_booking_status_lifecycle() from public,anon,authenticated;
