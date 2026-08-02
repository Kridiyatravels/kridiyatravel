begin;

create or replace function public.list_my_corporate_quotes(
  p_corporate_account_id uuid default null,
  p_limit integer default 100
)
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', q.id,
    'booking_id', b.id,
    'booking_reference', b.booking_reference,
    'booking_title', b.title,
    'service_type', b.service_type,
    'route_or_destination', b.route_or_destination,
    'title', q.title,
    'description', q.description,
    'price_amount', q.price_amount,
    'currency', q.currency,
    'valid_until', q.valid_until,
    'terms', q.terms,
    'status', q.status,
    'responded_at', q.responded_at,
    'created_at', q.created_at,
    'updated_at', q.updated_at,
    'can_approve', cpm.can_approve_quotes
  ) order by q.created_at desc), '[]'::jsonb)
  from public.quotes q
  join public.bookings b
    on b.enquiry_id = q.enquiry_id
   and b.archived_at is null
   and b.booking_kind = 'corporate'
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where (select auth.uid()) is not null
    and (p_corporate_account_id is null or b.corporate_account_id = p_corporate_account_id)
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$function$;

create or replace function public.respond_my_corporate_quote(
  p_quote_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_quote public.quotes%rowtype;
  v_booking public.bookings%rowtype;
  v_actor uuid := auth.uid();
  v_status public.quote_status;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if p_status not in ('accepted', 'declined') then
    raise exception 'Quote can only be accepted or declined';
  end if;
  v_status := p_status::public.quote_status;

  select q.*
  into v_quote
  from public.quotes q
  join public.bookings b
    on b.enquiry_id = q.enquiry_id
   and b.archived_at is null
   and b.booking_kind = 'corporate'
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = v_actor
   and cpm.status = 'active'
   and cpm.can_approve_quotes = true
  where q.id = p_quote_id;

  if not found then
    raise exception 'Quote approval access denied';
  end if;

  if v_quote.status <> 'sent' then
    raise exception 'Only sent quotes can be accepted or declined';
  end if;

  select b.*
  into v_booking
  from public.bookings b
  where b.enquiry_id = v_quote.enquiry_id
    and b.archived_at is null
    and b.booking_kind = 'corporate'
  limit 1;

  update public.quotes
  set status = v_status,
      responded_at = now()
  where id = p_quote_id
  returning * into v_quote;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_actor,
    'corporate_portal.quote_responded',
    'quote',
    p_quote_id,
    jsonb_build_object(
      'status', v_status,
      'booking_id', v_booking.id,
      'booking_reference', v_booking.booking_reference,
      'corporate_account_id', v_booking.corporate_account_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'quote_id', v_quote.id,
    'status', v_quote.status,
    'responded_at', v_quote.responded_at,
    'booking_id', v_booking.id,
    'booking_reference', v_booking.booking_reference
  );
end;
$function$;

revoke execute on function public.list_my_corporate_quotes(uuid, integer) from public, anon;
revoke execute on function public.respond_my_corporate_quote(uuid, text) from public, anon;

grant execute on function public.list_my_corporate_quotes(uuid, integer) to authenticated, service_role;
grant execute on function public.respond_my_corporate_quote(uuid, text) to authenticated, service_role;

commit;
