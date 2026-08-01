begin;

alter table public.quotes
  add column if not exists booking_id uuid references public.bookings(id) on delete set null;

create index if not exists quotes_booking_id_idx on public.quotes(booking_id);

create or replace function public.get_booking_quote_context(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $function$
  select jsonb_build_object(
    'booking_id', b.id,
    'enquiry_id', b.enquiry_id,
    'source', b.source,
    'can_edit_quotes', public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings'),
    'quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'booking_id', q.booking_id,
        'enquiry_id', q.enquiry_id,
        'title', q.title,
        'description', q.description,
        'option_data', q.option_data,
        'addons', q.addons,
        'price_amount', q.price_amount,
        'currency', q.currency,
        'valid_until', q.valid_until,
        'terms', q.terms,
        'status', q.status,
        'responded_at', q.responded_at,
        'created_at', q.created_at
      ) order by q.created_at desc)
      from public.quotes q
      where q.booking_id = b.id
         or (b.enquiry_id is not null and q.enquiry_id = b.enquiry_id)
    ), '[]'::jsonb)
  )
  from public.bookings b
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_reports')
    );
$function$;

create or replace function public.create_booking_quote_option(
  p_booking_id uuid,
  p_title text,
  p_description text default null,
  p_price_amount numeric default null,
  p_currency text default 'AED',
  p_valid_until timestamptz default null,
  p_terms text default null,
  p_option_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_booking public.bookings%rowtype;
  v_quote public.quotes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings')) then
    raise exception 'Booking quote permission required';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
    and archived_at is null;

  if not found then
    raise exception 'Booking not found';
  end if;

  if length(trim(coalesce(p_title, ''))) < 3 then
    raise exception 'Quote title is required';
  end if;

  if coalesce(p_price_amount, 0) <= 0 then
    raise exception 'Quote amount must be greater than zero';
  end if;

  insert into public.quotes (
    enquiry_id,
    booking_id,
    title,
    description,
    option_data,
    price_amount,
    currency,
    valid_until,
    terms,
    status,
    created_by
  ) values (
    v_booking.enquiry_id,
    v_booking.id,
    trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    coalesce(p_option_data, '{}'::jsonb),
    p_price_amount,
    coalesce(nullif(trim(coalesce(p_currency, '')), ''), 'AED'),
    p_valid_until,
    nullif(trim(coalesce(p_terms, '')), ''),
    'sent',
    auth.uid()
  )
  returning * into v_quote;

  update public.bookings
  set status = case when status = 'enquiry' then 'quote_sent' else status end,
      updated_at = now()
  where id = v_booking.id;

  if v_booking.enquiry_id is not null then
    update public.enquiries
    set status = 'quote_sent',
        quote_sent_at = coalesce(quote_sent_at, now())
    where id = v_booking.enquiry_id;
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'booking.quote_sent',
    'quote',
    v_quote.id,
    jsonb_build_object(
      'booking_id', v_booking.id,
      'booking_reference', v_booking.booking_reference,
      'enquiry_id', v_booking.enquiry_id,
      'amount', v_quote.price_amount,
      'currency', v_quote.currency
    )
  );

  return jsonb_build_object(
    'ok', true,
    'quote', jsonb_build_object(
      'id', v_quote.id,
      'booking_id', v_quote.booking_id,
      'enquiry_id', v_quote.enquiry_id,
      'title', v_quote.title,
      'description', v_quote.description,
      'option_data', v_quote.option_data,
      'price_amount', v_quote.price_amount,
      'currency', v_quote.currency,
      'valid_until', v_quote.valid_until,
      'terms', v_quote.terms,
      'status', v_quote.status,
      'created_at', v_quote.created_at
    )
  );
end;
$function$;

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
    on (
      b.id = q.booking_id
      or (b.enquiry_id is not null and b.enquiry_id = q.enquiry_id)
    )
   and b.archived_at is null
   and b.booking_kind = 'corporate'
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where (select auth.uid()) is not null
    and q.status in ('sent', 'accepted', 'declined')
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
    on (
      b.id = q.booking_id
      or (b.enquiry_id is not null and b.enquiry_id = q.enquiry_id)
    )
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
  where b.archived_at is null
    and b.booking_kind = 'corporate'
    and (
      b.id = v_quote.booking_id
      or (b.enquiry_id is not null and b.enquiry_id = v_quote.enquiry_id)
    )
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

revoke execute on function public.get_booking_quote_context(uuid) from public, anon;
revoke execute on function public.create_booking_quote_option(uuid, text, text, numeric, text, timestamptz, text, jsonb) from public, anon;
revoke execute on function public.list_my_corporate_quotes(uuid, integer) from public, anon;
revoke execute on function public.respond_my_corporate_quote(uuid, text) from public, anon;

grant execute on function public.get_booking_quote_context(uuid) to authenticated, service_role;
grant execute on function public.create_booking_quote_option(uuid, text, text, numeric, text, timestamptz, text, jsonb) to authenticated, service_role;
grant execute on function public.list_my_corporate_quotes(uuid, integer) to authenticated, service_role;
grant execute on function public.respond_my_corporate_quote(uuid, text) to authenticated, service_role;

commit;
