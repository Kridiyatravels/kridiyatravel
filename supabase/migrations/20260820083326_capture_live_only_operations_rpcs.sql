-- Exact capture of nine RPCs present in production but absent from every
-- timestamped and legacy migration in this repository. Definitions below are
-- copied from the 2026-08-20 production schema dump without behavioral edits.

CREATE OR REPLACE FUNCTION "public"."create_corporate_account"("p_company_name" "text", "p_billing_email" "text" DEFAULT NULL::"text", "p_accounts_email" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_address" "text" DEFAULT NULL::"text", "p_trade_license_no" "text" DEFAULT NULL::"text", "p_trn" "text" DEFAULT NULL::"text", "p_payment_terms" "text" DEFAULT 'payment_before_booking'::"text", "p_credit_allowed" boolean DEFAULT false, "p_monthly_billing" boolean DEFAULT false, "p_lpo_required" boolean DEFAULT false, "p_status" "text" DEFAULT 'prospect'::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  insert into public.corporate_accounts (
    company_name, billing_email, accounts_email, phone, address,
    trade_license_no, trn, payment_terms, credit_allowed, monthly_billing,
    lpo_required, status, notes, created_by
  ) values (
    trim(p_company_name), nullif(trim(coalesce(p_billing_email, '')), ''), nullif(trim(coalesce(p_accounts_email, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_address, '')), ''),
    nullif(trim(coalesce(p_trade_license_no, '')), ''), nullif(trim(coalesce(p_trn, '')), ''),
    coalesce(nullif(p_payment_terms, ''), 'payment_before_booking'), coalesce(p_credit_allowed, false), coalesce(p_monthly_billing, false),
    coalesce(p_lpo_required, false), coalesce(nullif(p_status, ''), 'prospect'), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."create_corporate_contact"("p_corporate_account_id" "uuid", "p_full_name" "text", "p_job_title" "text" DEFAULT NULL::"text", "p_email" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_whatsapp" "text" DEFAULT NULL::"text", "p_is_authorized_contact" boolean DEFAULT false, "p_is_accounts_contact" boolean DEFAULT false, "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_customer_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  if not exists (select 1 from public.corporate_accounts where id = p_corporate_account_id and archived_at is null) then
    raise exception 'Corporate account not found';
  end if;

  insert into public.customers (
    customer_type, full_name, email, phone, whatsapp, source, notes, created_by
  ) values (
    'corporate_contact', trim(p_full_name), nullif(trim(coalesce(p_email, '')), ''), nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(coalesce(p_whatsapp, '')), ''), 'corporate', nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_customer_id;

  insert into public.corporate_contacts (
    corporate_account_id, customer_id, full_name, job_title, email, phone, whatsapp,
    is_authorized_contact, is_accounts_contact, notes, created_by
  ) values (
    p_corporate_account_id, v_customer_id, trim(p_full_name), nullif(trim(coalesce(p_job_title, '')), ''),
    nullif(trim(coalesce(p_email, '')), ''), nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_whatsapp, '')), ''),
    coalesce(p_is_authorized_contact, false), coalesce(p_is_accounts_contact, false), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."delete_booking_document"("p_document_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then
    raise exception 'Document permission required';
  end if;
  delete from public.booking_documents where id = p_document_id;
  return found;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."delete_booking_passenger"("p_passenger_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Booking edit permission required';
  end if;
  delete from public.booking_passengers where id = p_passenger_id;
  return found;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."generate_booking_payment_request_document"("p_booking_id" "uuid", "p_amount_requested" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_booking public.bookings%rowtype;
  v_customer public.customers%rowtype;
  v_doc public.documents%rowtype;
  v_total numeric := 0;
  v_received numeric := 0;
  v_due numeric := 0;
  v_amount numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('view_payments') or public.has_staff_permission('edit_payments') or public.has_staff_permission('generate_documents')) then
    raise exception 'Payment or document permission required';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if not found then
    raise exception 'Booking not found';
  end if;

  if v_booking.customer_id is not null then
    select * into v_customer from public.customers where id = v_booking.customer_id;
  end if;

  v_total := coalesce(v_booking.selling_price, v_booking.amount, 0);

  select coalesce(sum(p.amount), 0) into v_received
  from public.payments p
  where p.booking_id = p_booking_id
    and p.payment_direction = 'customer_in'
    and p.status = 'received';

  v_due := greatest(v_total - v_received, 0);
  v_amount := coalesce(p_amount_requested, v_due);

  if v_amount <= 0 then
    raise exception 'No amount due for this booking';
  end if;

  insert into public.documents (
    document_type,
    enquiry_id,
    customer_name,
    customer_email,
    amount_total,
    currency,
    payload,
    created_by
  ) values (
    'payment_request',
    v_booking.enquiry_id,
    coalesce(v_customer.full_name, v_booking.title),
    v_customer.email,
    v_amount,
    v_booking.currency,
    jsonb_build_object(
      'kind', 'booking_payment_request',
      'booking_id', v_booking.id,
      'booking_reference', v_booking.booking_reference,
      'booking_title', v_booking.title,
      'service_type', v_booking.service_type,
      'route_or_destination', v_booking.route_or_destination,
      'travel_start', v_booking.travel_start,
      'travel_end', v_booking.travel_end,
      'total_amount', v_total,
      'received_amount', v_received,
      'amount_due', v_due,
      'amount_requested', v_amount,
      'customer_name', coalesce(v_customer.full_name, v_booking.title),
      'customer_email', v_customer.email,
      'customer_phone', coalesce(v_customer.phone, v_customer.whatsapp),
      'notes', nullif(trim(coalesce(p_notes, '')), '')
    ),
    auth.uid()
  ) returning * into v_doc;

  return jsonb_build_object(
    'id', v_doc.id,
    'document_number', v_doc.document_number,
    'document_type', v_doc.document_type,
    'customer_name', v_doc.customer_name,
    'customer_email', v_doc.customer_email,
    'amount_total', v_doc.amount_total,
    'currency', v_doc.currency,
    'payload', v_doc.payload,
    'created_at', v_doc.created_at
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."generate_booking_receipt_document"("p_booking_id" "uuid", "p_payment_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_booking public.bookings%rowtype;
  v_payment public.payments%rowtype;
  v_customer public.customers%rowtype;
  v_doc public.documents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('view_payments') or public.has_staff_permission('edit_payments') or public.has_staff_permission('generate_documents')) then
    raise exception 'Payment or document permission required';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if not found then
    raise exception 'Booking not found';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id and booking_id = p_booking_id;
  if not found then
    raise exception 'Payment not found';
  end if;

  if v_payment.status not in ('received', 'proof_received') then
    raise exception 'Receipt can only be generated for received payments or proof received';
  end if;

  if v_payment.receipt_document_id is not null then
    select * into v_doc from public.documents where id = v_payment.receipt_document_id;
    if found then
      return jsonb_build_object(
        'id', v_doc.id,
        'document_number', v_doc.document_number,
        'document_type', v_doc.document_type,
        'customer_name', v_doc.customer_name,
        'customer_email', v_doc.customer_email,
        'amount_total', v_doc.amount_total,
        'currency', v_doc.currency,
        'payload', v_doc.payload,
        'created_at', v_doc.created_at
      );
    end if;
  end if;

  if v_booking.customer_id is not null then
    select * into v_customer from public.customers where id = v_booking.customer_id;
  end if;

  insert into public.documents (
    document_type,
    enquiry_id,
    customer_name,
    customer_email,
    amount_total,
    currency,
    payload,
    created_by
  ) values (
    'receipt',
    v_booking.enquiry_id,
    coalesce(v_customer.full_name, v_booking.title),
    v_customer.email,
    v_payment.amount,
    v_payment.currency,
    jsonb_build_object(
      'kind', 'booking_receipt',
      'booking_id', v_booking.id,
      'booking_reference', v_booking.booking_reference,
      'booking_title', v_booking.title,
      'service_type', v_booking.service_type,
      'route_or_destination', v_booking.route_or_destination,
      'payment_id', v_payment.id,
      'payment_reference', v_payment.payment_reference,
      'payment_method', v_payment.method,
      'payment_status', v_payment.status,
      'payment_notes', v_payment.notes,
      'received_at', coalesce(v_payment.received_at, v_payment.created_at),
      'customer_name', coalesce(v_customer.full_name, v_booking.title),
      'customer_email', v_customer.email,
      'customer_phone', coalesce(v_customer.phone, v_customer.whatsapp)
    ),
    auth.uid()
  ) returning * into v_doc;

  update public.payments
  set receipt_document_id = v_doc.id,
      updated_at = now()
  where id = v_payment.id;

  return jsonb_build_object(
    'id', v_doc.id,
    'document_number', v_doc.document_number,
    'document_type', v_doc.document_type,
    'customer_name', v_doc.customer_name,
    'customer_email', v_doc.customer_email,
    'amount_total', v_doc.amount_total,
    'currency', v_doc.currency,
    'payload', v_doc.payload,
    'created_at', v_doc.created_at
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."record_booking_document"("p_booking_id" "uuid", "p_document_type" "text", "p_file_name" "text", "p_external_reference" "text" DEFAULT NULL::"text", "p_storage_path" "text" DEFAULT NULL::"text", "p_visible_to_customer" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then
    raise exception 'Document permission required';
  end if;
  select coalesce(user_id, auth.uid()) into v_user_id
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if not found then
    raise exception 'Booking not found';
  end if;
  insert into public.booking_documents (
    booking_id, user_id, document_type, file_name, storage_path,
    external_reference, visible_to_customer, created_by
  ) values (
    p_booking_id, v_user_id, trim(p_document_type), trim(p_file_name), nullif(trim(coalesce(p_storage_path, '')), ''),
    nullif(trim(coalesce(p_external_reference, '')), ''), coalesce(p_visible_to_customer, false), auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."record_booking_passenger"("p_booking_id" "uuid", "p_passenger_name" "text", "p_passenger_type" "text" DEFAULT 'adult'::"text", "p_nationality" "text" DEFAULT NULL::"text", "p_date_of_birth" "date" DEFAULT NULL::"date", "p_passport_number" "text" DEFAULT NULL::"text", "p_passport_expiry" "date" DEFAULT NULL::"date", "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_customer_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Booking edit permission required';
  end if;
  select customer_id into v_customer_id
  from public.bookings
  where id = p_booking_id and archived_at is null;
  if not found then
    raise exception 'Booking not found';
  end if;
  insert into public.booking_passengers (
    booking_id, customer_id, passenger_name, passenger_type, nationality,
    date_of_birth, passport_number, passport_expiry, notes, created_by
  ) values (
    p_booking_id, v_customer_id, trim(p_passenger_name), coalesce(nullif(p_passenger_type, ''), 'adult'), nullif(trim(coalesce(p_nationality, '')), ''),
    p_date_of_birth, nullif(trim(coalesce(p_passport_number, '')), ''), p_passport_expiry, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."update_booking_corporate_controls"("p_booking_id" "uuid", "p_lpo_number" "text" DEFAULT NULL::"text", "p_approval_person" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (public.has_staff_permission('edit_bookings') or public.has_staff_permission('edit_corporates')) then
    raise exception 'Corporate booking edit permission required';
  end if;

  update public.bookings
  set lpo_number = nullif(trim(coalesce(p_lpo_number, '')), ''),
      approval_person = nullif(trim(coalesce(p_approval_person, '')), ''),
      updated_at = now()
  where id = p_booking_id
    and archived_at is null
    and booking_kind = 'corporate';

  if not found then
    raise exception 'Corporate booking not found';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.corporate_controls_updated', 'booking', p_booking_id, jsonb_build_object('lpo_number', p_lpo_number, 'approval_person', p_approval_person));

  return true;
end;
$$;

-- Exact production execute privileges for the captured RPCs.

REVOKE ALL ON FUNCTION "public"."create_corporate_account"("p_company_name" "text", "p_billing_email" "text", "p_accounts_email" "text", "p_phone" "text", "p_address" "text", "p_trade_license_no" "text", "p_trn" "text", "p_payment_terms" "text", "p_credit_allowed" boolean, "p_monthly_billing" boolean, "p_lpo_required" boolean, "p_status" "text", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_corporate_account"("p_company_name" "text", "p_billing_email" "text", "p_accounts_email" "text", "p_phone" "text", "p_address" "text", "p_trade_license_no" "text", "p_trn" "text", "p_payment_terms" "text", "p_credit_allowed" boolean, "p_monthly_billing" boolean, "p_lpo_required" boolean, "p_status" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_corporate_account"("p_company_name" "text", "p_billing_email" "text", "p_accounts_email" "text", "p_phone" "text", "p_address" "text", "p_trade_license_no" "text", "p_trn" "text", "p_payment_terms" "text", "p_credit_allowed" boolean, "p_monthly_billing" boolean, "p_lpo_required" boolean, "p_status" "text", "p_notes" "text") TO "service_role";
REVOKE ALL ON FUNCTION "public"."create_corporate_contact"("p_corporate_account_id" "uuid", "p_full_name" "text", "p_job_title" "text", "p_email" "text", "p_phone" "text", "p_whatsapp" "text", "p_is_authorized_contact" boolean, "p_is_accounts_contact" boolean, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_corporate_contact"("p_corporate_account_id" "uuid", "p_full_name" "text", "p_job_title" "text", "p_email" "text", "p_phone" "text", "p_whatsapp" "text", "p_is_authorized_contact" boolean, "p_is_accounts_contact" boolean, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_corporate_contact"("p_corporate_account_id" "uuid", "p_full_name" "text", "p_job_title" "text", "p_email" "text", "p_phone" "text", "p_whatsapp" "text", "p_is_authorized_contact" boolean, "p_is_accounts_contact" boolean, "p_notes" "text") TO "service_role";
REVOKE ALL ON FUNCTION "public"."delete_booking_document"("p_document_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_booking_document"("p_document_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_booking_document"("p_document_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."delete_booking_passenger"("p_passenger_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_booking_passenger"("p_passenger_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_booking_passenger"("p_passenger_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."generate_booking_payment_request_document"("p_booking_id" "uuid", "p_amount_requested" numeric, "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_booking_payment_request_document"("p_booking_id" "uuid", "p_amount_requested" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_booking_payment_request_document"("p_booking_id" "uuid", "p_amount_requested" numeric, "p_notes" "text") TO "service_role";
REVOKE ALL ON FUNCTION "public"."generate_booking_receipt_document"("p_booking_id" "uuid", "p_payment_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_booking_receipt_document"("p_booking_id" "uuid", "p_payment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_booking_receipt_document"("p_booking_id" "uuid", "p_payment_id" "uuid") TO "service_role";
REVOKE ALL ON FUNCTION "public"."record_booking_document"("p_booking_id" "uuid", "p_document_type" "text", "p_file_name" "text", "p_external_reference" "text", "p_storage_path" "text", "p_visible_to_customer" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_booking_document"("p_booking_id" "uuid", "p_document_type" "text", "p_file_name" "text", "p_external_reference" "text", "p_storage_path" "text", "p_visible_to_customer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_booking_document"("p_booking_id" "uuid", "p_document_type" "text", "p_file_name" "text", "p_external_reference" "text", "p_storage_path" "text", "p_visible_to_customer" boolean) TO "service_role";
REVOKE ALL ON FUNCTION "public"."record_booking_passenger"("p_booking_id" "uuid", "p_passenger_name" "text", "p_passenger_type" "text", "p_nationality" "text", "p_date_of_birth" "date", "p_passport_number" "text", "p_passport_expiry" "date", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_booking_passenger"("p_booking_id" "uuid", "p_passenger_name" "text", "p_passenger_type" "text", "p_nationality" "text", "p_date_of_birth" "date", "p_passport_number" "text", "p_passport_expiry" "date", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_booking_passenger"("p_booking_id" "uuid", "p_passenger_name" "text", "p_passenger_type" "text", "p_nationality" "text", "p_date_of_birth" "date", "p_passport_number" "text", "p_passport_expiry" "date", "p_notes" "text") TO "service_role";
REVOKE ALL ON FUNCTION "public"."update_booking_corporate_controls"("p_booking_id" "uuid", "p_lpo_number" "text", "p_approval_person" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_booking_corporate_controls"("p_booking_id" "uuid", "p_lpo_number" "text", "p_approval_person" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_booking_corporate_controls"("p_booking_id" "uuid", "p_lpo_number" "text", "p_approval_person" "text") TO "service_role";
