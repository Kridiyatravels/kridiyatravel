create or replace function public.update_operations_booking_details(
  p_booking_id uuid,
  p_title text,
  p_service_type public.booking_service_type,
  p_route_or_destination text,
  p_travel_start date,
  p_travel_end date,
  p_customer_id uuid,
  p_selling_price numeric,
  p_supplier_cost numeric,
  p_supplier_id uuid,
  p_supplier_name text,
  p_supplier_reference text,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.bookings%rowtype;
  v_updated_at timestamptz;
  v_supplier_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Permission denied';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Expected booking version is required';
  end if;
  if nullif(trim(coalesce(p_title, '')), '') is null then
    raise exception 'Booking title is required';
  end if;
  if length(trim(p_title)) < 3 or length(trim(p_title)) > 220 then
    raise exception 'Booking title must be between 3 and 220 characters';
  end if;
  if p_travel_start is not null and p_travel_end is not null and p_travel_end < p_travel_start then
    raise exception 'Travel end date cannot be before travel start date';
  end if;
  if coalesce(p_selling_price, 0) < 0 or coalesce(p_supplier_cost, 0) < 0 then
    raise exception 'Booking prices cannot be negative';
  end if;

  if p_customer_id is not null and not exists (
    select 1
    from public.customers c
    where c.id = p_customer_id
      and c.active = true
      and c.archived_at is null
  ) then
    raise exception 'Active customer not found';
  end if;

  if p_supplier_id is not null then
    select s.name
    into v_supplier_name
    from public.suppliers s
    where s.id = p_supplier_id
      and s.status = 'active';

    if not found then
      raise exception 'Active supplier not found';
    end if;
  else
    v_supplier_name := nullif(trim(coalesce(p_supplier_name, '')), '');
  end if;

  select b.*
  into v_before
  from public.bookings b
  where b.id = p_booking_id
    and b.archived_at is null;

  if not found then
    raise exception 'Booking not found';
  end if;

  update public.bookings
  set title = trim(p_title),
      service_type = p_service_type,
      route_or_destination = nullif(trim(coalesce(p_route_or_destination, '')), ''),
      travel_start = p_travel_start,
      travel_end = p_travel_end,
      customer_id = p_customer_id,
      selling_price = p_selling_price,
      amount = p_selling_price,
      supplier_cost = p_supplier_cost,
      supplier_id = p_supplier_id,
      supplier_name = v_supplier_name,
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      updated_at = clock_timestamp()
  where id = p_booking_id
    and archived_at is null
    and updated_at = p_expected_updated_at
  returning updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Booking changed after this page was loaded. Reload and review the latest values.';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'booking.details_updated',
    'booking',
    p_booking_id,
    jsonb_build_object(
      'reference', v_before.booking_reference,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'before', jsonb_build_object(
        'title', v_before.title,
        'service_type', v_before.service_type,
        'route_or_destination', v_before.route_or_destination,
        'travel_start', v_before.travel_start,
        'travel_end', v_before.travel_end,
        'customer_id', v_before.customer_id,
        'selling_price', v_before.selling_price,
        'supplier_cost', v_before.supplier_cost,
        'supplier_id', v_before.supplier_id,
        'supplier_name', v_before.supplier_name,
        'supplier_reference', v_before.supplier_reference
      ),
      'after', jsonb_build_object(
        'title', trim(p_title),
        'service_type', p_service_type,
        'route_or_destination', nullif(trim(coalesce(p_route_or_destination, '')), ''),
        'travel_start', p_travel_start,
        'travel_end', p_travel_end,
        'customer_id', p_customer_id,
        'selling_price', p_selling_price,
        'supplier_cost', p_supplier_cost,
        'supplier_id', p_supplier_id,
        'supplier_name', v_supplier_name,
        'supplier_reference', nullif(trim(coalesce(p_supplier_reference, '')), '')
      )
    )
  );

  return v_updated_at;
end;
$$;

revoke execute on function public.update_operations_booking_details(
  uuid, text, public.booking_service_type, text, date, date, uuid, numeric, numeric,
  uuid, text, text, timestamptz
) from public, anon;
grant execute on function public.update_operations_booking_details(
  uuid, text, public.booking_service_type, text, date, date, uuid, numeric, numeric,
  uuid, text, text, timestamptz
) to authenticated, service_role;

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
  v_start date;
  v_end date;
  v_note text;
  v_created_customer boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('create_bookings') then
    raise exception 'Booking creation permission required';
  end if;

  select e.*
  into v_enquiry
  from public.enquiries e
  where e.id = p_enquiry_id
  for update;

  if not found then
    raise exception 'Enquiry not found';
  end if;

  select b.id
  into v_booking_id
  from public.bookings b
  where b.enquiry_id = p_enquiry_id
    and b.archived_at is null
  order by b.created_at asc
  limit 1;

  if found then
    return jsonb_build_object(
      'booking_id', v_booking_id,
      'customer_id', null,
      'created_customer', false,
      'existing_booking', true
    );
  end if;

  v_details := coalesce(v_enquiry.details, '{}'::jsonb);

  if nullif(trim(coalesce(v_details ->> 'Company_name', '')), '') is not null
     or v_enquiry.service_type ilike '%corporate%' then
    raise exception 'Corporate enquiries must use convert_corporate_enquiry_to_booking';
  end if;

  v_route := nullif(trim(coalesce(
    p_route_or_destination,
    v_details ->> 'Route_or_destination',
    v_enquiry.summary,
    ''
  )), '');
  v_title := nullif(trim(coalesce(p_title, v_enquiry.summary, v_enquiry.service_type || ' enquiry')), '');
  v_start := coalesce(p_travel_start, nullif(v_details ->> 'Travel_start', '')::date);
  v_end := coalesce(p_travel_end, nullif(v_details ->> 'Travel_end', '')::date);

  if length(coalesce(v_title, '')) < 3 or length(v_title) > 220 then
    raise exception 'Booking title must be between 3 and 220 characters';
  end if;
  if v_start is not null and v_end is not null and v_end < v_start then
    raise exception 'Travel end date cannot be before travel start date';
  end if;

  v_service := coalesce(
    p_service_type,
    case
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%flight%' then 'flight'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%visa%' then 'visa'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%hotel%' then 'hotel'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%holiday%' then 'holiday'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%umrah%' then 'umrah'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%cruise%' then 'cruise'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%insurance%' then 'insurance'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%transfer%' then 'transfer'::public.booking_service_type
      else 'other'::public.booking_service_type
    end
  );

  select c.id
  into v_customer_id
  from public.customers c
  where c.active = true
    and c.archived_at is null
    and (
      (v_enquiry.user_id is not null and c.auth_user_id = v_enquiry.user_id)
      or lower(c.email) = lower(v_enquiry.email)
    )
  order by (c.auth_user_id = v_enquiry.user_id) desc nulls last, c.created_at asc
  limit 1;

  if not found then
    insert into public.customers (
      auth_user_id,
      customer_type,
      full_name,
      email,
      phone,
      whatsapp,
      source,
      notes,
      created_by
    ) values (
      v_enquiry.user_id,
      'individual',
      trim(v_enquiry.full_name),
      lower(trim(v_enquiry.email)),
      nullif(trim(coalesce(v_enquiry.phone, '')), ''),
      nullif(trim(coalesce(v_enquiry.phone, '')), ''),
      'manual',
      'Created from enquiry ' || v_enquiry.reference,
      auth.uid()
    )
    returning id into v_customer_id;

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
    booking_reference,
    enquiry_id,
    service_type,
    title,
    booking_kind,
    customer_id,
    route_or_destination,
    travel_start,
    travel_end,
    selling_price,
    amount,
    staff_notes,
    source,
    priority,
    status,
    payment_status,
    created_by
  ) values (
    v_reference,
    p_enquiry_id,
    v_service,
    v_title,
    'individual',
    v_customer_id,
    v_route,
    v_start,
    v_end,
    v_enquiry.estimated_booking_value,
    v_enquiry.estimated_booking_value,
    nullif(v_note, ''),
    'admin',
    v_enquiry.priority,
    'enquiry',
    'not_requested',
    auth.uid()
  )
  returning id into v_booking_id;

  update public.enquiries
  set status = 'confirmed',
      pipeline_stage = 'booking',
      updated_at = now(),
      last_activity_at = now()
  where id = p_enquiry_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'enquiry.converted_to_individual_booking',
    'booking',
    v_booking_id,
    jsonb_build_object(
      'enquiry_id', p_enquiry_id,
      'enquiry_reference', v_enquiry.reference,
      'booking_reference', v_reference,
      'customer_id', v_customer_id,
      'created_customer', v_created_customer
    )
  );

  return jsonb_build_object(
    'booking_id', v_booking_id,
    'customer_id', v_customer_id,
    'created_customer', v_created_customer,
    'existing_booking', false
  );
end;
$$;

revoke execute on function public.convert_individual_enquiry_to_booking(
  uuid, text, public.booking_service_type, text, date, date, text
) from public, anon;
grant execute on function public.convert_individual_enquiry_to_booking(
  uuid, text, public.booking_service_type, text, date, date, text
) to authenticated, service_role;

create or replace function public.convert_corporate_enquiry_to_booking(
  p_enquiry_id uuid,
  p_corporate_account_id uuid default null,
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
set search_path to 'public'
as $function$
declare
  v_enquiry public.enquiries%rowtype;
  v_details jsonb;
  v_company_name text;
  v_contact_name text;
  v_job_title text;
  v_email text;
  v_phone text;
  v_whatsapp text;
  v_billing_email text;
  v_payment_terms text;
  v_lpo_required boolean;
  v_route text;
  v_title text;
  v_service public.booking_service_type;
  v_start date;
  v_end date;
  v_account_id uuid;
  v_contact_id uuid;
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
  v_created_company boolean := false;
  v_existing_booking boolean := false;
  v_note text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('create_bookings') then
    raise exception 'Booking creation permission required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  select *
  into v_enquiry
  from public.enquiries
  where id = p_enquiry_id;

  if not found then
    raise exception 'Enquiry not found';
  end if;

  select id
  into v_booking_id
  from public.bookings
  where enquiry_id = p_enquiry_id
    and archived_at is null
  order by created_at asc
  limit 1;

  if found then
    return jsonb_build_object(
      'booking_id', v_booking_id,
      'corporate_account_id', null,
      'corporate_contact_id', null,
      'created_company', false,
      'existing_booking', true
    );
  end if;

  v_details := coalesce(v_enquiry.details, '{}'::jsonb);
  v_company_name := nullif(trim(coalesce(v_details ->> 'Company_name', '')), '');
  v_contact_name := nullif(trim(coalesce(v_details ->> 'Name', v_enquiry.full_name, '')), '');
  v_job_title := nullif(trim(coalesce(v_details ->> 'Job_title', '')), '');
  v_email := nullif(trim(coalesce(v_enquiry.email, v_details ->> 'Email', '')), '');
  v_phone := nullif(trim(coalesce(v_enquiry.phone, v_details ->> 'Phone', '')), '');
  v_whatsapp := nullif(trim(coalesce(v_details ->> 'WhatsApp', v_phone, '')), '');
  v_billing_email := nullif(trim(coalesce(v_details ->> 'Billing_email', v_email, '')), '');
  v_payment_terms := case
    when lower(coalesce(v_details ->> 'Preferred_payment_terms', '')) like '%credit%' then 'credit_approved'
    when lower(coalesce(v_details ->> 'Preferred_payment_terms', '')) like '%monthly%' then 'monthly_billing'
    else 'payment_before_booking'
  end;
  v_lpo_required := lower(coalesce(v_details ->> 'LPO_required', '')) = 'yes';
  v_route := nullif(trim(coalesce(p_route_or_destination, v_details ->> 'Route_or_destination', v_enquiry.summary, '')), '');
  v_title := nullif(trim(coalesce(p_title, v_company_name || ' - ' || coalesce(v_details ->> 'Service_needed', v_enquiry.service_type), v_enquiry.summary)), '');
  v_start := coalesce(p_travel_start, nullif(v_details ->> 'Travel_start', '')::date);
  v_end := coalesce(p_travel_end, nullif(v_details ->> 'Travel_end', '')::date);

  v_service := coalesce(
    p_service_type,
    case
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%flight%' then 'flight'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%visa%' then 'visa'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%hotel%' then 'hotel'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%holiday%' then 'holiday'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%umrah%' then 'umrah'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%cruise%' then 'cruise'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%insurance%' then 'insurance'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%transfer%' then 'transfer'::public.booking_service_type
      when coalesce(v_details ->> 'Service_needed', v_enquiry.service_type) ilike '%corporate%' then 'corporate'::public.booking_service_type
      else 'other'::public.booking_service_type
    end
  );

  if v_company_name is null then
    raise exception 'Company name is required on the enquiry details';
  end if;

  if p_corporate_account_id is not null then
    select id
    into v_account_id
    from public.corporate_accounts
    where id = p_corporate_account_id
      and archived_at is null;

    if not found then
      raise exception 'Corporate account not found';
    end if;
  else
    select id
    into v_account_id
    from public.corporate_accounts
    where lower(company_name) = lower(v_company_name)
      and archived_at is null
    order by created_at asc
    limit 1;

    if not found then
      insert into public.corporate_accounts (
        company_name, billing_email, accounts_email, phone, payment_terms,
        credit_allowed, monthly_billing, lpo_required, status, notes, created_by
      ) values (
        v_company_name, v_billing_email, v_billing_email, v_phone,
        coalesce(nullif(v_payment_terms, ''), 'payment_before_booking'),
        false, false, v_lpo_required, 'prospect',
        'Created from enquiry ' || v_enquiry.reference,
        auth.uid()
      ) returning id into v_account_id;

      v_created_company := true;
    end if;
  end if;

  if v_contact_name is not null then
    select cc.id, cc.customer_id
    into v_contact_id, v_customer_id
    from public.corporate_contacts cc
    where cc.corporate_account_id = v_account_id
      and cc.active = true
      and (
        lower(cc.email) = lower(v_email)
        or (cc.email is null and lower(cc.full_name) = lower(v_contact_name))
      )
    order by cc.created_at asc
    limit 1;

    if not found then
      insert into public.customers (
        customer_type, full_name, email, phone, whatsapp, source, notes, created_by
      ) values (
        'corporate_contact', v_contact_name, v_email, v_phone, v_whatsapp,
        'corporate', 'Created from enquiry ' || v_enquiry.reference, auth.uid()
      ) returning id into v_customer_id;

      insert into public.corporate_contacts (
        corporate_account_id, customer_id, full_name, job_title, email, phone, whatsapp,
        is_authorized_contact, is_accounts_contact, notes, created_by
      ) values (
        v_account_id, v_customer_id, v_contact_name, v_job_title, v_email, v_phone, v_whatsapp,
        true, coalesce(v_billing_email = v_email, false),
        'Created from enquiry ' || v_enquiry.reference, auth.uid()
      ) returning id into v_contact_id;
    end if;
  end if;

  v_reference := public.next_booking_reference();
  v_note := concat_ws(E'\n',
    'Converted from enquiry ' || v_enquiry.reference,
    'Original summary: ' || v_enquiry.summary,
    'Traveller details: ' || nullif(v_details ->> 'Traveller_details', ''),
    'Budget/policy: ' || nullif(v_details ->> 'Budget_or_policy', ''),
    'Payment plan: ' || nullif(v_details ->> 'Preferred_payment_terms', ''),
    'LPO/PO required: ' || nullif(v_details ->> 'LPO_required', ''),
    'Original notes: ' || nullif(v_details ->> 'Notes', ''),
    nullif(trim(coalesce(p_notes, '')), '')
  );

  insert into public.bookings (
    booking_reference,
    enquiry_id,
    service_type,
    title,
    booking_kind,
    customer_id,
    corporate_account_id,
    corporate_contact_id,
    route_or_destination,
    travel_start,
    travel_end,
    supplier_name,
    staff_notes,
    source,
    status,
    payment_status,
    created_by
  ) values (
    v_reference,
    p_enquiry_id,
    v_service,
    coalesce(v_title, v_company_name || ' corporate request'),
    'corporate',
    v_customer_id,
    v_account_id,
    v_contact_id,
    v_route,
    v_start,
    v_end,
    null,
    nullif(v_note, ''),
    'corporate',
    'enquiry',
    'not_requested',
    auth.uid()
  ) returning id into v_booking_id;

  update public.enquiries
  set status = 'confirmed',
      pipeline_stage = 'booking',
      updated_at = now()
  where id = p_enquiry_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'enquiry.converted_to_corporate_booking',
    'booking',
    v_booking_id,
    jsonb_build_object(
      'enquiry_id', p_enquiry_id,
      'enquiry_reference', v_enquiry.reference,
      'booking_reference', v_reference,
      'corporate_account_id', v_account_id,
      'corporate_contact_id', v_contact_id,
      'created_company', v_created_company
    )
  );

  return jsonb_build_object(
    'booking_id', v_booking_id,
    'corporate_account_id', v_account_id,
    'corporate_contact_id', v_contact_id,
    'created_company', v_created_company,
    'existing_booking', v_existing_booking
  );
end;
$function$;

revoke execute on function public.convert_corporate_enquiry_to_booking(
  uuid, uuid, text, public.booking_service_type, text, date, date, text
) from public, anon;
grant execute on function public.convert_corporate_enquiry_to_booking(
  uuid, uuid, text, public.booking_service_type, text, date, date, text
) to authenticated, service_role;
