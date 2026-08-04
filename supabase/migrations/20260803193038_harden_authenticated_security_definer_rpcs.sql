-- Harden intentionally exposed SECURITY DEFINER RPCs without revoking authenticated access.
-- Generated from the exact live function definitions audited on 2026-08-03.
-- 40 functions are replaced: 39 missing an explicit auth.uid() guard and one with an inverted guard.

-- approve_corporate_application(p_enquiry_id uuid, p_auth_user_id uuid, p_role text, p_can_request boolean, p_can_approve_quotes boolean, p_can_view_finance boolean, p_can_view_documents boolean, p_notes text)
CREATE OR REPLACE FUNCTION public.approve_corporate_application(p_enquiry_id uuid, p_auth_user_id uuid DEFAULT NULL::uuid, p_role text DEFAULT 'travel_coordinator'::text, p_can_request boolean DEFAULT true, p_can_approve_quotes boolean DEFAULT false, p_can_view_finance boolean DEFAULT false, p_can_view_documents boolean DEFAULT true, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_user_id uuid := auth.uid();
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
  v_customer_id uuid;
  v_booking_reference text;
  v_note text;
  v_booking_id uuid;
  v_account_id uuid;
  v_contact_id uuid;
  v_member_id uuid;
  v_enquiry_reference text;
  v_portal_status text := 'pending_user';
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if v_actor_user_id is not null then
    if not public.has_staff_permission('create_bookings') then
      raise exception 'Booking creation permission required';
    end if;

    if not public.has_staff_permission('edit_corporates') then
      raise exception 'Corporate edit permission required';
    end if;
  end if;

  select *
  into v_enquiry
  from public.enquiries
  where id = p_enquiry_id;

  if not found then
    raise exception 'Corporate application enquiry not found';
  end if;

  v_enquiry_reference := v_enquiry.reference;

  select id, corporate_account_id, corporate_contact_id
  into v_booking_id, v_account_id, v_contact_id
  from public.bookings
  where enquiry_id = p_enquiry_id
    and archived_at is null
  order by created_at asc
  limit 1;

  if v_booking_id is null then
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
    v_route := nullif(trim(coalesce(v_details ->> 'Route_or_destination', v_enquiry.summary, '')), '');

    if v_company_name is null then
      raise exception 'Company name is required on the enquiry details';
    end if;

    select id
    into v_account_id
    from public.corporate_accounts
    where lower(company_name) = lower(v_company_name)
      and archived_at is null
    order by created_at asc
    limit 1;

    if v_account_id is null then
      insert into public.corporate_accounts (
        company_name, billing_email, accounts_email, phone, payment_terms,
        credit_allowed, monthly_billing, lpo_required, status, notes, created_by
      ) values (
        v_company_name, v_billing_email, v_billing_email, v_phone,
        coalesce(nullif(v_payment_terms, ''), 'payment_before_booking'),
        false, false, v_lpo_required, 'active',
        'Approved from corporate application ' || v_enquiry_reference,
        v_actor_user_id
      ) returning id into v_account_id;
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

      if v_contact_id is null then
        insert into public.customers (
          customer_type, full_name, email, phone, whatsapp, source, notes, created_by
        ) values (
          'corporate_contact', v_contact_name, v_email, v_phone, v_whatsapp,
          'corporate', 'Approved from enquiry ' || v_enquiry_reference, v_actor_user_id
        ) returning id into v_customer_id;

        insert into public.corporate_contacts (
          corporate_account_id, customer_id, full_name, job_title, email, phone, whatsapp,
          is_authorized_contact, is_accounts_contact, notes, created_by
        ) values (
          v_account_id, v_customer_id, v_contact_name, v_job_title, v_email, v_phone, v_whatsapp,
          true, coalesce(v_billing_email = v_email, false),
          'Approved from enquiry ' || v_enquiry_reference, v_actor_user_id
        ) returning id into v_contact_id;
      end if;
    end if;

    v_booking_reference := public.next_booking_reference();
    v_note := concat_ws(E'\n',
      'Approved corporate application ' || v_enquiry_reference,
      'Original summary: ' || v_enquiry.summary,
      'Requested services: ' || nullif(v_details ->> 'Service_needed', ''),
      'Monthly volume: ' || nullif(v_details ->> 'Monthly_travel_volume', ''),
      'Billing/LPO: ' || nullif(v_details ->> 'Billing_or_LPO_requirement', ''),
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
      supplier_name,
      staff_notes,
      source,
      status,
      payment_status,
      created_by
    ) values (
      v_booking_reference,
      p_enquiry_id,
      'corporate'::public.booking_service_type,
      v_company_name || ' corporate account',
      'corporate',
      v_customer_id,
      v_account_id,
      v_contact_id,
      v_route,
      null,
      nullif(v_note, ''),
      'corporate',
      'enquiry',
      'not_requested',
      v_actor_user_id
    ) returning id into v_booking_id;
  end if;

  if v_account_id is null then
    raise exception 'Corporate account could not be resolved from application';
  end if;

  update public.corporate_accounts
  set status = 'active',
      notes = concat_ws(E'\n', nullif(notes, ''), 'Approved from corporate application ' || v_enquiry_reference),
      updated_at = now()
  where id = v_account_id
    and archived_at is null;

  if p_auth_user_id is not null then
    if not exists (select 1 from auth.users where id = p_auth_user_id) then
      raise exception 'Corporate Auth user not found';
    end if;

    insert into public.corporate_portal_members (
      corporate_account_id,
      corporate_contact_id,
      user_id,
      role,
      status,
      can_request,
      can_approve_quotes,
      can_view_finance,
      can_view_documents,
      notes,
      invited_by
    ) values (
      v_account_id,
      v_contact_id,
      p_auth_user_id,
      coalesce(nullif(trim(coalesce(p_role, '')), ''), 'travel_coordinator'),
      'active',
      coalesce(p_can_request, true),
      coalesce(p_can_approve_quotes, false),
      coalesce(p_can_view_finance, false),
      coalesce(p_can_view_documents, true),
      concat_ws(E'\n', 'Approved from enquiry ' || v_enquiry_reference, nullif(trim(coalesce(p_notes, '')), '')),
      v_actor_user_id
    )
    on conflict (corporate_account_id, user_id)
    do update set
      corporate_contact_id = excluded.corporate_contact_id,
      role = excluded.role,
      status = excluded.status,
      can_request = excluded.can_request,
      can_approve_quotes = excluded.can_approve_quotes,
      can_view_finance = excluded.can_view_finance,
      can_view_documents = excluded.can_view_documents,
      notes = excluded.notes,
      updated_at = now()
    returning id into v_member_id;

    v_portal_status := 'active';
  end if;

  update public.enquiries
  set status = 'confirmed',
      details = jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(details, '{}'::jsonb),
            '{Corporate_approval_status}',
            to_jsonb('approved'::text),
            true
          ),
          '{Corporate_portal_status}',
          to_jsonb(v_portal_status),
          true
        ),
        '{Corporate_approved_at}',
        to_jsonb(now()),
        true
      ),
      updated_at = now()
  where id = p_enquiry_id;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_actor_user_id,
    p_auth_user_id,
    'corporate_application.approved',
    'corporate_account',
    v_account_id,
    jsonb_build_object(
      'enquiry_id', p_enquiry_id,
      'enquiry_reference', v_enquiry_reference,
      'booking_id', v_booking_id,
      'corporate_contact_id', v_contact_id,
      'portal_member_id', v_member_id,
      'portal_status', v_portal_status
    )
  );

  return jsonb_build_object(
    'ok', true,
    'enquiry_id', p_enquiry_id,
    'enquiry_reference', v_enquiry_reference,
    'booking_id', v_booking_id,
    'corporate_account_id', v_account_id,
    'corporate_contact_id', v_contact_id,
    'portal_member_id', v_member_id,
    'portal_status', v_portal_status
  );
end;
$function$
;

-- approve_payment_refund(p_payment_id uuid, p_note text)
CREATE OR REPLACE FUNCTION public.approve_payment_refund(p_payment_id uuid, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment public.payments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.can_approve_refunds() then
    raise exception 'Refund approval permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if v_payment.status <> 'refund_pending' then
    raise exception 'Only pending refunds can be approved';
  end if;

  update public.payments
  set status = 'refund_approved',
      refund_approved_by = auth.uid(),
      refund_approved_at = now(),
      notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))),
      updated_at = now()
  where id = p_payment_id;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.refund_approved', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference, 'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency, 'note', nullif(trim(coalesce(p_note, '')), '')));

  return p_payment_id;
end;
$function$
;

-- booking_profit_summary()
CREATE OR REPLACE FUNCTION public.booking_profit_summary()
 RETURNS TABLE(booking_id uuid, booking_reference text, service_type booking_service_type, selling_price numeric, supplier_cost numeric, gross_profit numeric, currency text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select
    b.id,
    b.booking_reference,
    b.service_type,
    coalesce(b.selling_price, b.amount, 0) as selling_price,
    coalesce(b.supplier_cost, 0) as supplier_cost,
    coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) as gross_profit,
    b.currency,
    b.created_at
  from public.bookings b
  where public.has_staff_permission('view_profit')
    and b.archived_at is null
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- can_approve_refunds()
CREATE OR REPLACE FUNCTION public.can_approve_refunds()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select auth.uid() is not null
    and coalesce(guarded.value, false)
  from (

  select public.is_admin() or public.has_staff_permission('approve_refunds')
  ) as guarded(value);
$function$
;

-- complete_payment_refund(p_payment_id uuid, p_refund_method text, p_refund_reference text, p_note text)
CREATE OR REPLACE FUNCTION public.complete_payment_refund(p_payment_id uuid, p_refund_method text, p_refund_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment public.payments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.can_approve_refunds() then
    raise exception 'Refund completion permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if v_payment.status not in ('refund_pending', 'refund_approved') then
    raise exception 'Only pending or approved refunds can be completed';
  end if;

  if nullif(trim(coalesce(p_refund_method, '')), '') is null then
    raise exception 'Refund method is required';
  end if;

  update public.payments
  set status = 'refunded', refund_method = nullif(trim(p_refund_method), ''), refund_reference = nullif(trim(coalesce(p_refund_reference, '')), ''), refund_completed_by = auth.uid(), refund_completed_at = now(), notes = trim(both from concat_ws(E'\n', nullif(notes, ''), nullif(p_note, ''))), updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings set payment_status = 'refunded', updated_at = now() where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.refund_completed', 'payment', p_payment_id,
    jsonb_build_object('booking_id', v_payment.booking_id, 'payment_reference', v_payment.payment_reference, 'refund_amount', v_payment.refund_amount, 'currency', v_payment.currency, 'method', nullif(trim(p_refund_method), ''), 'reference', nullif(trim(coalesce(p_refund_reference, '')), ''), 'note', nullif(trim(coalesce(p_note, '')), '')));

  return p_payment_id;
end;
$function$
;

-- create_operations_booking(p_title text, p_service_type booking_service_type, p_booking_kind text, p_customer_name text, p_customer_email text, p_customer_phone text, p_corporate_account_id uuid, p_route_or_destination text, p_travel_start date, p_travel_end date, p_selling_price numeric, p_supplier_cost numeric, p_supplier_name text, p_portal_id uuid, p_notes text)
CREATE OR REPLACE FUNCTION public.create_operations_booking(p_title text, p_service_type booking_service_type, p_booking_kind text DEFAULT 'individual'::text, p_customer_name text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_phone text DEFAULT NULL::text, p_corporate_account_id uuid DEFAULT NULL::uuid, p_route_or_destination text DEFAULT NULL::text, p_travel_start date DEFAULT NULL::date, p_travel_end date DEFAULT NULL::date, p_selling_price numeric DEFAULT NULL::numeric, p_supplier_cost numeric DEFAULT NULL::numeric, p_supplier_name text DEFAULT NULL::text, p_portal_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('create_bookings') then
    raise exception 'Permission denied';
  end if;

  if p_customer_name is not null and length(trim(p_customer_name)) >= 2 then
    insert into public.customers (full_name, email, phone, source, created_by)
    values (trim(p_customer_name), nullif(trim(coalesce(p_customer_email, '')), ''), nullif(trim(coalesce(p_customer_phone, '')), ''),
      case when p_booking_kind = 'corporate' then 'corporate' else 'manual' end,
      auth.uid())
    returning id into v_customer_id;
  end if;

  v_reference := public.next_booking_reference();

  insert into public.bookings (
    booking_reference,
    service_type,
    title,
    booking_kind,
    customer_id,
    corporate_account_id,
    route_or_destination,
    travel_start,
    travel_end,
    selling_price,
    supplier_cost,
    amount,
    supplier_name,
    portal_id,
    staff_notes,
    source,
    status,
    payment_status,
    created_by
  ) values (
    v_reference,
    p_service_type,
    trim(p_title),
    coalesce(nullif(p_booking_kind, ''), 'individual'),
    v_customer_id,
    p_corporate_account_id,
    nullif(trim(coalesce(p_route_or_destination, '')), ''),
    p_travel_start,
    p_travel_end,
    p_selling_price,
    p_supplier_cost,
    p_selling_price,
    nullif(trim(coalesce(p_supplier_name, '')), ''),
    p_portal_id,
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_booking_kind = 'corporate' then 'corporate' else 'manual' end,
    'enquiry',
    'not_requested',
    auth.uid()
  ) returning id into v_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.created', 'booking', v_booking_id, jsonb_build_object('reference', v_reference, 'title', p_title, 'service_type', p_service_type));

  return v_booking_id;
end;
$function$
;

-- create_operations_booking(p_title text, p_service_type booking_service_type, p_booking_kind text, p_customer_name text, p_customer_email text, p_customer_phone text, p_corporate_account_id uuid, p_route_or_destination text, p_travel_start date, p_travel_end date, p_selling_price numeric, p_supplier_cost numeric, p_supplier_name text, p_portal_id uuid, p_notes text, p_corporate_contact_id uuid)
CREATE OR REPLACE FUNCTION public.create_operations_booking(p_title text, p_service_type booking_service_type, p_booking_kind text DEFAULT 'individual'::text, p_customer_name text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_phone text DEFAULT NULL::text, p_corporate_account_id uuid DEFAULT NULL::uuid, p_route_or_destination text DEFAULT NULL::text, p_travel_start date DEFAULT NULL::date, p_travel_end date DEFAULT NULL::date, p_selling_price numeric DEFAULT NULL::numeric, p_supplier_cost numeric DEFAULT NULL::numeric, p_supplier_name text DEFAULT NULL::text, p_portal_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_corporate_contact_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
  v_contact_account_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('create_bookings') then
    raise exception 'Permission denied';
  end if;

  if p_booking_kind = 'corporate' and p_corporate_account_id is null then
    raise exception 'Corporate account is required for corporate bookings';
  end if;

  if p_corporate_contact_id is not null then
    select cc.customer_id, cc.corporate_account_id
    into v_customer_id, v_contact_account_id
    from public.corporate_contacts cc
    where cc.id = p_corporate_contact_id
      and cc.active = true;
    if not found then
      raise exception 'Corporate contact not found';
    end if;
    if p_corporate_account_id is not null and v_contact_account_id <> p_corporate_account_id then
      raise exception 'Corporate contact does not belong to selected company';
    end if;
    p_corporate_account_id := v_contact_account_id;
  elsif p_customer_name is not null and length(trim(p_customer_name)) >= 2 then
    insert into public.customers (customer_type, full_name, email, phone, whatsapp, source, created_by)
    values (
      case when p_booking_kind = 'corporate' then 'corporate_contact' else 'individual' end,
      trim(p_customer_name),
      nullif(trim(coalesce(p_customer_email, '')), ''),
      nullif(trim(coalesce(p_customer_phone, '')), ''),
      nullif(trim(coalesce(p_customer_phone, '')), ''),
      case when p_booking_kind = 'corporate' then 'corporate' else 'manual' end,
      auth.uid()
    ) returning id into v_customer_id;

    if p_booking_kind = 'corporate' and p_corporate_account_id is not null then
      insert into public.corporate_contacts (
        corporate_account_id, customer_id, full_name, email, phone, whatsapp,
        is_authorized_contact, is_accounts_contact, created_by
      ) values (
        p_corporate_account_id, v_customer_id, trim(p_customer_name),
        nullif(trim(coalesce(p_customer_email, '')), ''), nullif(trim(coalesce(p_customer_phone, '')), ''), nullif(trim(coalesce(p_customer_phone, '')), ''),
        true, false, auth.uid()
      ) returning id into p_corporate_contact_id;
    end if;
  end if;

  v_reference := public.next_booking_reference();

  insert into public.bookings (
    booking_reference,
    service_type,
    title,
    booking_kind,
    customer_id,
    corporate_account_id,
    corporate_contact_id,
    route_or_destination,
    travel_start,
    travel_end,
    selling_price,
    supplier_cost,
    amount,
    supplier_name,
    portal_id,
    staff_notes,
    source,
    status,
    payment_status,
    created_by
  ) values (
    v_reference,
    p_service_type,
    trim(p_title),
    coalesce(nullif(p_booking_kind, ''), 'individual'),
    v_customer_id,
    p_corporate_account_id,
    p_corporate_contact_id,
    nullif(trim(coalesce(p_route_or_destination, '')), ''),
    p_travel_start,
    p_travel_end,
    p_selling_price,
    p_supplier_cost,
    p_selling_price,
    nullif(trim(coalesce(p_supplier_name, '')), ''),
    p_portal_id,
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_booking_kind = 'corporate' then 'corporate' else 'manual' end,
    'enquiry',
    'not_requested',
    auth.uid()
  ) returning id into v_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.created', 'booking', v_booking_id, jsonb_build_object('reference', v_reference, 'title', p_title, 'service_type', p_service_type, 'booking_kind', p_booking_kind, 'corporate_account_id', p_corporate_account_id));

  return v_booking_id;
end;
$function$
;

-- delete_staff_profile(target_user_id uuid)
CREATE OR REPLACE FUNCTION public.delete_staff_profile(target_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can delete staff profiles';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'You cannot delete your own staff profile';
  end if;
  if public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  delete from public.staff_permissions where user_id = target_user_id;
  delete from public.staff_roles where user_id = target_user_id;
  update public.staff_profiles
  set active = false,
      deleted_at = now(),
      hold_until = null,
      hold_reason = null,
      updated_at = now()
  where user_id = target_user_id;

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.profile_deleted', 'user', target_user_id, '{}'::jsonb);

  return 'deleted';
end;
$function$
;

-- get_booking_quote_context(p_booking_id uuid)
CREATE OR REPLACE FUNCTION public.get_booking_quote_context(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

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
    )
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- get_booking_workflow(p_booking_id uuid)
CREATE OR REPLACE FUNCTION public.get_booking_workflow(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select jsonb_build_object(
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'task_type', t.task_type,
        'entity_type', t.entity_type,
        'entity_id', t.entity_id,
        'assigned_to', t.assigned_to,
        'assigned_to_name', sp.full_name,
        'due_at', t.due_at,
        'status', t.status,
        'priority', t.priority,
        'notes', t.notes,
        'created_by', t.created_by,
        'created_by_name', creator.full_name,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'completed_at', t.completed_at
      ) order by case when t.status = 'completed' then 1 else 0 end, t.due_at nulls last, t.created_at desc)
      from public.tasks_reminders t
      left join public.staff_profiles sp on sp.user_id = t.assigned_to
      left join public.staff_profiles creator on creator.user_id = t.created_by
      where t.entity_type = 'booking'
        and t.entity_id = b.id
    ), '[]'::jsonb),
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ae.id,
        'event_type', ae.event_type,
        'entity_type', ae.entity_type,
        'entity_id', ae.entity_id,
        'actor_user_id', ae.actor_user_id,
        'actor_name', actor.full_name,
        'metadata', ae.metadata,
        'created_at', ae.created_at
      ) order by ae.created_at desc)
      from public.audit_events ae
      left join public.staff_profiles actor on actor.user_id = ae.actor_user_id
      where ae.entity_type = 'booking'
        and ae.entity_id = b.id
      limit 80
    ), '[]'::jsonb),
    'can_edit_tasks', public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings'),
    'can_view_activity', public.has_staff_permission('view_reports') or public.has_staff_permission('edit_bookings')
  )
  from public.bookings b
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    )
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- get_my_corporate_booking_detail(p_booking_id uuid)
CREATE OR REPLACE FUNCTION public.get_my_corporate_booking_detail(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select jsonb_build_object(
    'booking', jsonb_build_object(
      'id', b.id,
      'booking_reference', b.booking_reference,
      'title', b.title,
      'service_type', b.service_type,
      'route_or_destination', b.route_or_destination,
      'travel_start', b.travel_start,
      'travel_end', b.travel_end,
      'status', b.status,
      'payment_status', b.payment_status,
      'document_status', b.document_status,
      'amount', case when cpm.can_view_finance then coalesce(b.selling_price, b.amount) else null end,
      'currency', b.currency,
      'customer_notes', b.customer_notes,
      'created_at', b.created_at,
      'updated_at', b.updated_at
    ),
    'corporate', jsonb_build_object(
      'id', ca.id,
      'company_name', ca.company_name,
      'payment_terms', ca.payment_terms,
      'monthly_billing', ca.monthly_billing,
      'lpo_required', ca.lpo_required
    ),
    'documents', case when cpm.can_view_documents then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bd.id,
        'booking_id', bd.booking_id,
        'document_type', bd.document_type,
        'file_name', bd.file_name,
        'storage_path', bd.storage_path,
        'external_reference', bd.external_reference,
        'visible_to_customer', bd.visible_to_customer,
        'created_at', bd.created_at
      ) order by bd.created_at desc)
      from public.booking_documents bd
      where bd.booking_id = b.id
        and bd.visible_to_customer = true
    ), '[]'::jsonb) else '[]'::jsonb end,
    'payments', case when cpm.can_view_finance then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'payment_reference', p.payment_reference,
        'amount', p.amount,
        'currency', p.currency,
        'method', p.method,
        'status', p.status,
        'received_at', p.received_at,
        'created_at', p.created_at
      ) order by p.created_at desc)
      from public.payments p
      where p.booking_id = b.id
        and p.payment_direction = 'customer_in'
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  from public.bookings b
  join public.corporate_accounts ca on ca.id = b.corporate_account_id
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where b.id = p_booking_id
    and b.archived_at is null
    and b.booking_kind = 'corporate'
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- get_my_corporate_portal()
CREATE OR REPLACE FUNCTION public.get_my_corporate_portal()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select coalesce(jsonb_agg(jsonb_build_object(
    'corporate_account_id', ca.id,
    'company_name', ca.company_name,
    'status', ca.status,
    'payment_terms', ca.payment_terms,
    'monthly_billing', ca.monthly_billing,
    'lpo_required', ca.lpo_required,
    'member_role', cpm.role,
    'can_request', cpm.can_request,
    'can_approve_quotes', cpm.can_approve_quotes,
    'can_view_finance', cpm.can_view_finance,
    'can_view_documents', cpm.can_view_documents
  ) order by ca.company_name), '[]'::jsonb)
  from public.corporate_portal_members cpm
  join public.corporate_accounts ca on ca.id = cpm.corporate_account_id
  where cpm.user_id = (select auth.uid())
    and cpm.status = 'active'
    and ca.archived_at is null
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- get_operations_booking_detail(p_booking_id uuid)
CREATE OR REPLACE FUNCTION public.get_operations_booking_detail(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select jsonb_build_object(
    'booking', jsonb_build_object(
      'id', b.id,
      'booking_reference', b.booking_reference,
      'title', b.title,
      'booking_kind', b.booking_kind,
      'service_type', b.service_type,
      'route_or_destination', b.route_or_destination,
      'travel_start', b.travel_start,
      'travel_end', b.travel_end,
      'status', b.status,
      'payment_status', b.payment_status,
      'document_status', b.document_status,
      'supplier_name', b.supplier_name,
      'supplier_reference', b.supplier_reference,
      'lpo_number', b.lpo_number,
      'approval_person', b.approval_person,
      'selling_price', case when public.has_staff_permission('view_payments') or public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount) else null end,
      'supplier_cost', case when public.has_staff_permission('view_supplier_cost') then b.supplier_cost else null end,
      'gross_profit', case when public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) else null end,
      'currency', b.currency,
      'priority', b.priority,
      'staff_notes', b.staff_notes,
      'customer_notes', b.customer_notes,
      'created_at', b.created_at,
      'updated_at', b.updated_at
    ),
    'customer', case when c.id is null then null else jsonb_build_object(
      'id', c.id,
      'full_name', c.full_name,
      'email', c.email,
      'phone', c.phone,
      'whatsapp', c.whatsapp,
      'source', c.source
    ) end,
    'corporate', case when ca.id is null then null else jsonb_build_object(
      'id', ca.id,
      'company_name', ca.company_name,
      'billing_email', ca.billing_email,
      'accounts_email', ca.accounts_email,
      'payment_terms', ca.payment_terms,
      'lpo_required', ca.lpo_required,
      'credit_allowed', ca.credit_allowed,
      'monthly_billing', ca.monthly_billing,
      'trade_license_no', ca.trade_license_no,
      'trn', ca.trn,
      'phone', ca.phone,
      'status', ca.status
    ) end,
    'corporate_contact', case when cc.id is null then null else jsonb_build_object(
      'id', cc.id,
      'full_name', cc.full_name,
      'job_title', cc.job_title,
      'email', cc.email,
      'phone', cc.phone,
      'whatsapp', cc.whatsapp,
      'is_authorized_contact', cc.is_authorized_contact,
      'is_accounts_contact', cc.is_accounts_contact
    ) end,
    'passengers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bp.id,
        'passenger_name', bp.passenger_name,
        'passenger_type', bp.passenger_type,
        'nationality', bp.nationality,
        'date_of_birth', bp.date_of_birth,
        'passport_number', bp.passport_number,
        'passport_expiry', bp.passport_expiry,
        'notes', bp.notes,
        'created_at', bp.created_at,
        'updated_at', bp.updated_at
      ) order by bp.created_at asc)
      from public.booking_passengers bp
      where bp.booking_id = b.id
    ), '[]'::jsonb),
    'booking_documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bd.id,
        'document_type', bd.document_type,
        'file_name', bd.file_name,
        'storage_path', bd.storage_path,
        'external_reference', bd.external_reference,
        'visible_to_customer', bd.visible_to_customer,
        'created_at', bd.created_at
      ) order by bd.created_at desc)
      from public.booking_documents bd
      where bd.booking_id = b.id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'payment_reference', p.payment_reference,
        'amount', p.amount,
        'currency', p.currency,
        'method', p.method,
        'status', p.status,
        'received_at', p.received_at,
        'notes', p.notes,
        'proof_storage_path', p.proof_storage_path,
        'proof_file_name', p.proof_file_name,
        'proof_uploaded_at', p.proof_uploaded_at,
        'created_at', p.created_at
      ) order by p.created_at desc)
      from public.payments p
      where p.booking_id = b.id
        and public.has_staff_permission('view_payments')
    ), '[]'::jsonb),
    'supplier_payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sp.id,
        'supplier_name', sp.supplier_name,
        'supplier_reference', sp.supplier_reference,
        'amount_payable', sp.amount_payable,
        'amount_paid', sp.amount_paid,
        'currency', sp.currency,
        'status', sp.status,
        'due_date', sp.due_date,
        'paid_at', sp.paid_at,
        'notes', sp.notes,
        'supplier_invoice_path', sp.supplier_invoice_path,
        'supplier_invoice_file_name', sp.supplier_invoice_file_name,
        'supplier_invoice_uploaded_at', sp.supplier_invoice_uploaded_at,
        'sharepoint_invoice_url', sp.sharepoint_invoice_url,
        'created_at', sp.created_at
      ) order by sp.created_at desc)
      from public.supplier_payments sp
      where sp.booking_id = b.id
        and (public.has_staff_permission('view_supplier_cost') or public.has_staff_permission('view_payments'))
    ), '[]'::jsonb),
    'can_view_payments', public.has_staff_permission('view_payments'),
    'can_edit_payments', public.has_staff_permission('edit_payments'),
    'can_view_profit', public.has_staff_permission('view_profit'),
    'can_edit_bookings', public.has_staff_permission('edit_bookings'),
    'can_edit_documents', public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'),
    'can_edit_corporates', public.has_staff_permission('edit_corporates') or public.has_staff_permission('edit_bookings')
  )
  from public.bookings b
  left join public.customers c on c.id = b.customer_id
  left join public.corporate_accounts ca on ca.id = b.corporate_account_id
  left join public.corporate_contacts cc on cc.id = b.corporate_contact_id
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    )
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- get_staff_management_profiles()
CREATE OR REPLACE FUNCTION public.get_staff_management_profiles()
 RETURNS TABLE(user_id uuid, email text, role staff_role, full_name text, department text, job_title text, phone text, notes text, active boolean, hold_until timestamp with time zone, hold_reason text, created_at timestamp with time zone, updated_at timestamp with time zone, permissions jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can view staff management profiles';
  end if;

  return query
    select
      sr.user_id,
      au.email::text,
      sr.role,
      coalesce(sp.full_name, au.email::text),
      sp.department,
      sp.job_title,
      sp.phone,
      sp.notes,
      coalesce(sp.active, true),
      sp.hold_until,
      sp.hold_reason,
      coalesce(sp.created_at, sr.created_at),
      coalesce(sp.updated_at, sr.created_at),
      jsonb_build_object(
        'view_enquiries', coalesce(p.view_enquiries, false),
        'edit_enquiries', coalesce(p.edit_enquiries, false),
        'view_customers', coalesce(p.view_customers, false),
        'edit_customers', coalesce(p.edit_customers, false),
        'view_corporates', coalesce(p.view_corporates, false),
        'edit_corporates', coalesce(p.edit_corporates, false),
        'create_bookings', coalesce(p.create_bookings, false),
        'edit_bookings', coalesce(p.edit_bookings, false),
        'view_payments', coalesce(p.view_payments, false),
        'edit_payments', coalesce(p.edit_payments, false),
        'view_supplier_cost', coalesce(p.view_supplier_cost, false),
        'view_profit', coalesce(p.view_profit, false),
        'generate_documents', coalesce(p.generate_documents, false),
        'manage_portals', coalesce(p.manage_portals, false),
        'manage_templates', coalesce(p.manage_templates, false),
        'view_reports', coalesce(p.view_reports, false),
        'export_reports', coalesce(p.export_reports, false),
        'approve_refunds', coalesce(p.approve_refunds, false),
        'approve_discounts', coalesce(p.approve_discounts, false),
        'manage_staff', coalesce(p.manage_staff, false),
        'view_activity', coalesce(p.view_activity, false),
        'manage_settings', coalesce(p.manage_settings, false)
      )
    from public.staff_roles sr
    join auth.users au on au.id = sr.user_id
    left join public.staff_profiles sp on sp.user_id = sr.user_id and sp.deleted_at is null
    left join public.staff_permissions p on p.user_id = sr.user_id
    order by coalesce(sp.active, true) desc, coalesce(sp.full_name, au.email::text);
end;
$function$
;

-- grant_staff_by_email(target_email text, target_role staff_role)
CREATE OR REPLACE FUNCTION public.grant_staff_by_email(target_email text, target_role staff_role DEFAULT 'staff'::staff_role)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can grant staff access';
  end if;
  select id into target_id from auth.users where lower(email) = lower(trim(target_email)) limit 1;
  if target_id is null then
    return 'not_found';
  end if;
  insert into public.staff_roles (user_id, role)
  values (target_id, target_role)
  on conflict (user_id) do update set role = excluded.role;
  return 'granted';
end;
$function$
;

-- has_staff_permission(permission_name text)
CREATE OR REPLACE FUNCTION public.has_staff_permission(permission_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  allowed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if public.is_admin() then
    return true;
  end if;
  if not public.is_staff() then
    return false;
  end if;

  case permission_name
    when 'view_enquiries' then select sp.view_enquiries into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_enquiries' then select sp.edit_enquiries into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_customers' then select sp.view_customers into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_customers' then select sp.edit_customers into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_corporates' then select sp.view_corporates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_corporates' then select sp.edit_corporates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'create_bookings' then select sp.create_bookings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_bookings' then select sp.edit_bookings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_payments' then select sp.view_payments into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_payments' then select sp.edit_payments into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_supplier_cost' then select sp.view_supplier_cost into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_profit' then select sp.view_profit into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'generate_documents' then select sp.generate_documents into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_portals' then select sp.manage_portals into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_templates' then select sp.manage_templates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_reports' then select sp.view_reports into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'export_reports' then select sp.export_reports into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'approve_refunds' then select sp.approve_refunds into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'approve_discounts' then select sp.approve_discounts into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_staff' then select sp.manage_staff into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_activity' then select sp.view_activity into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_settings' then select sp.manage_settings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    else allowed := false;
  end case;

  return coalesce(allowed, false);
end;
$function$
;

-- hold_staff(target_user_id uuid, hold_until timestamp with time zone, reason text)
CREATE OR REPLACE FUNCTION public.hold_staff(target_user_id uuid, hold_until timestamp with time zone, reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can hold staff access';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'You cannot hold your own staff account';
  end if;
  if hold_until is null or hold_until <= now() then
    raise exception 'Hold-until time must be in the future';
  end if;
  if public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  insert into public.staff_profiles (user_id, full_name, active, hold_until, hold_reason, created_by)
  select
    target_user_id,
    coalesce(nullif(trim(au.raw_user_meta_data->>'full_name'), ''), au.email::text),
    true,
    $2,
    nullif(trim(coalesce(reason, 'Temporary hold')), ''),
    auth.uid()
  from auth.users au
  where au.id = target_user_id
  on conflict (user_id) do update set
    active = true,
    hold_until = excluded.hold_until,
    hold_reason = excluded.hold_reason,
    deleted_at = null,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.held', 'user', target_user_id, jsonb_build_object('hold_until', hold_until, 'reason', reason));

  return 'held';
end;
$function$
;

-- is_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select auth.uid() is not null
    and coalesce(guarded.value, false)
  from (

  select exists (
    select 1
    from public.staff_roles sr
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    where sr.user_id = auth.uid()
      and sr.role in ('owner', 'admin')
      and coalesce(sp.active, true) = true
      and coalesce(sp.deleted_at is null, true)
      and (sp.hold_until is null or sp.hold_until <= now())
  )
  ) as guarded(value);
$function$
;

-- is_corporate_portal_member(p_corporate_account_id uuid)
CREATE OR REPLACE FUNCTION public.is_corporate_portal_member(p_corporate_account_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select auth.uid() is not null
    and coalesce(guarded.value, false)
  from (

  select exists (
    select 1
    from public.corporate_portal_members cpm
    join public.corporate_accounts ca on ca.id = cpm.corporate_account_id
    where cpm.user_id = (select auth.uid())
      and cpm.corporate_account_id = p_corporate_account_id
      and cpm.status = 'active'
      and ca.archived_at is null
      and ca.status in ('active', 'approved', 'customer', 'prospect')
  )
  ) as guarded(value);
$function$
;

-- is_staff()
CREATE OR REPLACE FUNCTION public.is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select auth.uid() is not null
    and coalesce(guarded.value, false)
  from (

  select exists (
    select 1
    from public.staff_roles sr
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    where sr.user_id = auth.uid()
      and sr.role in ('owner', 'admin', 'staff', 'support')
      and coalesce(sp.active, true) = true
      and coalesce(sp.deleted_at is null, true)
      and (sp.hold_until is null or sp.hold_until <= now())
  )
  ) as guarded(value);
$function$
;

-- list_audit_events(limit_count integer)
CREATE OR REPLACE FUNCTION public.list_audit_events(limit_count integer DEFAULT 200)
 RETURNS TABLE(id uuid, event_type text, entity_type text, entity_id uuid, actor_email text, metadata jsonb, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can view the activity log';
  end if;
  return query
    select ae.id, ae.event_type, ae.entity_type, ae.entity_id,
           u.email::text, ae.metadata, ae.created_at
    from public.audit_events ae
    left join auth.users u on u.id = ae.actor_user_id
    order by ae.created_at desc
    limit limit_count;
end;
$function$
;

-- list_b2b_portals()
CREATE OR REPLACE FUNCTION public.list_b2b_portals()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bp.id,
    'portal_name', bp.portal_name,
    'website_url', bp.website_url,
    'service_scope', bp.service_scope,
    'username_hint', bp.username_hint,
    'password_location', bp.password_location,
    'owner_notes', bp.owner_notes,
    'status', bp.status,
    'created_at', bp.created_at,
    'updated_at', bp.updated_at
  ) order by case when bp.status = 'active' then 0 else 1 end, bp.portal_name), '[]'::jsonb)
  from public.b2b_portals bp
  where public.is_staff()
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_corporate_accounts()
CREATE OR REPLACE FUNCTION public.list_corporate_accounts()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ca.id,
    'company_name', ca.company_name,
    'trade_license_no', ca.trade_license_no,
    'trn', ca.trn,
    'billing_email', ca.billing_email,
    'accounts_email', ca.accounts_email,
    'phone', ca.phone,
    'address', ca.address,
    'payment_terms', ca.payment_terms,
    'credit_allowed', ca.credit_allowed,
    'monthly_billing', ca.monthly_billing,
    'lpo_required', ca.lpo_required,
    'status', ca.status,
    'notes', ca.notes,
    'created_at', ca.created_at,
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cc.id,
        'full_name', cc.full_name,
        'job_title', cc.job_title,
        'email', cc.email,
        'phone', cc.phone,
        'whatsapp', cc.whatsapp,
        'is_authorized_contact', cc.is_authorized_contact,
        'is_accounts_contact', cc.is_accounts_contact,
        'active', cc.active
      ) order by cc.created_at asc)
      from public.corporate_contacts cc
      where cc.corporate_account_id = ca.id and cc.active = true
    ), '[]'::jsonb),
    'booking_count', (
      select count(*) from public.bookings b where b.corporate_account_id = ca.id and b.archived_at is null
    ),
    'booking_value', (
      select coalesce(sum(coalesce(b.selling_price, b.amount, 0)), 0)
      from public.bookings b
      where b.corporate_account_id = ca.id and b.archived_at is null
    )
  ) order by ca.company_name), '[]'::jsonb)
  from public.corporate_accounts ca
  where ca.archived_at is null
    and (public.has_staff_permission('view_corporates') or public.has_staff_permission('edit_corporates') or public.has_staff_permission('manage_staff'))
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_dashboard_booking_tasks(limit_count integer)
CREATE OR REPLACE FUNCTION public.list_dashboard_booking_tasks(limit_count integer DEFAULT 80)
 RETURNS TABLE(id uuid, title text, task_type text, entity_id uuid, booking_reference text, booking_title text, service_type booking_service_type, booking_kind text, assigned_to uuid, assigned_to_name text, due_at timestamp with time zone, status text, priority text, notes text, created_at timestamp with time zone, due_bucket text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select
    t.id,
    t.title,
    t.task_type,
    t.entity_id,
    b.booking_reference,
    b.title as booking_title,
    b.service_type,
    b.booking_kind,
    t.assigned_to,
    sp.full_name as assigned_to_name,
    t.due_at,
    t.status,
    t.priority,
    t.notes,
    t.created_at,
    case
      when t.due_at is null then 'no_due_date'
      when t.due_at < now() then 'overdue'
      when t.due_at < date_trunc('day', now()) + interval '1 day' then 'today'
      when t.due_at < date_trunc('day', now()) + interval '8 days' then 'next_7_days'
      else 'later'
    end as due_bucket
  from public.tasks_reminders t
  join public.bookings b on b.id = t.entity_id
  left join public.staff_profiles sp on sp.user_id = t.assigned_to
  where t.entity_type = 'booking'
    and t.status <> 'completed'
    and b.archived_at is null
    and (
      public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('create_bookings')
      or public.has_staff_permission('view_reports')
      or t.assigned_to = auth.uid()
    )
  order by
    case
      when t.due_at is not null and t.due_at < now() then 0
      when t.due_at is not null and t.due_at < date_trunc('day', now()) + interval '1 day' then 1
      when t.due_at is null then 3
      else 2
    end,
    t.due_at nulls last,
    case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
    t.created_at desc
  limit greatest(1, least(limit_count, 200))
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_my_corporate_bookings(p_corporate_account_id uuid, p_limit integer)
CREATE OR REPLACE FUNCTION public.list_my_corporate_bookings(p_corporate_account_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id,
    'booking_reference', b.booking_reference,
    'title', b.title,
    'service_type', b.service_type,
    'route_or_destination', b.route_or_destination,
    'travel_start', b.travel_start,
    'travel_end', b.travel_end,
    'status', b.status,
    'payment_status', b.payment_status,
    'document_status', b.document_status,
    'amount', case when cpm.can_view_finance then coalesce(b.selling_price, b.amount) else null end,
    'currency', b.currency,
    'created_at', b.created_at,
    'updated_at', b.updated_at
  ) order by b.created_at desc), '[]'::jsonb)
  from public.bookings b
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where b.archived_at is null
    and b.booking_kind = 'corporate'
    and (p_corporate_account_id is null or b.corporate_account_id = p_corporate_account_id)
  limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_operations_bookings(limit_count integer)
CREATE OR REPLACE FUNCTION public.list_operations_bookings(limit_count integer DEFAULT 200)
 RETURNS TABLE(id uuid, booking_reference text, enquiry_id uuid, customer_id uuid, corporate_account_id uuid, corporate_contact_id uuid, corporate_company_name text, corporate_contact_name text, booking_kind text, service_type booking_service_type, title text, route_or_destination text, travel_start date, travel_end date, status booking_status, payment_status text, document_status text, supplier_name text, supplier_cost numeric, selling_price numeric, gross_profit numeric, currency text, priority text, follow_up_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select
    b.id,
    b.booking_reference,
    b.enquiry_id,
    b.customer_id,
    b.corporate_account_id,
    b.corporate_contact_id,
    ca.company_name as corporate_company_name,
    cc.full_name as corporate_contact_name,
    b.booking_kind,
    b.service_type,
    b.title,
    b.route_or_destination,
    b.travel_start,
    b.travel_end,
    b.status,
    b.payment_status,
    b.document_status,
    b.supplier_name,
    case when public.has_staff_permission('view_supplier_cost') then b.supplier_cost else null end as supplier_cost,
    case when public.has_staff_permission('view_payments') or public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount) else null end as selling_price,
    case when public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) else null end as gross_profit,
    b.currency,
    b.priority,
    b.follow_up_at,
    b.created_at,
    b.updated_at
  from public.bookings b
  left join public.corporate_accounts ca on ca.id = b.corporate_account_id
  left join public.corporate_contacts cc on cc.id = b.corporate_contact_id
  where b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    )
  order by b.created_at desc
  limit greatest(1, least(limit_count, 500))
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_operations_payments(limit_count integer)
CREATE OR REPLACE FUNCTION public.list_operations_payments(limit_count integer DEFAULT 200)
 RETURNS TABLE(id uuid, booking_id uuid, enquiry_id uuid, customer_id uuid, corporate_account_id uuid, booking_reference text, booking_title text, customer_name text, corporate_company_name text, service_type text, payment_reference text, payment_direction text, amount numeric, currency text, method text, status text, payment_link text, has_proof boolean, proof_file_name text, proof_uploaded_at timestamp with time zone, receipt_document_id uuid, refund_amount numeric, refund_reason text, refund_method text, refund_reference text, refund_requested_at timestamp with time zone, refund_approved_at timestamp with time zone, refund_completed_at timestamp with time zone, received_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select
    p.id,
    p.booking_id,
    p.enquiry_id,
    p.customer_id,
    p.corporate_account_id,
    b.booking_reference,
    b.title as booking_title,
    null::text as customer_name,
    ca.company_name as corporate_company_name,
    b.service_type::text as service_type,
    p.payment_reference,
    p.payment_direction,
    p.amount,
    p.currency,
    p.method,
    p.status,
    p.payment_link,
    (p.proof_storage_path is not null) as has_proof,
    p.proof_file_name,
    p.proof_uploaded_at,
    p.receipt_document_id,
    p.refund_amount,
    p.refund_reason,
    p.refund_method,
    p.refund_reference,
    p.refund_requested_at,
    p.refund_approved_at,
    p.refund_completed_at,
    p.received_at,
    p.created_at,
    p.updated_at
  from public.payments p
  left join public.bookings b on b.id = p.booking_id
  left join public.corporate_accounts ca on ca.id = p.corporate_account_id
  where public.has_staff_permission('view_payments')
  order by p.created_at desc
  limit greatest(1, least(limit_count, 500))
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- list_staff()
CREATE OR REPLACE FUNCTION public.list_staff()
 RETURNS TABLE(user_id uuid, email text, role staff_role, full_name text, department text, active boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_staff() then
    raise exception 'Only staff can view the staff list';
  end if;
  return query
    select sr.user_id, u.email::text, sr.role,
           coalesce(sp.full_name, u.email::text), sp.department,
           coalesce(sp.active, true), sr.created_at
    from public.staff_roles sr
    join auth.users u on u.id = sr.user_id
    left join public.staff_profiles sp on sp.user_id = sr.user_id
    order by sr.created_at asc;
end;
$function$
;

-- reactivate_staff(target_user_id uuid)
CREATE OR REPLACE FUNCTION public.reactivate_staff(target_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can reactivate staff access';
  end if;

  insert into public.staff_profiles (user_id, full_name, active, hold_until, hold_reason, created_by)
  select
    target_user_id,
    coalesce(nullif(trim(au.raw_user_meta_data->>'full_name'), ''), au.email::text),
    true,
    null,
    null,
    auth.uid()
  from auth.users au
  where au.id = target_user_id
  on conflict (user_id) do update set
    active = true,
    hold_until = null,
    hold_reason = null,
    deleted_at = null,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.reactivated', 'user', target_user_id, '{}'::jsonb);

  return 'reactivated';
end;
$function$
;

-- record_customer_payment(p_booking_id uuid, p_amount numeric, p_method text, p_status text, p_currency text, p_payment_link text, p_notes text)
CREATE OR REPLACE FUNCTION public.record_customer_payment(p_booking_id uuid, p_amount numeric, p_method text, p_status text DEFAULT 'received'::text, p_currency text DEFAULT 'AED'::text, p_payment_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment_id uuid;
  v_ref text;
  v_booking_ref text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;

  if p_amount is null or p_amount < 0 then
    raise exception 'Payment amount must be positive';
  end if;

  select booking_reference into v_booking_ref from public.bookings where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  v_ref := public.next_payment_reference();

  insert into public.payments (
    booking_id,
    payment_reference,
    amount,
    currency,
    method,
    status,
    payment_link,
    notes,
    received_at,
    created_by
  ) values (
    p_booking_id,
    v_ref,
    p_amount,
    upper(coalesce(p_currency, 'AED')),
    p_method,
    p_status,
    nullif(trim(coalesce(p_payment_link, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_status = 'received' then now() else null end,
    auth.uid()
  ) returning id into v_payment_id;

  update public.bookings
  set payment_status = case
        when p_status = 'received' then 'paid'
        when p_status = 'proof_received' then 'proof_received'
        else payment_status
      end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.recorded', 'payment', v_payment_id, jsonb_build_object('booking_reference', v_booking_ref, 'payment_reference', v_ref, 'amount', p_amount, 'method', p_method, 'status', p_status));

  return v_payment_id;
end;
$function$
;

-- record_supplier_payment(p_booking_id uuid, p_supplier_name text, p_amount_payable numeric, p_amount_paid numeric, p_status text, p_currency text, p_supplier_reference text, p_due_date date, p_notes text)
CREATE OR REPLACE FUNCTION public.record_supplier_payment(p_booking_id uuid, p_supplier_name text, p_amount_payable numeric, p_amount_paid numeric DEFAULT 0, p_status text DEFAULT 'pending'::text, p_currency text DEFAULT 'AED'::text, p_supplier_reference text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_supplier_payment_id uuid;
  v_booking_ref text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;

  select booking_reference into v_booking_ref from public.bookings where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  insert into public.supplier_payments (
    booking_id,
    supplier_name,
    supplier_reference,
    amount_payable,
    amount_paid,
    currency,
    due_date,
    paid_at,
    status,
    notes,
    created_by
  ) values (
    p_booking_id,
    trim(p_supplier_name),
    nullif(trim(coalesce(p_supplier_reference, '')), ''),
    coalesce(p_amount_payable, 0),
    coalesce(p_amount_paid, 0),
    upper(coalesce(p_currency, 'AED')),
    p_due_date,
    case when p_status = 'paid' then now() else null end,
    p_status,
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
  ) returning id into v_supplier_payment_id;

  update public.bookings
  set supplier_name = trim(p_supplier_name),
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      supplier_cost = coalesce(p_amount_payable, supplier_cost),
      payment_status = case when p_status = 'paid' then 'supplier_paid' else payment_status end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'supplier_payment.recorded', 'supplier_payment', v_supplier_payment_id, jsonb_build_object('booking_reference', v_booking_ref, 'supplier_name', p_supplier_name, 'amount_payable', p_amount_payable, 'status', p_status));

  return v_supplier_payment_id;
end;
$function$
;

-- request_payment_refund(p_payment_id uuid, p_refund_amount numeric, p_reason text)
CREATE OR REPLACE FUNCTION public.request_payment_refund(p_payment_id uuid, p_refund_amount numeric DEFAULT NULL::numeric, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment public.payments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('edit_payments') or public.can_approve_refunds()) then
    raise exception 'Refund request permission required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and payment_direction = 'customer_in';

  if not found then
    raise exception 'Customer payment not found';
  end if;

  if coalesce(p_refund_amount, v_payment.amount) <= 0 then
    raise exception 'Refund amount must be greater than zero';
  end if;

  update public.payments
  set status = 'refund_pending',
      refund_amount = coalesce(p_refund_amount, v_payment.amount),
      refund_reason = nullif(trim(coalesce(p_reason, '')), ''),
      refund_requested_by = auth.uid(),
      refund_requested_at = now(),
      updated_at = now()
  where id = p_payment_id;

  if v_payment.booking_id is not null then
    update public.bookings
    set payment_status = 'refund_pending',
        updated_at = now()
    where id = v_payment.booking_id;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment.refund_requested',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_reference', v_payment.payment_reference,
      'refund_amount', coalesce(p_refund_amount, v_payment.amount),
      'currency', v_payment.currency,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );

  return p_payment_id;
end;
$function$
;

-- respond_my_corporate_quote(p_quote_id uuid, p_status text)
CREATE OR REPLACE FUNCTION public.respond_my_corporate_quote(p_quote_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_quote public.quotes%rowtype;
  v_booking public.bookings%rowtype;
  v_actor uuid := auth.uid();
  v_status public.quote_status;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
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
  where q.id = p_quote_id;

  if not found then
    raise exception 'Quote approval access denied';
  end if;

  select b.*
  into v_booking
  from public.bookings b
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = v_actor
   and cpm.status = 'active'
   and cpm.can_approve_quotes = true
  where (
      b.id = v_quote.booking_id
      or (v_quote.booking_id is null and b.enquiry_id = v_quote.enquiry_id)
    )
    and b.archived_at is null
    and b.booking_kind = 'corporate'
  limit 1;

  if not found then
    raise exception 'Quote approval access denied';
  end if;

  if v_quote.status <> 'sent' then
    raise exception 'Only sent quotes can be accepted or declined';
  end if;

  update public.quotes
  set status = v_status,
      responded_at = now()
  where id = p_quote_id
  returning * into v_quote;

  if v_status = 'accepted' then
    update public.bookings
    set status = case
          when status in ('enquiry', 'quote_sent') then 'payment_pending'::public.booking_status
          else status
        end,
        selling_price = coalesce(selling_price, v_quote.price_amount),
        currency = coalesce(nullif(currency, ''), v_quote.currency),
        updated_at = now()
    where id = v_booking.id;
  end if;

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
$function$
;

-- revoke_staff(target_user_id uuid)
CREATE OR REPLACE FUNCTION public.revoke_staff(target_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can revoke staff access';
  end if;
  if target_user_id = auth.uid() then
    return 'cannot_remove_self';
  end if;
  update public.staff_profiles set active = false where user_id = target_user_id;
  delete from public.staff_roles where user_id = target_user_id;
  return 'revoked';
end;
$function$
;

-- setup_staff_account_record(target_user_id uuid, full_name text, department text, role staff_role)
CREATE OR REPLACE FUNCTION public.setup_staff_account_record(target_user_id uuid, full_name text, department text DEFAULT NULL::text, role staff_role DEFAULT 'staff'::staff_role)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role public.staff_role;
  v_actor_rank integer;
  v_target_rank integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select sr.role into v_actor_role
  from public.staff_roles sr where sr.user_id = v_actor;

  v_actor_rank := case v_actor_role
    when 'owner' then 4 when 'admin' then 3 when 'staff' then 2 when 'support' then 1 else 0 end;
  v_target_rank := case role
    when 'owner' then 4 when 'admin' then 3 when 'staff' then 2 when 'support' then 1 else 99 end;

  if v_actor_rank < 3 then
    raise exception 'Only admins can set up staff accounts';
  end if;
  if char_length(trim(coalesce(full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;
  if role = 'owner' and v_actor_role <> 'owner' then
    raise exception 'Only an owner can grant the owner role';
  end if;
  if v_actor_role <> 'owner' and v_target_rank >= v_actor_rank then
    raise exception 'Cannot grant a role at or above your own';
  end if;

  insert into public.staff_profiles (
    user_id, full_name, department, active, created_by, deleted_at, hold_until, hold_reason
  )
  values (
    target_user_id, trim(full_name), nullif(trim(coalesce(department, '')), ''),
    true, v_actor, null, null, null
  )
  on conflict (user_id) do update
    set full_name = excluded.full_name,
        department = excluded.department,
        active = true,
        deleted_at = null,
        hold_until = null,
        hold_reason = null,
        updated_at = now();

  insert into public.staff_roles (user_id, role)
  values (target_user_id, role)
  on conflict (user_id) do update set role = excluded.role;

  insert into public.staff_permissions (user_id)
  values (target_user_id)
  on conflict (user_id) do nothing;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (v_actor, target_user_id, 'staff.created', 'user', target_user_id,
          jsonb_build_object('full_name', full_name, 'role', role, 'department', department));

  return 'created';
end;
$function$
;

-- staff_dashboard_summary()
CREATE OR REPLACE FUNCTION public.staff_dashboard_summary()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select jsonb_build_object(
    'enquiries_open', (select count(*) from public.enquiries where status <> 'closed'),
    'enquiries_today', (select count(*) from public.enquiries where created_at::date = current_date),
    'bookings_open', (select count(*) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'bookings_confirmed_unpaid', (select count(*) from public.bookings where archived_at is null and status in ('confirmed', 'ticketed', 'paid') and payment_status not in ('paid', 'received', 'payment_received', 'completed')),
    'documents_pending', (select count(*) from public.bookings where archived_at is null and document_status in ('not_started', 'pending', 'missing', 'requested')),
    'payments_pending', (select count(*) from public.payments where status in ('pending', 'proof_received')),
    'payment_proofs_received', (select count(*) from public.payments where status = 'proof_received' or proof_storage_path is not null),
    'supplier_payments_pending', (select count(*) from public.supplier_payments where status in ('pending', 'partial')),
    'refunds_pending', (select count(*) from public.payments where status in ('refund_pending', 'refund_approved')),
    'refund_value_pending', (select coalesce(sum(coalesce(refund_amount, amount)), 0) from public.payments where status in ('refund_pending', 'refund_approved')),
    'sales_value_open', (select coalesce(sum(coalesce(selling_price, amount)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'supplier_cost_open', (select coalesce(sum(coalesce(supplier_cost, 0)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'gross_profit_open', (select coalesce(sum(coalesce(selling_price, amount, 0) - coalesce(supplier_cost, 0)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'received_value_30d', (select coalesce(sum(amount), 0) from public.payments where status = 'received' and created_at >= now() - interval '30 days'),
    'net_collected_30d', (select coalesce(sum(case when status = 'received' then amount when status = 'refunded' then -coalesce(refund_amount, amount) else 0 end), 0) from public.payments where created_at >= now() - interval '30 days'),
    'tasks_due', (select count(*) from public.tasks_reminders where status = 'open' and due_at <= now()),
    'tasks_overdue', (select count(*) from public.tasks_reminders where status = 'open' and due_at < now()),
    'tasks_today', (select count(*) from public.tasks_reminders where status = 'open' and due_at::date = current_date),
    'documents_generated', (select count(*) from public.documents),
    'recent_activity', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (select event_type, entity_type, entity_id, metadata, created_at from public.audit_events order by created_at desc limit 10) x)
  )
  where public.is_staff()
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- staff_monitoring_summary(days_back integer)
CREATE OR REPLACE FUNCTION public.staff_monitoring_summary(days_back integer DEFAULT 30)
 RETURNS TABLE(user_id uuid, full_name text, email text, role staff_role, active boolean, bookings_created integer, tasks_open integer, tasks_completed integer, payments_recorded integer, documents_recorded integer, activity_events integer, last_activity_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select guarded.*
  from (

  select
    sp.user_id,
    sp.full_name,
    au.email,
    coalesce(sr.role, 'staff'::public.staff_role) as role,
    sp.active,
    count(distinct b.id)::integer as bookings_created,
    count(distinct t_open.id)::integer as tasks_open,
    count(distinct t_done.id)::integer as tasks_completed,
    count(distinct p.id)::integer as payments_recorded,
    count(distinct bd.id)::integer as documents_recorded,
    count(distinct ae.id)::integer as activity_events,
    max(ae.created_at) as last_activity_at
  from public.staff_profiles sp
  left join auth.users au on au.id = sp.user_id
  left join public.staff_roles sr on sr.user_id = sp.user_id
  left join public.bookings b on b.created_by = sp.user_id
    and b.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.tasks_reminders t_open on t_open.assigned_to = sp.user_id
    and t_open.status <> 'completed'
  left join public.tasks_reminders t_done on t_done.assigned_to = sp.user_id
    and t_done.status = 'completed'
    and t_done.completed_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.payments p on p.created_by = sp.user_id
    and p.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.booking_documents bd on bd.created_by = sp.user_id
    and bd.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.audit_events ae on ae.actor_user_id = sp.user_id
    and ae.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  where public.is_admin()
  group by sp.user_id, sp.full_name, au.email, sr.role, sp.active
  order by sp.active desc, activity_events desc, sp.full_name
  ) as guarded
  where auth.uid() is not null;
$function$
;

-- update_operations_booking_status(p_booking_id uuid, p_status booking_status, p_payment_status text, p_document_status text, p_supplier_reference text, p_staff_notes text)
CREATE OR REPLACE FUNCTION public.update_operations_booking_status(p_booking_id uuid, p_status booking_status, p_payment_status text, p_document_status text, p_supplier_reference text DEFAULT NULL::text, p_staff_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ref text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Permission denied';
  end if;

  update public.bookings
  set status = p_status,
      payment_status = p_payment_status,
      document_status = p_document_status,
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      staff_notes = nullif(trim(coalesce(p_staff_notes, '')), ''),
      updated_at = now()
  where id = p_booking_id
  returning booking_reference into v_ref;

  if v_ref is null then
    raise exception 'Booking not found';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.status_updated', 'booking', p_booking_id, jsonb_build_object('reference', v_ref, 'status', p_status, 'payment_status', p_payment_status, 'document_status', p_document_status));
end;
$function$
;

-- update_staff_permissions(target_user_id uuid, permissions jsonb)
CREATE OR REPLACE FUNCTION public.update_staff_permissions(target_user_id uuid, permissions jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can update staff permissions';
  end if;

  insert into public.staff_permissions (
    user_id, view_enquiries, edit_enquiries, view_customers, edit_customers,
    view_corporates, edit_corporates, create_bookings, edit_bookings,
    view_payments, edit_payments, view_supplier_cost, view_profit,
    generate_documents, manage_portals, manage_templates, view_reports,
    export_reports, approve_refunds, approve_discounts, manage_staff,
    view_activity, manage_settings
  )
  values (
    target_user_id,
    coalesce((permissions->>'view_enquiries')::boolean, false),
    coalesce((permissions->>'edit_enquiries')::boolean, false),
    coalesce((permissions->>'view_customers')::boolean, false),
    coalesce((permissions->>'edit_customers')::boolean, false),
    coalesce((permissions->>'view_corporates')::boolean, false),
    coalesce((permissions->>'edit_corporates')::boolean, false),
    coalesce((permissions->>'create_bookings')::boolean, false),
    coalesce((permissions->>'edit_bookings')::boolean, false),
    coalesce((permissions->>'view_payments')::boolean, false),
    coalesce((permissions->>'edit_payments')::boolean, false),
    coalesce((permissions->>'view_supplier_cost')::boolean, false),
    coalesce((permissions->>'view_profit')::boolean, false),
    coalesce((permissions->>'generate_documents')::boolean, false),
    coalesce((permissions->>'manage_portals')::boolean, false),
    coalesce((permissions->>'manage_templates')::boolean, false),
    coalesce((permissions->>'view_reports')::boolean, false),
    coalesce((permissions->>'export_reports')::boolean, false),
    coalesce((permissions->>'approve_refunds')::boolean, false),
    coalesce((permissions->>'approve_discounts')::boolean, false),
    coalesce((permissions->>'manage_staff')::boolean, false),
    coalesce((permissions->>'view_activity')::boolean, false),
    coalesce((permissions->>'manage_settings')::boolean, false)
  )
  on conflict (user_id) do update set
    view_enquiries = excluded.view_enquiries,
    edit_enquiries = excluded.edit_enquiries,
    view_customers = excluded.view_customers,
    edit_customers = excluded.edit_customers,
    view_corporates = excluded.view_corporates,
    edit_corporates = excluded.edit_corporates,
    create_bookings = excluded.create_bookings,
    edit_bookings = excluded.edit_bookings,
    view_payments = excluded.view_payments,
    edit_payments = excluded.edit_payments,
    view_supplier_cost = excluded.view_supplier_cost,
    view_profit = excluded.view_profit,
    generate_documents = excluded.generate_documents,
    manage_portals = excluded.manage_portals,
    manage_templates = excluded.manage_templates,
    view_reports = excluded.view_reports,
    export_reports = excluded.export_reports,
    approve_refunds = excluded.approve_refunds,
    approve_discounts = excluded.approve_discounts,
    manage_staff = excluded.manage_staff,
    view_activity = excluded.view_activity,
    manage_settings = excluded.manage_settings,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.permissions_updated', 'user', target_user_id, permissions);

  return 'updated';
end;
$function$
;

-- update_staff_profile(target_user_id uuid, full_name text, department text, job_title text, phone text, role staff_role, active boolean, notes text, hold_until timestamp with time zone)
CREATE OR REPLACE FUNCTION public.update_staff_profile(target_user_id uuid, full_name text, department text DEFAULT NULL::text, job_title text DEFAULT NULL::text, phone text DEFAULT NULL::text, role staff_role DEFAULT 'staff'::staff_role, active boolean DEFAULT true, notes text DEFAULT NULL::text, hold_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can update staff profiles';
  end if;
  if target_user_id = auth.uid() and active = false then
    raise exception 'You cannot deactivate your own staff account';
  end if;
  if char_length(trim(coalesce(full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;
  if (role not in ('owner', 'admin')) and public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  insert into public.staff_profiles (
    user_id, full_name, department, job_title, phone, notes, active, hold_until, hold_reason, created_by, deleted_at
  )
  values (
    target_user_id, trim(full_name), nullif(trim(coalesce(department, '')), ''),
    nullif(trim(coalesce(job_title, '')), ''), nullif(trim(coalesce(phone, '')), ''),
    nullif(trim(coalesce(notes, '')), ''), active, hold_until,
    case when hold_until is null then null else nullif(trim(coalesce(notes, '')), '') end,
    auth.uid(), null
  )
  on conflict (user_id) do update set
    full_name = excluded.full_name,
    department = excluded.department,
    job_title = excluded.job_title,
    phone = excluded.phone,
    notes = excluded.notes,
    active = excluded.active,
    hold_until = excluded.hold_until,
    hold_reason = excluded.hold_reason,
    deleted_at = null,
    updated_at = now();

  insert into public.staff_roles (user_id, role)
  values (target_user_id, role)
  on conflict (user_id) do update set role = excluded.role;

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.profile_updated', 'user', target_user_id, jsonb_build_object('role', role, 'active', active, 'hold_until', hold_until));

  return 'updated';
end;
$function$
;
