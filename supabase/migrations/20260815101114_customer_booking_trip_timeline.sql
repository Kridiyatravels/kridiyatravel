create or replace function public.list_my_booking_timeline(p_booking_id uuid)
returns table(event_type text,title text,detail text,event_at timestamptz,tone text)
language sql stable security definer set search_path=public,pg_temp
as $$
  with owned as (
    select b.* from public.bookings b where b.id=p_booking_id and b.user_id=auth.uid() and b.archived_at is null
  ), events(event_type,title,detail,event_at,tone) as (
    select 'booking_created'::text,'Booking created'::text,coalesce(b.booking_reference,'Kridiya booking')::text,b.created_at,'complete'::text from owned b
    union all select 'booking_status','Booking status: '||initcap(replace(b.status::text,'_',' ')),coalesce(b.route_or_destination,b.title),b.updated_at,
      case when b.status::text in ('cancelled','refunded') then 'alert' when b.status::text in ('completed','ticketed','confirmed') then 'complete' else 'current' end from owned b
    union all select 'travel_start','Travel starts',coalesce(b.route_or_destination,b.title),b.travel_start::timestamptz,
      case when b.travel_start<current_date then 'complete' when b.travel_start=current_date then 'current' else 'upcoming' end from owned b where b.travel_start is not null
    union all select 'travel_end','Travel ends',coalesce(b.route_or_destination,b.title),b.travel_end::timestamptz,
      case when b.travel_end<current_date then 'complete' else 'upcoming' end from owned b where b.travel_end is not null
    union all select 'payment_'||p.status,'Payment: '||initcap(replace(p.status,'_',' ')),p.currency||' '||to_char(p.amount,'FM999999990.00'),coalesce(p.received_at,p.created_at),
      case when p.status='received' then 'complete' when p.status in ('failed','cancelled') then 'alert' else 'current' end
      from public.payments p join owned b on b.id=p.booking_id where p.payment_direction='customer_in'
    union all select 'payment_proof','Payment proof submitted','Awaiting verification',p.proof_uploaded_at,'current'
      from public.payments p join owned b on b.id=p.booking_id where p.proof_uploaded_at is not null
    union all select 'refund_requested','Refund requested',coalesce(p.refund_reason,'Kridiya is reviewing the request'),p.refund_requested_at,'current'
      from public.payments p join owned b on b.id=p.booking_id where p.refund_requested_at is not null
    union all select 'refund_completed','Refund completed',coalesce(p.refund_reference,'Refund processed'),p.refund_completed_at,'complete'
      from public.payments p join owned b on b.id=p.booking_id where p.refund_completed_at is not null
    union all select 'document_released','Document available',coalesce(bd.file_name,initcap(replace(bd.document_type,'_',' '))),bd.created_at,'complete'
      from public.booking_documents bd join owned b on b.id=bd.booking_id where bd.visible_to_customer=true
    union all select 'support_'||r.status,'Support: '||r.subject,initcap(replace(r.status,'_',' ')),coalesce(r.resolved_at,r.created_at),
      case when r.status in ('resolved','closed') then 'complete' when r.status='cancelled' then 'alert' else 'current' end
      from public.customer_support_requests r join owned b on b.id=r.booking_id
  )
  select event_type,title,detail,event_at,tone from events where event_at is not null order by event_at,event_type
$$;

revoke execute on function public.list_my_booking_timeline(uuid) from public,anon;
grant execute on function public.list_my_booking_timeline(uuid) to authenticated,service_role;
