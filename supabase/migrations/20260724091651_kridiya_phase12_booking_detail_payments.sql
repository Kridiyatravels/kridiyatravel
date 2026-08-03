-- Kridiya Phase 12: booking detail and payment workflow helpers.

create sequence if not exists public.payment_reference_seq start 1;

create or replace function public.next_payment_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n bigint;
begin
  n := nextval('public.payment_reference_seq');
  return 'PAY-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$$;

create or replace function public.get_operations_booking_detail(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
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
    'can_edit_bookings', public.has_staff_permission('edit_bookings')
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
$$;

create or replace function public.update_operations_booking_status(
  p_booking_id uuid,
  p_status public.booking_status,
  p_payment_status text,
  p_document_status text,
  p_supplier_reference text default null,
  p_staff_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
begin
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
$$;

create or replace function public.record_customer_payment(
  p_booking_id uuid,
  p_amount numeric,
  p_method text,
  p_status text default 'received',
  p_currency text default 'AED',
  p_payment_link text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_id uuid;
  v_ref text;
  v_booking_ref text;
begin
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
$$;

create or replace function public.record_supplier_payment(
  p_booking_id uuid,
  p_supplier_name text,
  p_amount_payable numeric,
  p_amount_paid numeric default 0,
  p_status text default 'pending',
  p_currency text default 'AED',
  p_supplier_reference text default null,
  p_due_date date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supplier_payment_id uuid;
  v_booking_ref text;
begin
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
$$;
