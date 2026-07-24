-- Booking passenger and document workflow for staff booking files.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.get_operations_booking_detail(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
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
      'lpo_required', ca.lpo_required
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
    'can_edit_documents', public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings')
  )
  from public.bookings b
  left join public.customers c on c.id = b.customer_id
  left join public.corporate_accounts ca on ca.id = b.corporate_account_id
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    );
$function$;

create or replace function public.record_booking_passenger(
  p_booking_id uuid,
  p_passenger_name text,
  p_passenger_type text default 'adult',
  p_nationality text default null,
  p_date_of_birth date default null,
  p_passport_number text default null,
  p_passport_expiry date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;

create or replace function public.delete_booking_passenger(p_passenger_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;

create or replace function public.record_booking_document(
  p_booking_id uuid,
  p_document_type text,
  p_file_name text,
  p_external_reference text default null,
  p_storage_path text default null,
  p_visible_to_customer boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;

create or replace function public.delete_booking_document(p_document_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
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
$function$;
