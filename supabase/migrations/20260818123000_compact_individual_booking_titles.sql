begin;

create or replace function public.convert_individual_enquiry_to_booking(
  p_enquiry_id uuid,
  p_title text default null,
  p_service_type public.booking_service_type default null,
  p_route_or_destination text default null,
  p_travel_start date default null,
  p_travel_end date default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enquiry public.enquiries%rowtype;
  v_details jsonb;
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
  v_service public.booking_service_type;
  v_title text;
  v_route text;
  v_route_name text;
  v_trip text;
  v_start date;
  v_end date;
  v_note text;
  v_created_customer boolean := false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_staff_permission('create_bookings') then
    raise exception 'Booking creation permission required';
  end if;

  select e.* into v_enquiry
  from public.enquiries e
  where e.id = p_enquiry_id
  for update;
  if not found then raise exception 'Enquiry not found'; end if;

  select b.id into v_booking_id
  from public.bookings b
  where b.enquiry_id = p_enquiry_id and b.archived_at is null
  order by b.created_at asc limit 1;
  if found then
    return jsonb_build_object('booking_id', v_booking_id, 'customer_id', null,
      'created_customer', false, 'existing_booking', true);
  end if;

  v_details := coalesce(v_enquiry.details, '{}'::jsonb);
  if nullif(trim(coalesce(v_details ->> 'Company_name', '')), '') is not null
     or v_enquiry.service_type ilike '%corporate%' then
    raise exception 'Corporate enquiries must use convert_corporate_enquiry_to_booking';
  end if;

  v_route := nullif(trim(coalesce(
    p_route_or_destination,
    v_details ->> 'Route_or_destination',
    v_details ->> 'Route',
    substring(v_enquiry.summary from '(?i)(?:^|·\s*)Route:\s*(.*?)(?=\s*·|$)'),
    ''
  )), '');
  v_trip := nullif(trim(coalesce(
    v_details ->> 'Trip',
    substring(v_enquiry.summary from '(?i)(?:^|·\s*)Trip:\s*(.*?)(?=\s*·|$)'),
    ''
  )), '');
  v_route_name := nullif(trim(regexp_replace(
    regexp_replace(coalesce(v_route, ''), '\s*\([A-Z0-9]{3}\)', '', 'g'),
    '\s*(⇄|↔|→)\s*', ' to ', 'g'
  )), '');
  v_title := nullif(trim(coalesce(
    p_title,
    case when v_route_name is not null then
      v_route_name || case when v_trip is not null then ' — ' || initcap(lower(v_trip)) else '' end
    end,
    initcap(replace(v_enquiry.service_type, '_', ' ')) || ' booking'
  )), '');
  v_start := coalesce(p_travel_start, nullif(v_details ->> 'Travel_start', '')::date);
  v_end := coalesce(p_travel_end, nullif(v_details ->> 'Travel_end', '')::date);

  if length(coalesce(v_title, '')) < 3 or length(v_title) > 220 then
    raise exception 'Booking title must be between 3 and 220 characters';
  end if;
  if v_start is not null and v_end is not null and v_end < v_start then
    raise exception 'Travel end date cannot be before travel start date';
  end if;

  v_service := coalesce(p_service_type, case
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%flight%' then 'flight'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%visa%' then 'visa'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%hotel%' then 'hotel'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%holiday%' then 'holiday'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%umrah%' then 'umrah'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%cruise%' then 'cruise'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%insurance%' then 'insurance'::public.booking_service_type
    when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%transfer%' then 'transfer'::public.booking_service_type
    else 'other'::public.booking_service_type end);

  select c.id into v_customer_id
  from public.customers c
  where c.active = true and c.archived_at is null and (
    (v_enquiry.user_id is not null and c.auth_user_id = v_enquiry.user_id)
    or lower(c.email) = lower(v_enquiry.email))
  order by (c.auth_user_id = v_enquiry.user_id) desc nulls last, c.created_at asc limit 1;

  if not found then
    insert into public.customers (
      auth_user_id, customer_type, full_name, email, phone, whatsapp, source, notes, created_by
    ) values (
      v_enquiry.user_id, 'individual', trim(v_enquiry.full_name), lower(trim(v_enquiry.email)),
      nullif(trim(coalesce(v_enquiry.phone, '')), ''), nullif(trim(coalesce(v_enquiry.phone, '')), ''),
      'manual', 'Created from enquiry ' || v_enquiry.reference, auth.uid()
    ) returning id into v_customer_id;
    v_created_customer := true;
  end if;

  v_reference := public.next_booking_reference();
  v_note := concat_ws(E'\n',
    'Converted from enquiry ' || v_enquiry.reference,
    'Original summary: ' || v_enquiry.summary,
    'Traveller details: ' || nullif(v_details ->> 'Traveller_details', ''),
    'Original notes: ' || nullif(v_details ->> 'Notes', ''),
    nullif(trim(coalesce(p_notes, '')), '')
  );

  insert into public.bookings (
    booking_reference, enquiry_id, service_type, title, booking_kind, customer_id,
    route_or_destination, travel_start, travel_end, selling_price, amount, staff_notes,
    source, priority, status, payment_status, created_by
  ) values (
    v_reference, p_enquiry_id, v_service, v_title, 'individual', v_customer_id,
    v_route, v_start, v_end, v_enquiry.estimated_booking_value, v_enquiry.estimated_booking_value,
    nullif(v_note, ''), 'admin', v_enquiry.priority, 'enquiry', 'not_requested', auth.uid()
  ) returning id into v_booking_id;

  update public.enquiries
  set status = 'confirmed', pipeline_stage = 'booking', updated_at = now(), last_activity_at = now()
  where id = p_enquiry_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'enquiry.converted_to_individual_booking', 'booking', v_booking_id,
    jsonb_build_object('enquiry_id', p_enquiry_id, 'enquiry_reference', v_enquiry.reference,
      'booking_reference', v_reference, 'customer_id', v_customer_id,
      'created_customer', v_created_customer));

  return jsonb_build_object('booking_id', v_booking_id, 'customer_id', v_customer_id,
    'created_customer', v_created_customer, 'existing_booking', false);
end;
$$;

revoke execute on function public.convert_individual_enquiry_to_booking(
  uuid, text, public.booking_service_type, text, date, date, text
) from public, anon;
grant execute on function public.convert_individual_enquiry_to_booking(
  uuid, text, public.booking_service_type, text, date, date, text
) to authenticated, service_role;

commit;
