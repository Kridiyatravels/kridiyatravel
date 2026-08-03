-- Connect corporate accounts and contacts to staff booking creation.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

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
  p_notes text default null,
  p_corporate_contact_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_customer_id uuid;
  v_booking_id uuid;
  v_reference text;
  v_contact_account_id uuid;
begin
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
$function$;

drop function if exists public.list_operations_bookings(integer);

create function public.list_operations_bookings(limit_count integer default 200)
returns table(
  id uuid,
  booking_reference text,
  enquiry_id uuid,
  customer_id uuid,
  corporate_account_id uuid,
  corporate_contact_id uuid,
  corporate_company_name text,
  corporate_contact_name text,
  booking_kind text,
  service_type public.booking_service_type,
  title text,
  route_or_destination text,
  travel_start date,
  travel_end date,
  status public.booking_status,
  payment_status text,
  document_status text,
  supplier_name text,
  supplier_cost numeric,
  selling_price numeric,
  gross_profit numeric,
  currency text,
  priority text,
  follow_up_at timestamp with time zone,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
language sql
security definer
set search_path to 'public'
as $function$
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
  limit greatest(1, least(limit_count, 500));
$function$;
