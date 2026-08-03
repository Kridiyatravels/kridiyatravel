-- Convert website corporate enquiries into corporate accounts, contacts, and bookings.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

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
  v_payment_terms := lower(replace(coalesce(v_details ->> 'Preferred_payment_terms', 'payment_before_booking'), ' ', '_'));
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

revoke execute on function public.convert_corporate_enquiry_to_booking(uuid, uuid, text, public.booking_service_type, text, date, date, text) from public;
revoke execute on function public.convert_corporate_enquiry_to_booking(uuid, uuid, text, public.booking_service_type, text, date, date, text) from anon;
grant execute on function public.convert_corporate_enquiry_to_booking(uuid, uuid, text, public.booking_service_type, text, date, date, text) to authenticated, service_role;
