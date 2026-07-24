-- Booking payment receipt generation.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create sequence if not exists public.doc_receipt_seq;

create or replace function public.set_document_number()
returns trigger
language plpgsql
as $function$
declare
  yr text := to_char(now(), 'YYYY');
  prefix text;
  seq_name text;
begin
  if new.document_number is not null and new.document_number <> '' then
    return new;
  end if;
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
    else prefix := 'DOC'; seq_name := 'public.doc_invoice_seq';
  end case;
  new.document_number := prefix || '-' || yr || '-' || lpad(nextval(seq_name)::text, 4, '0');
  return new;
end;
$function$;

create or replace function public.generate_booking_receipt_document(
  p_booking_id uuid,
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;
