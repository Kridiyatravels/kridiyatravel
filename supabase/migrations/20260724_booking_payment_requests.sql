-- Booking payment request document generation.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.generate_booking_payment_request_document(
  p_booking_id uuid,
  p_amount_requested numeric default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;
