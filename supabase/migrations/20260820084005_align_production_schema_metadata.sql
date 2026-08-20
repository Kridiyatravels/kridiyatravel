-- Exact pg-delta alignment from the corrected disposable rebuild to the
-- 2026-08-20 production public schema. This captures function source text and
-- ACL/default-privilege state that existed live but was absent from the ledger.
-- Production already has this state; deployment must be ledger-repair-only.

set local check_function_bodies = off;

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "service_role";

revoke all on function "public"."list_staff_for_login"() from "anon";

revoke all on function "public"."list_staff_for_login"() from "authenticated";

revoke all on sequence "public"."booking_reference_seq" from "anon";

revoke all on sequence "public"."booking_reference_seq" from "authenticated";

revoke all on sequence "public"."booking_reference_seq" from "service_role";

revoke all on sequence "public"."doc_cancellation_seq" from "anon";

revoke all on sequence "public"."doc_cancellation_seq" from "authenticated";

revoke all on sequence "public"."doc_cancellation_seq" from "service_role";

revoke all on sequence "public"."doc_eticket_seq" from "anon";

revoke all on sequence "public"."doc_eticket_seq" from "authenticated";

revoke all on sequence "public"."doc_eticket_seq" from "service_role";

revoke all on sequence "public"."doc_invoice_seq" from "anon";

revoke all on sequence "public"."doc_invoice_seq" from "authenticated";

revoke all on sequence "public"."doc_invoice_seq" from "service_role";

revoke all on sequence "public"."doc_receipt_seq" from "anon";

revoke all on sequence "public"."doc_receipt_seq" from "authenticated";

revoke all on sequence "public"."doc_receipt_seq" from "service_role";

revoke all on sequence "public"."doc_rejection_seq" from "anon";

revoke all on sequence "public"."doc_rejection_seq" from "authenticated";

revoke all on sequence "public"."doc_rejection_seq" from "service_role";

revoke all on sequence "public"."doc_statement_seq" from "anon";

revoke all on sequence "public"."doc_statement_seq" from "authenticated";

revoke all on sequence "public"."doc_statement_seq" from "service_role";

revoke all on sequence "public"."payment_reference_seq" from "anon";

revoke all on sequence "public"."payment_reference_seq" from "authenticated";

revoke all on sequence "public"."payment_reference_seq" from "service_role";

revoke all on table "public"."staff_permissions" from "anon";

create or replace function public.admit_marketing_unsubscribe (
  p_ip_hash    text,
  p_email_hash text
)
  returns boolean
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if p_ip_hash !~ '^[0-9a-f]{64}$' or p_email_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  -- Serialize requests for the same address or client so concurrent calls
  -- cannot race past the limits.
  perform pg_advisory_xact_lock(hashtextextended(p_ip_hash, 0));
  perform pg_advisory_xact_lock(hashtextextended(p_email_hash, 1));

  delete from public.marketing_unsubscribe_requests
  where created_at < now() - interval '24 hours';

  if (select count(*) from public.marketing_unsubscribe_requests
      where ip_hash = p_ip_hash
        and created_at >= now() - interval '15 minutes') >= 5 then
    return false;
  end if;

  if (select count(*) from public.marketing_unsubscribe_requests
      where email_hash = p_email_hash
        and created_at >= now() - interval '1 hour') >= 3 then
    return false;
  end if;

  insert into public.marketing_unsubscribe_requests (ip_hash, email_hash)
  values (p_ip_hash, p_email_hash);
  return true;
end;
$function$;

create or replace function public.admit_meta_conversion (
  p_ip_hash  text,
  p_event_id text
)
  returns text
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if (select count(*) from public.meta_conversion_requests
      where ip_hash = p_ip_hash and created_at >= now() - interval '15 minutes') >= 30 then
    return 'rate_limited';
  end if;
  begin
    insert into public.meta_conversion_requests (ip_hash, event_id) values (p_ip_hash, p_event_id);
  exception when unique_violation then
    return 'duplicate';
  end;
  return 'allowed';
end;
$function$;

create or replace function public.approve_corporate_application (
  p_enquiry_id         uuid,
  p_auth_user_id       uuid    default null::uuid,
  p_role               text    default 'travel_coordinator'::text,
  p_can_request        boolean default true,
  p_can_approve_quotes boolean default false,
  p_can_view_finance   boolean default false,
  p_can_view_documents boolean default true,
  p_notes              text    default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.audit_enquiry_lifecycle_change()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare changed_fields text[]:='{}'::text[];
begin
  if old.status is distinct from new.status then changed_fields:=array_append(changed_fields,'status'); end if;
  if old.pipeline_stage is distinct from new.pipeline_stage then changed_fields:=array_append(changed_fields,'pipeline_stage'); end if;
  if old.assigned_staff_id is distinct from new.assigned_staff_id then changed_fields:=array_append(changed_fields,'assigned_staff_id'); end if;
  if old.priority is distinct from new.priority then changed_fields:=array_append(changed_fields,'priority'); end if;
  if cardinality(changed_fields)=0 then return new; end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(auth.uid(),'enquiry.lifecycle_updated','enquiry',new.id,
    jsonb_build_object('reference',new.reference,'changed_fields',changed_fields,
      'before',jsonb_build_object('status',old.status,'pipeline_stage',old.pipeline_stage,'assigned_staff_id',old.assigned_staff_id,'priority',old.priority),
      'after',jsonb_build_object('status',new.status,'pipeline_stage',new.pipeline_stage,'assigned_staff_id',new.assigned_staff_id,'priority',new.priority)));
  return new;
end;
$function$;

create or replace function public.claim_my_enquiry (
  p_reference text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public', 'auth', 'pg_temp'
  AS $function$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_confirmed_at timestamptz;
  v_enquiry_id uuid;
  v_owner_id uuid;
  v_reference text := upper(btrim(coalesce(p_reference, '')));
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if v_reference !~ '^KD-[A-Z]{3}-[A-Z0-9]{8}$' then raise exception 'Enquiry could not be verified'; end if;
  select lower(email), email_confirmed_at into v_email, v_confirmed_at from auth.users where id = v_user_id;
  if v_email is null or v_confirmed_at is null then raise exception 'A verified email is required'; end if;
  select id, user_id into v_enquiry_id, v_owner_id from public.enquiries
   where upper(reference) = v_reference and lower(btrim(email)) = v_email for update;
  if v_enquiry_id is null or (v_owner_id is not null and v_owner_id <> v_user_id) then raise exception 'Enquiry could not be verified'; end if;
  if v_owner_id is null then
    update public.enquiries set user_id = v_user_id where id = v_enquiry_id;
    insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
    values(v_user_id,'enquiry.claimed_by_verified_email','enquiry',v_enquiry_id,jsonb_build_object('reference',v_reference));
  end if;
  return v_enquiry_id;
end $function$;

create or replace function public.create_my_corporate_request (
  p_corporate_account_id uuid,
  p_title                text,
  p_service_type         public.booking_service_type,
  p_route_or_destination text                        default null::text,
  p_travel_start         date                        default null::date,
  p_travel_end           date                        default null::date,
  p_customer_notes       text                        default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_booking_id uuid;
  v_reference text;
  v_contact_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select corporate_contact_id
  into v_contact_id
  from public.corporate_portal_members
  where user_id = auth.uid()
    and corporate_account_id = p_corporate_account_id
    and status = 'active'
    and can_request = true;

  if not found then
    raise exception 'Corporate request access denied';
  end if;

  v_reference := public.next_booking_reference();

  insert into public.bookings (
    user_id,
    booking_reference,
    service_type,
    title,
    booking_kind,
    corporate_account_id,
    corporate_contact_id,
    route_or_destination,
    travel_start,
    travel_end,
    customer_notes,
    source,
    status,
    payment_status,
    created_by
  ) values (
    auth.uid(),
    v_reference,
    p_service_type,
    trim(p_title),
    'corporate',
    p_corporate_account_id,
    v_contact_id,
    nullif(trim(coalesce(p_route_or_destination, '')), ''),
    p_travel_start,
    p_travel_end,
    nullif(trim(coalesce(p_customer_notes, '')), ''),
    'corporate_portal',
    'enquiry',
    'not_requested',
    auth.uid()
  ) returning id into v_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'corporate_portal.request_created',
    'booking',
    v_booking_id,
    jsonb_build_object(
      'reference', v_reference,
      'corporate_account_id', p_corporate_account_id,
      'service_type', p_service_type
    )
  );

  return v_booking_id;
end;
$function$;

create or replace function public.enforce_customer_payment_currency()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare expected_currency text;
begin
  new.currency := upper(new.currency);
  if new.booking_id is null then return new; end if;
  select upper(b.currency) into expected_currency from public.bookings b where b.id = new.booking_id;
  if expected_currency is null then raise exception 'Linked booking not found'; end if;
  if new.currency <> expected_currency then
    raise exception 'Customer payment currency must match booking currency (%)', expected_currency;
  end if;
  return new;
end;
$function$;

create or replace function public.enforce_supplier_payment_currency()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare expected_currency text;
begin
  new.currency := upper(new.currency);
  select upper(coalesce(b.supplier_currency, b.currency))
  into expected_currency from public.bookings b where b.id = new.booking_id;
  if expected_currency is null then raise exception 'Linked booking not found'; end if;
  if new.currency <> expected_currency then
    raise exception 'Supplier payment currency must match supplier currency (%)', expected_currency;
  end if;
  return new;
end;
$function$;

create or replace function public.find_company_duplicate_candidates (
  p_company_name       text default null::text,
  p_trade_license_no   text default null::text,
  p_trn                text default null::text,
  p_exclude_company_id uuid default null::uuid
)
  returns table (
    company_id           uuid,
    company_name         text,
    trade_license_no     text,
    trn                  text,
    status               text,
    match_reasons        text[],
    linked_booking_count bigint,
    portal_member_count  bigint,
    created_at           timestamp with time zone
  )
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare normalized_name text:=public.normalize_company_name(p_company_name);
 normalized_license text:=public.normalize_company_registration(p_trade_license_no);
 normalized_trn text:=public.normalize_company_registration(p_trn);
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_staff_permission('view_corporates') then raise exception 'Permission denied'; end if;
 if normalized_name is null and normalized_license is null and normalized_trn is null then return; end if;
 return query
 select ca.id,ca.company_name,ca.trade_license_no,ca.trn,ca.status,
  array_remove(array[
   case when normalized_name is not null and public.normalize_company_name(ca.company_name)=normalized_name then 'company_name' end,
   case when normalized_license is not null and public.normalize_company_registration(ca.trade_license_no)=normalized_license then 'trade_license_no' end,
   case when normalized_trn is not null and public.normalize_company_registration(ca.trn)=normalized_trn then 'trn' end
  ],null)::text[],counts.booking_count,counts.member_count,ca.created_at
 from public.corporate_accounts ca
 cross join lateral(select
  (select count(*) from public.bookings b where b.corporate_account_id=ca.id) booking_count,
  (select count(*) from public.corporate_portal_members cpm where cpm.corporate_account_id=ca.id) member_count) counts
 where ca.archived_at is null and (p_exclude_company_id is null or ca.id<>p_exclude_company_id)
 and ((normalized_name is not null and public.normalize_company_name(ca.company_name)=normalized_name)
  or (normalized_license is not null and public.normalize_company_registration(ca.trade_license_no)=normalized_license)
  or (normalized_trn is not null and public.normalize_company_registration(ca.trn)=normalized_trn))
 order by counts.booking_count desc,counts.member_count desc,ca.created_at asc;
end;
$function$;

create or replace function public.find_customer_duplicate_candidates (
  p_email               text default null::text,
  p_phone               text default null::text,
  p_exclude_customer_id uuid default null::uuid
)
  returns table (
    customer_id          uuid,
    full_name            text,
    email                text,
    phone                text,
    whatsapp             text,
    match_reasons        text[],
    linked_booking_count bigint,
    created_at           timestamp with time zone
  )
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare normalized_email text:=public.normalize_customer_email(p_email);
 normalized_phone text:=public.normalize_customer_phone(p_phone);
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_staff_permission('view_customers') then raise exception 'Permission denied'; end if;
 if normalized_email is null and normalized_phone is null then return; end if;
 return query
 select c.id,c.full_name,c.email,c.phone,c.whatsapp,
  array_remove(array[
   case when normalized_email is not null and public.normalize_customer_email(c.email)=normalized_email then 'email' end,
   case when normalized_phone is not null and public.normalize_customer_phone(coalesce(c.phone,c.whatsapp))=normalized_phone then 'phone' end
  ],null)::text[],
  (select count(*) from public.bookings b where b.customer_id=c.id),c.created_at
 from public.customers c
 where c.archived_at is null
  and (p_exclude_customer_id is null or c.id<>p_exclude_customer_id)
  and ((normalized_email is not null and public.normalize_customer_email(c.email)=normalized_email)
    or (normalized_phone is not null and public.normalize_customer_phone(coalesce(c.phone,c.whatsapp))=normalized_phone))
 order by (select count(*) from public.bookings b where b.customer_id=c.id) desc,c.created_at asc;
end;
$function$;

create or replace function public.get_booking_quote_context (
  p_booking_id uuid
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.get_my_corporate_booking_detail (
  p_booking_id uuid
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.get_my_corporate_portal()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.get_my_payment_receipt (
  p_payment_id uuid
)
  returns table (
    receipt_number       text,
    payment_reference    text,
    booking_reference    text,
    booking_title        text,
    route_or_destination text,
    amount               numeric,
    currency             text,
    payment_method       text,
    received_at          timestamp with time zone,
    issued_at            timestamp with time zone
  )
  language sql
  stable
  security definer
  set search_path to 'public', 'pg_temp'
  AS $function$
 select d.document_number,p.payment_reference,b.booking_reference,b.title,b.route_or_destination,p.amount,p.currency,p.method,coalesce(p.received_at,p.created_at),d.created_at
 from public.payments p join public.bookings b on b.id=p.booking_id join public.documents d on d.id=p.receipt_document_id and d.document_type='receipt'
 where p.id=p_payment_id and auth.uid() is not null and b.user_id=auth.uid() and p.payment_direction='customer_in' and p.status='received' limit 1
$function$;

create or replace function public.is_corporate_portal_member (
  p_corporate_account_id uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.link_my_enquiry_traveller (
  p_enquiry_id   uuid,
  p_traveller_id uuid
)
  returns boolean
  language plpgsql
  security definer
  set search_path to 'public', 'pg_temp'
  AS $function$
declare v_user_id uuid:=auth.uid(); v_reference text;
begin
 if v_user_id is null then raise exception 'Authentication required'; end if;
 if p_enquiry_id is null or p_traveller_id is null then raise exception 'Enquiry and traveller are required'; end if;
 select e.reference into v_reference from public.enquiries e where e.id=p_enquiry_id and e.user_id=v_user_id for update;
 if v_reference is null then raise exception 'Enquiry not found for this account'; end if;
 if not exists(select 1 from public.travellers t join public.customers c on c.id=t.customer_id where t.id=p_traveller_id and t.archived_at is null and t.active=true and c.auth_user_id=v_user_id and c.archived_at is null) then raise exception 'Traveller not found for this account'; end if;
 update public.enquiries set primary_traveller_id=p_traveller_id where id=p_enquiry_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user_id,'enquiry.primary_traveller_linked','enquiry',p_enquiry_id,jsonb_build_object('reference',v_reference,'traveller_id',p_traveller_id));
 return true;
end $function$;

create or replace function public.list_enquiry_primary_travellers()
  returns table (
    enquiry_id      uuid,
    traveller_id    uuid,
    full_name       text,
    date_of_birth   date,
    nationality     text,
    passport_expiry date
  )
  language sql
  stable
  security definer
  set search_path to 'public', 'pg_temp'
  AS $function$
 select e.id,t.id,t.full_name,t.date_of_birth,t.nationality,t.passport_expiry
 from public.enquiries e join public.travellers t on t.id=e.primary_traveller_id
 where auth.uid() is not null and public.is_staff()
$function$;

create or replace function public.list_my_corporate_bookings (
  p_corporate_account_id uuid    default null::uuid,
  p_limit                integer default 100
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public'
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
$function$;

create or replace function public.manage_corporate_portal_member (
  p_corporate_account_id uuid,
  p_user_id              uuid,
  p_corporate_contact_id uuid    default null::uuid,
  p_role                 text    default 'requester'::text,
  p_status               text    default 'active'::text,
  p_can_request          boolean default true,
  p_can_approve_quotes   boolean default false,
  p_can_view_finance     boolean default false,
  p_can_view_documents   boolean default true,
  p_notes                text    default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  if not exists (
    select 1 from public.corporate_accounts
    where id = p_corporate_account_id and archived_at is null
  ) then
    raise exception 'Corporate account not found';
  end if;

  if p_corporate_contact_id is not null and not exists (
    select 1 from public.corporate_contacts
    where id = p_corporate_contact_id
      and corporate_account_id = p_corporate_account_id
      and active = true
  ) then
    raise exception 'Corporate contact does not belong to selected company';
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
    p_corporate_account_id,
    p_corporate_contact_id,
    p_user_id,
    coalesce(nullif(trim(coalesce(p_role, '')), ''), 'requester'),
    coalesce(nullif(trim(coalesce(p_status, '')), ''), 'active'),
    coalesce(p_can_request, true),
    coalesce(p_can_approve_quotes, false),
    coalesce(p_can_view_finance, false),
    coalesce(p_can_view_documents, true),
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
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
  returning id into v_id;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    p_user_id,
    'corporate_portal.member_upserted',
    'corporate_account',
    p_corporate_account_id,
    jsonb_build_object('member_id', v_id, 'role', p_role, 'status', p_status)
  );

  return v_id;
end;
$function$;

create or replace function public.merge_customer_records_internal_20260815 (
  p_source_customer_id         uuid,
  p_target_customer_id         uuid,
  p_source_expected_updated_at timestamp with time zone,
  p_target_expected_updated_at timestamp with time zone,
  p_reason                     text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare source_customer public.customers%rowtype; target_customer public.customers%rowtype;
 moved_bookings integer; moved_passengers integer; moved_payments integer; moved_corporate_contacts integer;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_staff_permission('edit_customers') then raise exception 'Permission denied'; end if;
 if p_source_customer_id=p_target_customer_id then raise exception 'Source and target customers must be different'; end if;
 if char_length(trim(coalesce(p_reason,'')))<10 then raise exception 'A merge reason of at least 10 characters is required'; end if;
 if p_source_expected_updated_at is null or p_target_expected_updated_at is null then raise exception 'Expected source and target versions are required'; end if;
 perform id from public.customers where id in(p_source_customer_id,p_target_customer_id) order by id for update;
 select * into source_customer from public.customers where id=p_source_customer_id;
 select * into target_customer from public.customers where id=p_target_customer_id;
 if source_customer.id is null or source_customer.archived_at is not null then raise exception 'Active source customer not found'; end if;
 if target_customer.id is null or target_customer.archived_at is not null then raise exception 'Active target customer not found'; end if;
 if source_customer.updated_at<>p_source_expected_updated_at or target_customer.updated_at<>p_target_expected_updated_at then
  raise exception 'Customer changed after merge review. Reload both records.';
 end if;
 if source_customer.auth_user_id is not null and target_customer.auth_user_id is not null
  and source_customer.auth_user_id<>target_customer.auth_user_id then
  raise exception 'Customers belong to different authenticated users and cannot be merged';
 end if;
 update public.bookings set customer_id=p_target_customer_id,updated_at=now() where customer_id=p_source_customer_id;
 get diagnostics moved_bookings=row_count;
 update public.booking_passengers set customer_id=p_target_customer_id,updated_at=now() where customer_id=p_source_customer_id;
 get diagnostics moved_passengers=row_count;
 update public.payments set customer_id=p_target_customer_id,updated_at=now() where customer_id=p_source_customer_id;
 get diagnostics moved_payments=row_count;
 update public.corporate_contacts set customer_id=p_target_customer_id,updated_at=now() where customer_id=p_source_customer_id;
 get diagnostics moved_corporate_contacts=row_count;
 update public.customers set
  auth_user_id=coalesce(target_customer.auth_user_id,source_customer.auth_user_id),
  email=coalesce(target_customer.email,source_customer.email),
  phone=coalesce(target_customer.phone,source_customer.phone),
  whatsapp=coalesce(target_customer.whatsapp,source_customer.whatsapp),
  nationality=coalesce(target_customer.nationality,source_customer.nationality),
  notes=trim(both from concat_ws(E'\n',nullif(target_customer.notes,''),
   case when nullif(source_customer.notes,'') is not null then 'Merged customer note: '||source_customer.notes end)),
  updated_at=now() where id=p_target_customer_id;
 update public.customers set active=false,auth_user_id=null,archived_at=now(),
  notes=trim(both from concat_ws(E'\n',nullif(source_customer.notes,''),
   'Merged into customer '||p_target_customer_id::text||': '||trim(p_reason))),
  updated_at=now() where id=p_source_customer_id;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
 values(auth.uid(),'customer.merged','customer',p_target_customer_id,
  jsonb_build_object('source_customer_id',p_source_customer_id,'target_customer_id',p_target_customer_id,
   'reason',trim(p_reason),'moved_bookings',moved_bookings,'moved_passengers',moved_passengers,
   'moved_payments',moved_payments,'moved_corporate_contacts',moved_corporate_contacts));
 return jsonb_build_object('ok',true,'source_customer_id',p_source_customer_id,'target_customer_id',p_target_customer_id,
  'moved_bookings',moved_bookings,'moved_passengers',moved_passengers,'moved_payments',moved_payments,
  'moved_corporate_contacts',moved_corporate_contacts);
end;
$function$;

create or replace function public.next_booking_reference()
  returns text
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  n bigint;
begin
  n := nextval('public.booking_reference_seq');
  return 'KRI-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$function$;

create or replace function public.next_payment_reference()
  returns text
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  n bigint;
begin
  n := nextval('public.payment_reference_seq');
  return 'PAY-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$function$;

create or replace function public.normalize_company_name (
  raw_name text
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$ select nullif(lower(regexp_replace(trim(coalesce(raw_name,'')),'\s+',' ','g')),''); $function$;

create or replace function public.normalize_company_registration (
  raw_value text
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$ select nullif(upper(regexp_replace(coalesce(raw_value,''),'[^0-9A-Za-z]','','g')),''); $function$;

create or replace function public.normalize_customer_email (
  raw_email text
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$ select nullif(lower(trim(coalesce(raw_email,''))),''); $function$;

create or replace function public.normalize_customer_phone (
  raw_phone text
)
  returns text
  language sql
  immutable
  set search_path to 'public'
  AS $function$ select nullif(regexp_replace(coalesce(raw_phone,''),'[^0-9]','','g'),''); $function$;

create or replace function public.record_customer_payment (
  p_booking_id   uuid,
  p_amount       numeric,
  p_method       text,
  p_status       text    default 'received'::text,
  p_currency     text    default 'AED'::text,
  p_payment_link text    default null::text,
  p_notes        text    default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_payment_id uuid;
  v_ref text;
  v_booking_ref text;
  v_selling_price numeric;
  v_received_total numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  select booking_reference, selling_price
  into v_booking_ref, v_selling_price
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;
  v_ref := public.next_payment_reference();
  insert into public.payments (
    booking_id, payment_reference, amount, currency, method, status,
    payment_link, notes, received_at, created_by
  ) values (
    p_booking_id, v_ref, p_amount, upper(coalesce(p_currency, 'AED')),
    p_method, p_status, nullif(trim(coalesce(p_payment_link, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_status = 'received' then now() else null end, auth.uid()
  ) returning id into v_payment_id;
  if p_status = 'received' then
    select coalesce(sum(amount), 0)
    into v_received_total
    from public.payments
    where booking_id = p_booking_id
      and payment_direction = 'customer_in'
      and status = 'received';
  end if;
  update public.bookings
  set payment_status = case
        when p_status = 'received'
          and coalesce(v_selling_price, 0) > 0
          and v_received_total < v_selling_price then 'partially_paid'
        when p_status = 'received' then 'paid'
        when p_status = 'proof_received' then 'proof_received'
        else payment_status
      end,
      updated_at = now()
  where id = p_booking_id;
  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'payment.recorded', 'payment', v_payment_id,
    jsonb_build_object(
      'booking_reference', v_booking_ref, 'payment_reference', v_ref,
      'amount', p_amount, 'method', p_method, 'status', p_status,
      'received_total', v_received_total, 'selling_price', v_selling_price
    )
  );
  return v_payment_id;
end;
$function$;

create or replace function public.refresh_booking_document_status (
  target_booking_id uuid
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  update public.bookings b
  set document_status = case
        when exists (select 1 from public.booking_documents bd where bd.booking_id=target_booking_id and bd.visible_to_customer=true) then 'sent'
        when exists (select 1 from public.booking_documents bd where bd.booking_id=target_booking_id) then 'generated'
        else 'not_started'
      end,
      updated_at = now()
  where b.id=target_booking_id and b.document_status <> 'archived';
end;
$function$;

create or replace function public.rls_auto_enable()
  returns event_trigger
  language plpgsql
  security definer
  set search_path to 'pg_catalog'
  AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

create or replace function public.set_document_number()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare yr text := to_char(now(), 'YYYY'); prefix text; seq_name text;
begin
 if new.document_number is not null and new.document_number <> '' then return new; end if;
 case new.document_type
 when 'invoice' then prefix := 'INV'; seq_name := 'public.doc_invoice_seq';
 when 'eticket' then prefix := 'ETK'; seq_name := 'public.doc_eticket_seq';
 when 'cancellation' then prefix := 'CXL'; seq_name := 'public.doc_cancellation_seq';
 when 'visa_rejection' then prefix := 'REJ'; seq_name := 'public.doc_rejection_seq';
 when 'receipt' then prefix := 'RCT'; seq_name := 'public.doc_receipt_seq';
 when 'payment_request' then prefix := 'PAY'; seq_name := 'public.doc_receipt_seq';
 when 'refund_note' then prefix := 'RFN'; seq_name := 'public.doc_receipt_seq';
 when 'quotation' then prefix := 'QTN'; seq_name := 'public.doc_invoice_seq';
 when 'hotel_voucher' then prefix := 'HTL'; seq_name := 'public.doc_eticket_seq';
 when 'visa_confirmation' then prefix := 'VSA'; seq_name := 'public.doc_eticket_seq';
 when 'corporate_confirmation' then prefix := 'COR'; seq_name := 'public.doc_eticket_seq';
 when 'supplier_payment_note' then prefix := 'SPN'; seq_name := 'public.doc_invoice_seq';
 when 'monthly_statement' then prefix := 'STM'; seq_name := 'public.doc_statement_seq';
 else prefix := 'DOC'; seq_name := 'public.doc_invoice_seq'; end case;
 new.document_number := prefix || '-' || yr || '-' || lpad(nextval(seq_name)::text, 4, '0'); return new;
end;$function$;

create or replace function public.staff_identity_for_pin (
  p_pin text
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path to 'public', 'extensions'
  AS $function$
  select jsonb_build_object('user_id', u.id, 'email', u.email)
  from public.staff_pin_credentials pc
  join public.staff_profiles sp on sp.user_id = pc.user_id
  join auth.users u on u.id = pc.user_id
  where sp.active = true
    and sp.pin_reset_required = false
    and (pc.locked_until is null or pc.locked_until <= now())
    and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash)
  limit 1;
$function$;

create or replace function public.staff_management_admin_count (
  except_user_id uuid default null::uuid
)
  returns integer
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select count(*)::integer
  from public.staff_roles sr
  left join public.staff_profiles sp on sp.user_id = sr.user_id
  where sr.role in ('owner', 'admin')
    and (except_user_id is null or sr.user_id <> except_user_id)
    and coalesce(sp.active, true) = true
    and coalesce(sp.deleted_at is null, true)
    and (sp.hold_until is null or sp.hold_until <= now());
$function$;

create or replace function public.staff_pin_in_use (
  p_pin             text,
  p_exclude_user_id uuid default null::uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public', 'extensions'
  AS $function$
  select exists (
    select 1 from public.staff_pin_credentials pc
    join public.staff_profiles sp on sp.user_id = pc.user_id
    where sp.active = true
      and (p_exclude_user_id is null or pc.user_id <> p_exclude_user_id)
      and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash)
  );
$function$;

create or replace function public.staff_pin_login_begin (
  p_ip_hash text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_state public.staff_pin_login_security_state%rowtype;
  v_global_failures integer;
  v_ip_failures integer;
  v_backoff_seconds integer;
  v_attempt_id uuid;
begin
  if p_ip_hash is null or char_length(p_ip_hash) <> 64 then
    raise exception 'Invalid address hash';
  end if;

  select * into v_state from public.staff_pin_login_security_state
  where singleton = true for update;

  if v_state.blocked_until is not null and v_state.blocked_until > now() then
    return jsonb_build_object(
      'allowed', false,
      'scope', 'global',
      'retry_after_seconds', greatest(1, ceil(extract(epoch from v_state.blocked_until - now())))::integer
    );
  end if;

  select count(*) into v_global_failures
  from public.staff_pin_login_attempts
  where success = false and attempted_at >= now() - interval '15 minutes';

  if v_global_failures >= 50 then
    v_backoff_seconds := least(3600, 60 * (2 ^ least(v_state.backoff_level, 6))::integer);
    update public.staff_pin_login_security_state
    set blocked_until = now() + make_interval(secs => v_backoff_seconds),
        backoff_level = least(backoff_level + 1, 8), updated_at = now()
    where singleton = true;
    insert into public.audit_events (event_type, entity_type, metadata)
    values ('security.staff_pin_global_limit', 'authentication',
      jsonb_build_object('failed_attempts', v_global_failures, 'backoff_seconds', v_backoff_seconds));
    return jsonb_build_object('allowed', false, 'scope', 'global', 'retry_after_seconds', v_backoff_seconds);
  end if;

  select count(*) into v_ip_failures
  from public.staff_pin_login_attempts
  where ip_hash = p_ip_hash and success = false
    and attempted_at >= now() - interval '15 minutes';
  if v_ip_failures >= 5 then
    return jsonb_build_object('allowed', false, 'scope', 'ip', 'retry_after_seconds', 900);
  end if;

  insert into public.staff_pin_login_attempts (ip_hash, success)
  values (p_ip_hash, false) returning id into v_attempt_id;
  return jsonb_build_object('allowed', true, 'attempt_id', v_attempt_id);
end;
$function$;

create or replace function public.staff_pin_login_finish (
  p_attempt_id uuid,
  p_user_id    uuid    default null::uuid,
  p_success    boolean default false
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if p_success then
    update public.staff_pin_login_attempts set success = true where id = p_attempt_id;
    if p_user_id is not null then
      update public.staff_pin_credentials
      set failed_auth_attempts = 0, locked_until = null
      where user_id = p_user_id;
    end if;
    update public.staff_pin_login_security_state
    set backoff_level = 0, blocked_until = null, updated_at = now()
    where singleton = true;
  elsif p_user_id is not null then
    update public.staff_pin_credentials
    set failed_auth_attempts = failed_auth_attempts + 1,
        locked_until = case
          when failed_auth_attempts + 1 >= 5 then now() + interval '30 minutes'
          else locked_until
        end
    where user_id = p_user_id;
  end if;
end;
$function$;

create or replace function public.staff_set_pin (
  p_user_id uuid,
  p_pin     text
)
  returns void
  language plpgsql
  security definer
  set search_path to 'public', 'extensions'
  AS $function$
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then raise exception 'PIN must contain exactly six digits'; end if;
  insert into public.staff_pin_credentials (user_id, pin_hash, updated_at, failed_auth_attempts, locked_until)
  values (p_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf')), now(), 0, null)
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, updated_at = now(), failed_auth_attempts = 0, locked_until = null;
  update public.staff_profiles set pin_reset_required = false where user_id = p_user_id;
end;
$function$;

create or replace function public.sync_booking_document_status()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  if tg_op='DELETE' then
    perform public.refresh_booking_document_status(old.booking_id);
    return old;
  end if;
  perform public.refresh_booking_document_status(new.booking_id);
  if tg_op='UPDATE' and old.booking_id is distinct from new.booking_id then
    perform public.refresh_booking_document_status(old.booking_id);
  end if;
  return new;
end;
$function$;

create or replace function public.sync_quote_response_lifecycle()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  linked_enquiry_id uuid := new.enquiry_id;
begin
  if old.status = 'sent' and new.status = 'accepted' then
    update public.quotes q
    set status = 'expired'
    where q.id <> new.id and q.status = 'sent'
      and (
        (new.booking_id is not null and q.booking_id = new.booking_id)
        or (linked_enquiry_id is not null and q.enquiry_id = linked_enquiry_id)
      );
    if linked_enquiry_id is not null then
      update public.enquiries
      set status = 'payment_pending', updated_at = now()
      where id = linked_enquiry_id
        and status in ('received', 'checking_availability', 'quote_sent');
    end if;
    update public.bookings b
    set status = 'payment_pending', selling_price = new.price_amount,
        amount = new.price_amount, currency = new.currency, updated_at = now()
    where b.archived_at is null
      and b.status in ('enquiry', 'quote_sent', 'payment_pending')
      and (
        b.id = new.booking_id
        or (linked_enquiry_id is not null and b.enquiry_id = linked_enquiry_id)
      );
    insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
    values (auth.uid(), 'quote.accepted', 'quote', new.id,
      jsonb_build_object('enquiry_id', linked_enquiry_id, 'booking_id', new.booking_id,
        'price_amount', new.price_amount, 'currency', new.currency));
  elsif old.status = 'sent' and new.status = 'declined' then
    insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
    values (auth.uid(), 'quote.declined', 'quote', new.id,
      jsonb_build_object('enquiry_id', linked_enquiry_id, 'booking_id', new.booking_id));
  end if;
  return new;
end;
$function$;

create or replace function public.update_operations_booking_status_v2 (
  p_booking_id          uuid,
  p_status              public.booking_status,
  p_payment_status      text,
  p_document_status     text,
  p_expected_updated_at timestamp with time zone,
  p_supplier_reference  text                     default null::text,
  p_staff_notes         text                     default null::text
)
  returns timestamp with time zone
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_ref text; v_updated_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_staff_permission('edit_bookings') then raise exception 'Permission denied'; end if;
  if p_expected_updated_at is null then raise exception 'Expected booking version is required'; end if;
  update public.bookings
  set status=p_status,payment_status=p_payment_status,document_status=p_document_status,
      supplier_reference=nullif(trim(coalesce(p_supplier_reference,'')),''),
      staff_notes=nullif(trim(coalesce(p_staff_notes,'')),''),
      updated_at=clock_timestamp()
  where id=p_booking_id and updated_at=p_expected_updated_at
  returning booking_reference,updated_at into v_ref,v_updated_at;
  if v_ref is null then
    if exists(select 1 from public.bookings where id=p_booking_id) then
      raise exception 'Booking changed after this page was loaded. Reload and review the latest values.';
    end if;
    raise exception 'Booking not found';
  end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(auth.uid(),'booking.status_updated','booking',p_booking_id,
    jsonb_build_object('reference',v_ref,'status',p_status,'payment_status',p_payment_status,
      'document_status',p_document_status,'expected_updated_at',p_expected_updated_at,'updated_at',v_updated_at));
  return v_updated_at;
end;
$function$;

create or replace function public.validate_booking_document_status()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare has_documents boolean; has_visible_documents boolean;
begin
  if new.document_status = old.document_status then return new; end if;
  select
    exists (select 1 from public.booking_documents bd where bd.booking_id=new.id),
    exists (select 1 from public.booking_documents bd where bd.booking_id=new.id and bd.visible_to_customer=true)
  into has_documents, has_visible_documents;
  if new.document_status='sent' and not has_visible_documents then
    raise exception 'Document status sent requires a customer-visible document';
  end if;
  if new.document_status='generated' and not has_documents then
    raise exception 'Document status generated requires a linked document';
  end if;
  if new.document_status='not_started' and has_documents then
    raise exception 'Document status not_started is invalid while documents exist';
  end if;
  return new;
end;
$function$;

create or replace function public.validate_public_enquiry_payload()
  returns trigger
  language plpgsql
  set search_path to 'public', 'pg_temp'
  AS $function$
declare missing_fields text[]:='{}';
begin
 if current_user in ('postgres','service_role','supabase_admin') then return new; end if;
 if current_user='authenticated' then if coalesce(public.is_staff(),false) then return new; end if; end if;
 if new.email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid email address'; end if;
 if new.phone is null or char_length(btrim(new.phone)) not between 7 and 30 then raise exception 'Enter a valid phone or WhatsApp number'; end if;
 if jsonb_typeof(new.details)<>'object' or octet_length(new.details::text)>32768 then raise exception 'Enquiry details are invalid or too large'; end if;
 case new.service_type
 when 'flight' then if nullif(btrim(new.details->>'Route'),'') is null then missing_fields:=array_append(missing_fields,'route'); end if; if nullif(btrim(new.details->>'Travellers'),'') is null then missing_fields:=array_append(missing_fields,'travellers'); end if; if nullif(btrim(new.details->>'Cabin'),'') is null then missing_fields:=array_append(missing_fields,'cabin'); end if;
 when 'hotel' then if nullif(btrim(new.details->>'City'),'') is null then missing_fields:=array_append(missing_fields,'city'); end if; if nullif(btrim(new.details->>'Stay'),'') is null then missing_fields:=array_append(missing_fields,'stay dates'); end if; if nullif(btrim(new.details->>'Rooms_Guests'),'') is null then missing_fields:=array_append(missing_fields,'rooms and guests'); end if;
 when 'holiday' then if nullif(btrim(new.details->>'Destination'),'') is null then missing_fields:=array_append(missing_fields,'destination'); end if; if coalesce(new.details->>'Travel_month','') !~ '^[0-9]{4}-[0-9]{2}$' then missing_fields:=array_append(missing_fields,'travel month'); end if;
 when 'visa' then if nullif(btrim(new.details->>'Country'),'') is null then missing_fields:=array_append(missing_fields,'visa country'); end if; if nullif(btrim(new.details->>'Nationality'),'') is null then missing_fields:=array_append(missing_fields,'nationality'); end if;
 when 'umrah' then if nullif(btrim(new.details->>'Package'),'') is null then missing_fields:=array_append(missing_fields,'Umrah package'); end if;
 when 'cruise' then if nullif(btrim(new.details->>'Cruise'),'') is null then missing_fields:=array_append(missing_fields,'cruise'); end if;
 when 'other' then if nullif(btrim(new.details->>'Message'),'') is null then missing_fields:=array_append(missing_fields,'message'); end if;
 end case;
 if cardinality(missing_fields)>0 then raise exception 'Missing required enquiry details: %',array_to_string(missing_fields,', '); end if;
 return new;
end $function$;

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text)
  from public;

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text)
  from "authenticated";

grant execute
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text)
  to "authenticated";

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text)
  from "service_role";

grant execute
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text)
  to "service_role";

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid)
  from public;

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid)
  from "authenticated";

grant execute
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid)
  to "authenticated";

revoke all
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid)
  from "service_role";

grant execute
  on function "public"."create_operations_booking"(text, public.booking_service_type, text, text, text, text, uuid, text, date, date, numeric, numeric, text, uuid, text, uuid)
  to "service_role";

revoke all on function "public"."grant_staff_by_email"(text, public.staff_role) from public;

revoke all on function "public"."grant_staff_by_email"(text, public.staff_role) from "service_role";

grant execute on function "public"."grant_staff_by_email"(text, public.staff_role) to "service_role";

revoke all on function "public"."handle_new_auth_user"() from public;

revoke all on function "public"."is_admin"() from public;

revoke all on function "public"."is_admin"() from "service_role";

grant execute on function "public"."is_admin"() to "service_role";

revoke all on function "public"."is_staff"() from public;

revoke all on function "public"."is_staff"() from "service_role";

grant execute on function "public"."is_staff"() to "service_role";

revoke all on function "public"."list_audit_events"(integer) from public;

revoke all on function "public"."list_audit_events"(integer) from "service_role";

grant execute on function "public"."list_audit_events"(integer) to "service_role";

revoke all on function "public"."list_dashboard_booking_tasks"(integer) from public;

revoke all on function "public"."list_dashboard_booking_tasks"(integer) from "authenticated";

grant execute on function "public"."list_dashboard_booking_tasks"(integer) to "authenticated";

revoke all on function "public"."list_dashboard_booking_tasks"(integer) from "service_role";

grant execute on function "public"."list_dashboard_booking_tasks"(integer) to "service_role";

revoke all on function "public"."list_staff"() from public;

revoke all on function "public"."list_staff"() from "service_role";

grant execute on function "public"."list_staff"() to "service_role";

revoke all on function "public"."list_staff_for_login"() from public;

revoke all on function "public"."revoke_staff"(uuid) from public;

revoke all on function "public"."revoke_staff"(uuid) from "service_role";

grant execute on function "public"."revoke_staff"(uuid) to "service_role";

revoke all on function "public"."set_document_number"() from public;

revoke all on function "public"."set_document_number"() from "service_role";

grant execute on function "public"."set_document_number"() to "service_role";

revoke all on function "public"."setup_staff_account_record"(uuid, text, text, public.staff_role) from "service_role";

grant execute on function "public"."setup_staff_account_record"(uuid, text, text, public.staff_role) to "service_role";

revoke all on function "public"."staff_monitoring_summary"(integer) from public;

revoke all on function "public"."staff_monitoring_summary"(integer) from "authenticated";

grant execute on function "public"."staff_monitoring_summary"(integer) to "authenticated";

revoke all on function "public"."staff_monitoring_summary"(integer) from "service_role";

grant execute on function "public"."staff_monitoring_summary"(integer) to "service_role";

revoke all on table "public"."staff_permissions" from "authenticated";

grant delete, insert, select, update on table "public"."staff_permissions" to "authenticated";

-- These identity sequences were created before the production default sequence
-- privileges were tightened, so align their existing ACLs explicitly as well.
revoke all on sequence "public"."marketing_unsubscribe_requests_id_seq"
  from "anon", "authenticated", "service_role";
revoke all on sequence "public"."meta_conversion_requests_id_seq"
  from "anon", "authenticated", "service_role";
