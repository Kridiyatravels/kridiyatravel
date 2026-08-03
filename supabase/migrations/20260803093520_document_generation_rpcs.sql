-- Customer-safe document generators for every printable document template.

create or replace function public.document_rpc_result(p_doc public.documents)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', p_doc.id, 'document_number', p_doc.document_number,
    'document_type', p_doc.document_type, 'customer_name', p_doc.customer_name,
    'customer_email', p_doc.customer_email, 'amount_total', p_doc.amount_total,
    'currency', p_doc.currency, 'payload', p_doc.payload, 'created_at', p_doc.created_at
  );
$function$;

create or replace function public.safe_booking_document_payload(p_booking public.bookings)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', p_booking.id, 'booking_reference', p_booking.booking_reference,
    'service_type', p_booking.service_type, 'title', p_booking.title,
    'route_or_destination', p_booking.route_or_destination,
    'travel_start', p_booking.travel_start, 'travel_end', p_booking.travel_end,
    'adults', p_booking.adults, 'children', p_booking.children, 'infants', p_booking.infants,
    'amount', coalesce(p_booking.selling_price, p_booking.amount, 0),
    'currency', p_booking.currency, 'status', p_booking.status,
    'supplier_reference', p_booking.supplier_reference,
    'customer_notes', p_booking.customer_notes, 'created_at', p_booking.created_at,
    'lpo_number', p_booking.lpo_number, 'approval_person', p_booking.approval_person,
    'payment_status', p_booking.payment_status
  );
$function$;

create or replace function public.safe_passengers_document_payload(p_booking_id uuid)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bp.id, 'passenger_name', bp.passenger_name,
    'passenger_type', bp.passenger_type, 'nationality', bp.nationality,
    'date_of_birth', bp.date_of_birth, 'passport_number', bp.passport_number,
    'passport_expiry', bp.passport_expiry
  ) order by bp.created_at, bp.id), '[]'::jsonb)
  from public.booking_passengers bp where bp.booking_id = p_booking_id;
$function$;

create or replace function public.generate_quotation_document(p_quote_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_quote public.quotes%rowtype; v_booking public.bookings%rowtype;
  v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings')) then
    raise exception 'Quote or document permission required'; end if;
  select * into v_quote from public.quotes where id = p_quote_id;
  if not found then raise exception 'Quote not found'; end if;
  select * into v_booking from public.bookings where id = v_quote.booking_id and archived_at is null;
  if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('quotation:' || p_quote_id::text, 0));
  select * into v_doc from public.documents where document_type = 'quotation' and payload->>'record_id' = p_quote_id::text order by created_at limit 1;
  if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  v_payload := jsonb_build_object('record_id',v_quote.id,'quote',jsonb_build_object(
    'id',v_quote.id,'title',v_quote.title,'description',v_quote.description,
    'price_amount',v_quote.price_amount,'currency',v_quote.currency,'valid_until',v_quote.valid_until,
    'terms',v_quote.terms,'status',v_quote.status,'created_at',v_quote.created_at,
    'airline',v_quote.airline,'stops',v_quote.stops,'outbound',v_quote.outbound,
    'inbound',v_quote.inbound,'baggage',v_quote.baggage,'addons',coalesce(v_quote.addons,'[]'::jsonb),
    'option_data',coalesce(v_quote.option_data,'{}'::jsonb)),
    'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_by','Kridiya Travel'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by)
  values('quotation',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,v_quote.price_amount,v_quote.currency,v_payload,auth.uid()) returning * into v_doc;
  return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_eticket_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then raise exception 'Booking or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('eticket:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='eticket' and payload->>'record_id'=p_booking_id::text order by created_at limit 1;
  if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),
    'passengers',public.safe_passengers_document_payload(v_booking.id),'segments',coalesce(v_booking.service_payload->'segments','[]'::jsonb),
    'extras',jsonb_build_object('pnr',v_booking.supplier_reference,'issued_by','Kridiya Travel','ticketed',v_booking.status='ticketed'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by)
  values('eticket',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc;
  return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_hotel_voucher_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_paid numeric; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then raise exception 'Booking or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hotel_voucher:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='hotel_voucher' and payload->>'record_id'=p_booking_id::text order by created_at limit 1;
  if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  select coalesce(sum(amount),0) into v_paid from public.payments where booking_id=p_booking_id and payment_direction='customer_in' and status in ('received','proof_received');
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),
    'hotel',jsonb_build_object('name',v_booking.service_payload->>'name','address',v_booking.service_payload->>'address','phone',v_booking.service_payload->>'phone','confirmation_number',coalesce(v_booking.service_payload->>'confirmation_number',v_booking.supplier_reference),'room_type',v_booking.service_payload->>'room_type','rooms',v_booking.service_payload->'rooms','board',v_booking.service_payload->>'board','check_in',coalesce(v_booking.service_payload->>'check_in',v_booking.travel_start::text),'check_out',coalesce(v_booking.service_payload->>'check_out',v_booking.travel_end::text),'check_in_time',v_booking.service_payload->>'check_in_time','check_out_time',v_booking.service_payload->>'check_out_time'),
    'guests',public.safe_passengers_document_payload(v_booking.id),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_by','Kridiya Travel','settled',v_paid>=coalesce(v_booking.selling_price,v_booking.amount,0)));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('hotel_voucher',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc;
  return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_visa_confirmation_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then raise exception 'Booking or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('visa_confirmation:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='visa_confirmation' and payload->>'record_id'=p_booking_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),'visa',jsonb_build_object('country',v_booking.service_payload->>'country','visa_type',v_booking.service_payload->>'visa_type','entry_type',v_booking.service_payload->>'entry_type','stay_length',v_booking.service_payload->>'stay_length','application_number',v_booking.service_payload->>'application_number','enter_before',v_booking.service_payload->>'enter_before','issued_on',v_booking.service_payload->>'issued_on','status',coalesce(v_booking.service_payload->>'status',v_booking.status::text)),'applicants',public.safe_passengers_document_payload(v_booking.id),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_by','Kridiya Travel'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('visa_confirmation',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_visa_rejection_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_paid numeric; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then raise exception 'Booking or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('visa_rejection:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='visa_rejection' and payload->>'record_id'=p_booking_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  select coalesce(sum(amount),0) into v_paid from public.payments where booking_id=p_booking_id and payment_direction='customer_in' and status in ('received','proof_received');
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),'visa',jsonb_build_object('country',v_booking.service_payload->>'country','visa_type',v_booking.service_payload->>'visa_type','application_number',v_booking.service_payload->>'application_number','submitted_on',v_booking.service_payload->>'submitted_on','decided_on',v_booking.service_payload->>'decided_on','reason',v_booking.service_payload->>'reason'),'applicants',public.safe_passengers_document_payload(v_booking.id),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_by','Kridiya Travel','amount_paid',v_paid,'non_refundable',coalesce(nullif(v_booking.service_payload->>'non_refundable','')::numeric,0),'currency',v_booking.currency,'next_steps',coalesce(v_booking.service_payload->'next_steps','[]'::jsonb)));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('visa_rejection',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_cancellation_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_paid numeric; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')) then raise exception 'Booking or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('cancellation:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='cancellation' and payload->>'record_id'=p_booking_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  select coalesce(sum(amount),0) into v_paid from public.payments where booking_id=p_booking_id and payment_direction='customer_in' and status in ('received','proof_received');
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),'charges',coalesce(v_booking.service_payload->'cancellation_charges','[]'::jsonb),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_by','Kridiya Travel','amount_paid',v_paid,'currency',v_booking.currency,'cancelled_on',coalesce(v_booking.service_payload->>'cancelled_on',v_booking.updated_at::text),'reason',v_booking.service_payload->>'cancellation_reason','cancelled_by',v_booking.service_payload->>'cancelled_by'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('cancellation',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_refund_note_document(p_payment_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_payment public.payments%rowtype; v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('view_payments') or public.has_staff_permission('edit_payments')) then raise exception 'Payment or document permission required'; end if;
  select * into v_payment from public.payments where id=p_payment_id and payment_direction='customer_in'; if not found then raise exception 'Payment not found'; end if;
  select * into v_booking from public.bookings where id=v_payment.booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('refund_note:'||p_payment_id::text,0));
  select * into v_doc from public.documents where document_type='refund_note' and payload->>'record_id'=p_payment_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  v_payload:=jsonb_build_object('record_id',v_payment.id,'payment',jsonb_build_object('id',v_payment.id,'amount',v_payment.amount,'currency',v_payment.currency,'method',v_payment.method,'payment_reference',v_payment.payment_reference,'received_at',v_payment.received_at,'status',v_payment.status,'refund_amount',v_payment.refund_amount,'refund_reason',v_payment.refund_reason,'refund_requested_at',v_payment.refund_requested_at,'refund_approved_at',v_payment.refund_approved_at,'refund_completed_at',v_payment.refund_completed_at),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'booking',jsonb_build_object('booking_reference',v_booking.booking_reference,'service_type',v_booking.service_type,'route_or_destination',v_booking.route_or_destination)));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('refund_note',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_payment.refund_amount,v_payment.amount),v_payment.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_invoice_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_doc public.documents%rowtype; v_payments jsonb; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('view_payments') or public.has_staff_permission('edit_payments')) then raise exception 'Payment or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('invoice:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='invoice' and payload->>'record_id'=p_booking_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'amount',p.amount,'currency',p.currency,'method',p.method,'payment_reference',p.payment_reference,'received_at',coalesce(p.received_at,p.created_at),'status',p.status) order by p.created_at),'[]'::jsonb) into v_payments from public.payments p where p.booking_id=p_booking_id and p.payment_direction='customer_in' and p.status in ('received','proof_received');
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),'items',coalesce(v_booking.service_payload->'invoice_items','[]'::jsonb),'payments',v_payments,'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_booking.title),'email',v_customer.email,'phone',coalesce(v_customer.phone,v_customer.whatsapp)),'company_name','Kridiya Travel','issued_on',now(),'due_on',v_booking.service_payload->>'invoice_due_on','discount',coalesce(nullif(v_booking.service_payload->>'discount','')::numeric,0),'issued_by','Kridiya Travel'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('invoice',v_booking.enquiry_id,coalesce(v_customer.full_name,v_booking.title),v_customer.email,coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_corporate_confirmation_document(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_booking public.bookings%rowtype; v_customer public.customers%rowtype; v_account public.corporate_accounts%rowtype; v_doc public.documents%rowtype; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('view_corporates') or public.has_staff_permission('edit_corporates')) then raise exception 'Corporate or document permission required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id and archived_at is null; if not found then raise exception 'Booking not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('corporate_confirmation:'||p_booking_id::text,0));
  select * into v_doc from public.documents where document_type='corporate_confirmation' and payload->>'record_id'=p_booking_id::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  if v_booking.customer_id is not null then select * into v_customer from public.customers where id=v_booking.customer_id; end if;
  if v_booking.corporate_account_id is not null then select * into v_account from public.corporate_accounts where id=v_booking.corporate_account_id and archived_at is null; end if;
  v_payload:=jsonb_build_object('record_id',v_booking.id,'booking',public.safe_booking_document_payload(v_booking),'passengers',public.safe_passengers_document_payload(v_booking.id),'extras',jsonb_build_object('customer',jsonb_build_object('full_name',coalesce(v_customer.full_name,v_account.company_name,v_booking.title),'email',coalesce(v_customer.email,v_account.billing_email,v_account.accounts_email),'phone',coalesce(v_customer.phone,v_customer.whatsapp,v_account.phone)),'company_name',coalesce(v_account.company_name,'Kridiya Travel'),'issued_by','Kridiya Travel'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('corporate_confirmation',v_booking.enquiry_id,coalesce(v_customer.full_name,v_account.company_name,v_booking.title),coalesce(v_customer.email,v_account.billing_email,v_account.accounts_email),coalesce(v_booking.selling_price,v_booking.amount),v_booking.currency,v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

create or replace function public.generate_monthly_statement_document(p_corporate_account_id uuid,p_period_start date,p_period_end date)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_account public.corporate_accounts%rowtype; v_contact public.corporate_contacts%rowtype; v_doc public.documents%rowtype; v_lines jsonb; v_total numeric; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (public.has_staff_permission('generate_documents') or public.has_staff_permission('view_corporates') or public.has_staff_permission('edit_corporates') or public.has_staff_permission('view_reports')) then raise exception 'Corporate or document permission required'; end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then raise exception 'Invalid statement period'; end if;
  select * into v_account from public.corporate_accounts where id=p_corporate_account_id and archived_at is null; if not found then raise exception 'Corporate account not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('monthly_statement:'||p_corporate_account_id::text||':'||p_period_start::text||':'||p_period_end::text,0));
  select * into v_doc from public.documents where document_type='monthly_statement' and payload->>'record_id'=p_corporate_account_id::text and payload->'extras'->>'period_start'=p_period_start::text and payload->'extras'->>'period_end'=p_period_end::text order by created_at limit 1; if found then return public.document_rpc_result(v_doc); end if;
  select * into v_contact from public.corporate_contacts where corporate_account_id=p_corporate_account_id and active=true and is_accounts_contact=true order by created_at limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('date',b.created_at::date,'booking_reference',b.booking_reference,'service_type',b.service_type,'route_or_destination',b.route_or_destination,'invoiced',coalesce(b.selling_price,b.amount,0),'paid',coalesce((select sum(p.amount) from public.payments p where p.booking_id=b.id and p.payment_direction='customer_in' and p.status in ('received','proof_received')),0),'travellers',b.adults+b.children+b.infants) order by b.created_at,b.id),'[]'::jsonb),coalesce(sum(coalesce(b.selling_price,b.amount,0)),0) into v_lines,v_total from public.bookings b where b.corporate_account_id=p_corporate_account_id and b.archived_at is null and b.created_at::date between p_period_start and p_period_end;
  v_payload:=jsonb_build_object('record_id',v_account.id,'account',jsonb_build_object('company_name',v_account.company_name,'billing_contact',v_contact.full_name,'billing_email',coalesce(v_contact.email,v_account.accounts_email,v_account.billing_email),'account_reference',v_account.id),'lines',v_lines,'extras',jsonb_build_object('period_start',p_period_start,'period_end',p_period_end,'currency','AED','brought_forward',0,'issued_by','Kridiya Travel'));
  insert into public.documents(document_type,enquiry_id,customer_name,customer_email,amount_total,currency,payload,created_by) values('monthly_statement',null,v_account.company_name,coalesce(v_contact.email,v_account.accounts_email,v_account.billing_email),v_total,'AED',v_payload,auth.uid()) returning * into v_doc; return public.document_rpc_result(v_doc);
end;$function$;

revoke execute on function public.document_rpc_result(public.documents) from public, anon, authenticated;
revoke execute on function public.safe_booking_document_payload(public.bookings) from public, anon, authenticated;
revoke execute on function public.safe_passengers_document_payload(uuid) from public, anon, authenticated;
grant execute on function public.document_rpc_result(public.documents) to service_role;
grant execute on function public.safe_booking_document_payload(public.bookings) to service_role;
grant execute on function public.safe_passengers_document_payload(uuid) to service_role;

revoke execute on function public.generate_quotation_document(uuid) from public, anon;
revoke execute on function public.generate_eticket_document(uuid) from public, anon;
revoke execute on function public.generate_hotel_voucher_document(uuid) from public, anon;
revoke execute on function public.generate_visa_confirmation_document(uuid) from public, anon;
revoke execute on function public.generate_visa_rejection_document(uuid) from public, anon;
revoke execute on function public.generate_cancellation_document(uuid) from public, anon;
revoke execute on function public.generate_refund_note_document(uuid) from public, anon;
revoke execute on function public.generate_invoice_document(uuid) from public, anon;
revoke execute on function public.generate_corporate_confirmation_document(uuid) from public, anon;
revoke execute on function public.generate_monthly_statement_document(uuid,date,date) from public, anon;
grant execute on function public.generate_quotation_document(uuid), public.generate_eticket_document(uuid), public.generate_hotel_voucher_document(uuid), public.generate_visa_confirmation_document(uuid), public.generate_visa_rejection_document(uuid), public.generate_cancellation_document(uuid), public.generate_refund_note_document(uuid), public.generate_invoice_document(uuid), public.generate_corporate_confirmation_document(uuid), public.generate_monthly_statement_document(uuid,date,date) to authenticated, service_role;
