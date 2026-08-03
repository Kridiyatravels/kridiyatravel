-- Kridiya Phase 11: staff booking creation helper for walk-in/WhatsApp/email customers without customer portal accounts.

alter table public.bookings alter column user_id drop not null;

create sequence if not exists public.booking_reference_seq start 1;

create or replace function public.next_booking_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n bigint;
begin
  n := nextval('public.booking_reference_seq');
  return 'KRI-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$$;

create or replace function public.create_operations_booking(
  p_title text,
  p_service_type public.booking_service_type,
  p_booking_kind text default 'individual',
  p_customer_name text default null,
  p_customer_email text default null,
  p_customer_phone text default null,
  p_corporate_account_id uuid default null,
  p_route_or_destination text default null,
  p_travel_start date default null,
  p_travel_end date default null,
  p_selling_price numeric default null,
  p_supplier_cost numeric default null,
  p_supplier_name text default null,
  p_portal_id uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
begin
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
$$;
