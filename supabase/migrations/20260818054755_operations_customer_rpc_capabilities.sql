create or replace function public.list_operations_customers(
  p_search text default null,
  p_limit integer default 100,
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null
)
returns table (
  id uuid,
  customer_type text,
  full_name text,
  email text,
  phone text,
  whatsapp text,
  nationality text,
  preferred_currency text,
  source text,
  active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  booking_count bigint,
  last_booking_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_normalized_phone text := public.normalize_customer_phone(p_search);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('view_customers') then
    raise exception 'Permission denied';
  end if;

  if (p_after_updated_at is null) <> (p_after_id is null) then
    raise exception 'Both customer pagination cursor values are required';
  end if;

  return query
  select
    c.id,
    c.customer_type,
    c.full_name,
    c.email,
    c.phone,
    c.whatsapp,
    c.nationality,
    c.preferred_currency,
    c.source,
    c.active,
    c.created_at,
    c.updated_at,
    coalesce(booking_summary.booking_count, 0)::bigint,
    booking_summary.last_booking_at
  from public.customers c
  left join lateral (
    select
      count(*)::bigint as booking_count,
      max(b.created_at) as last_booking_at
    from public.bookings b
    where b.customer_id = c.id
      and b.archived_at is null
  ) booking_summary on true
  where c.customer_type = 'individual'
    and c.archived_at is null
    and (
      v_search is null
      or strpos(lower(c.full_name), lower(v_search)) > 0
      or strpos(lower(coalesce(c.email, '')), lower(v_search)) > 0
      or strpos(lower(coalesce(c.phone, '')), lower(v_search)) > 0
      or strpos(lower(coalesce(c.whatsapp, '')), lower(v_search)) > 0
      or (
        v_normalized_phone is not null
        and (
          public.normalize_customer_phone(c.phone) = v_normalized_phone
          or public.normalize_customer_phone(c.whatsapp) = v_normalized_phone
        )
      )
    )
    and (
      p_after_updated_at is null
      or c.updated_at < p_after_updated_at
      or (c.updated_at = p_after_updated_at and c.id < p_after_id)
    )
  order by c.updated_at desc, c.id desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

create or replace function public.get_operations_customer_detail(
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_can_view_payments boolean;
  v_can_view_supplier_cost boolean;
  v_can_view_profit boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('view_customers') then
    raise exception 'Permission denied';
  end if;

  v_can_view_payments := public.has_staff_permission('view_payments');
  v_can_view_supplier_cost := public.has_staff_permission('view_supplier_cost');
  v_can_view_profit := public.has_staff_permission('view_profit');

  select jsonb_build_object(
    'customer', jsonb_build_object(
      'id', c.id,
      'customer_type', c.customer_type,
      'full_name', c.full_name,
      'email', c.email,
      'phone', c.phone,
      'whatsapp', c.whatsapp,
      'nationality', c.nationality,
      'preferred_currency', c.preferred_currency,
      'source', c.source,
      'notes', c.notes,
      'active', c.active,
      'created_at', c.created_at,
      'updated_at', c.updated_at
    ),
    'bookings', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', b.id,
            'booking_reference', b.booking_reference,
            'enquiry_id', b.enquiry_id,
            'title', b.title,
            'service_type', b.service_type,
            'route_or_destination', b.route_or_destination,
            'travel_start', b.travel_start,
            'travel_end', b.travel_end,
            'status', b.status,
            'payment_status', b.payment_status,
            'document_status', b.document_status,
            'selling_price', case
              when v_can_view_payments or v_can_view_profit
                then coalesce(b.selling_price, b.amount)
              else null
            end,
            'supplier_cost', case
              when v_can_view_supplier_cost then b.supplier_cost
              else null
            end,
            'gross_profit', case
              when v_can_view_profit
                then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0)
              else null
            end,
            'currency', b.currency,
            'created_at', b.created_at,
            'updated_at', b.updated_at
          )
          order by b.created_at desc, b.id desc
        )
        from public.bookings b
        where b.customer_id = c.id
          and b.archived_at is null
      ),
      '[]'::jsonb
    )
  )
  into v_result
  from public.customers c
  where c.id = p_customer_id
    and c.customer_type = 'individual'
    and c.archived_at is null;

  if v_result is null then
    raise exception 'Customer not found';
  end if;

  return v_result;
end;
$$;

create or replace function public.create_operations_customer(
  p_full_name text,
  p_email text,
  p_phone text,
  p_whatsapp text,
  p_nationality text,
  p_preferred_currency text,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_full_name text := trim(coalesce(p_full_name, ''));
  v_email text := public.normalize_customer_email(p_email);
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_whatsapp text := nullif(trim(coalesce(p_whatsapp, '')), '');
  v_normalized_phone text;
  v_currency text := upper(trim(coalesce(p_preferred_currency, 'AED')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (
    public.has_staff_permission('create_bookings')
    or public.has_staff_permission('edit_customers')
  ) then
    raise exception 'Permission denied';
  end if;

  if length(v_full_name) < 2 or length(v_full_name) > 160 then
    raise exception 'Customer name must be between 2 and 160 characters';
  end if;

  if v_email is not null and length(v_email) > 320 then
    raise exception 'Customer email must not exceed 320 characters';
  end if;

  if v_phone is not null and length(v_phone) > 40 then
    raise exception 'Customer phone must not exceed 40 characters';
  end if;

  if v_whatsapp is not null and length(v_whatsapp) > 40 then
    raise exception 'Customer WhatsApp number must not exceed 40 characters';
  end if;

  if nullif(trim(coalesce(p_nationality, '')), '') is not null
    and length(trim(p_nationality)) > 100 then
    raise exception 'Customer nationality must not exceed 100 characters';
  end if;

  if nullif(trim(coalesce(p_notes, '')), '') is not null
    and length(trim(p_notes)) > 5000 then
    raise exception 'Customer notes must not exceed 5000 characters';
  end if;

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Preferred currency must be a three-letter code';
  end if;

  v_normalized_phone := coalesce(
    public.normalize_customer_phone(v_phone),
    public.normalize_customer_phone(v_whatsapp)
  );

  if v_email is null and v_normalized_phone is null then
    raise exception 'Customer email or phone is required';
  end if;

  if exists (
    select 1
    from public.customers c
    where c.customer_type = 'individual'
      and c.archived_at is null
      and c.active = true
      and (
        (v_email is not null and public.normalize_customer_email(c.email) = v_email)
        or (
          v_normalized_phone is not null
          and (
            public.normalize_customer_phone(c.phone) = v_normalized_phone
            or public.normalize_customer_phone(c.whatsapp) = v_normalized_phone
          )
        )
      )
  ) then
    raise exception 'An active customer with this email or phone already exists';
  end if;

  insert into public.customers (
    customer_type,
    full_name,
    email,
    phone,
    whatsapp,
    nationality,
    preferred_currency,
    source,
    notes,
    active,
    created_by
  )
  values (
    'individual',
    v_full_name,
    v_email,
    v_phone,
    v_whatsapp,
    nullif(trim(coalesce(p_nationality, '')), ''),
    v_currency,
    'manual',
    nullif(trim(coalesce(p_notes, '')), ''),
    true,
    auth.uid()
  )
  returning id into v_customer_id;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    auth.uid(),
    'customer.created',
    'customer',
    v_customer_id,
    jsonb_build_object(
      'after', jsonb_build_object(
        'customer_type', 'individual',
        'full_name', v_full_name,
        'email', v_email,
        'phone', v_phone,
        'whatsapp', v_whatsapp,
        'nationality', nullif(trim(coalesce(p_nationality, '')), ''),
        'preferred_currency', v_currency,
        'source', 'manual',
        'notes', nullif(trim(coalesce(p_notes, '')), ''),
        'active', true
      )
    )
  );

  return v_customer_id;
end;
$$;

create or replace function public.update_operations_customer_details(
  p_customer_id uuid,
  p_full_name text,
  p_email text,
  p_phone text,
  p_whatsapp text,
  p_nationality text,
  p_preferred_currency text,
  p_notes text,
  p_active boolean,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.customers%rowtype;
  v_updated_at timestamptz;
  v_full_name text := trim(coalesce(p_full_name, ''));
  v_email text := public.normalize_customer_email(p_email);
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_whatsapp text := nullif(trim(coalesce(p_whatsapp, '')), '');
  v_normalized_phone text;
  v_currency text := upper(trim(coalesce(p_preferred_currency, 'AED')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_customers') then
    raise exception 'Permission denied';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected customer version is required';
  end if;

  if length(v_full_name) < 2 or length(v_full_name) > 160 then
    raise exception 'Customer name must be between 2 and 160 characters';
  end if;

  if v_email is not null and length(v_email) > 320 then
    raise exception 'Customer email must not exceed 320 characters';
  end if;

  if v_phone is not null and length(v_phone) > 40 then
    raise exception 'Customer phone must not exceed 40 characters';
  end if;

  if v_whatsapp is not null and length(v_whatsapp) > 40 then
    raise exception 'Customer WhatsApp number must not exceed 40 characters';
  end if;

  if nullif(trim(coalesce(p_nationality, '')), '') is not null
    and length(trim(p_nationality)) > 100 then
    raise exception 'Customer nationality must not exceed 100 characters';
  end if;

  if nullif(trim(coalesce(p_notes, '')), '') is not null
    and length(trim(p_notes)) > 5000 then
    raise exception 'Customer notes must not exceed 5000 characters';
  end if;

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Preferred currency must be a three-letter code';
  end if;

  if p_active is null then
    raise exception 'Customer active status is required';
  end if;

  v_normalized_phone := coalesce(
    public.normalize_customer_phone(v_phone),
    public.normalize_customer_phone(v_whatsapp)
  );

  if v_email is null and v_normalized_phone is null then
    raise exception 'Customer email or phone is required';
  end if;

  select c.*
  into v_before
  from public.customers c
  where c.id = p_customer_id
    and c.customer_type = 'individual'
    and c.archived_at is null;

  if not found then
    raise exception 'Customer not found';
  end if;

  if exists (
    select 1
    from public.customers c
    where c.id <> p_customer_id
      and c.customer_type = 'individual'
      and c.archived_at is null
      and c.active = true
      and (
        (v_email is not null and public.normalize_customer_email(c.email) = v_email)
        or (
          v_normalized_phone is not null
          and (
            public.normalize_customer_phone(c.phone) = v_normalized_phone
            or public.normalize_customer_phone(c.whatsapp) = v_normalized_phone
          )
        )
      )
  ) then
    raise exception 'An active customer with this email or phone already exists';
  end if;

  update public.customers
  set full_name = v_full_name,
      email = v_email,
      phone = v_phone,
      whatsapp = v_whatsapp,
      nationality = nullif(trim(coalesce(p_nationality, '')), ''),
      preferred_currency = v_currency,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      active = p_active,
      updated_at = clock_timestamp()
  where id = p_customer_id
    and customer_type = 'individual'
    and archived_at is null
    and updated_at = p_expected_updated_at
  returning updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Customer changed after this page was loaded. Reload and review the latest values.';
  end if;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    auth.uid(),
    'customer.details_updated',
    'customer',
    p_customer_id,
    jsonb_build_object(
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'before', jsonb_build_object(
        'full_name', v_before.full_name,
        'email', v_before.email,
        'phone', v_before.phone,
        'whatsapp', v_before.whatsapp,
        'nationality', v_before.nationality,
        'preferred_currency', v_before.preferred_currency,
        'notes', v_before.notes,
        'active', v_before.active
      ),
      'after', jsonb_build_object(
        'full_name', v_full_name,
        'email', v_email,
        'phone', v_phone,
        'whatsapp', v_whatsapp,
        'nationality', nullif(trim(coalesce(p_nationality, '')), ''),
        'preferred_currency', v_currency,
        'notes', nullif(trim(coalesce(p_notes, '')), ''),
        'active', p_active
      )
    )
  );

  return v_updated_at;
end;
$$;

revoke all on function public.list_operations_customers(text, integer, timestamptz, uuid) from public, anon;
revoke all on function public.get_operations_customer_detail(uuid) from public, anon;
revoke all on function public.create_operations_customer(text, text, text, text, text, text, text) from public, anon;
revoke all on function public.update_operations_customer_details(uuid, text, text, text, text, text, text, text, boolean, timestamptz) from public, anon;

grant execute on function public.list_operations_customers(text, integer, timestamptz, uuid) to authenticated, service_role;
grant execute on function public.get_operations_customer_detail(uuid) to authenticated, service_role;
grant execute on function public.create_operations_customer(text, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.update_operations_customer_details(uuid, text, text, text, text, text, text, text, boolean, timestamptz) to authenticated, service_role;
