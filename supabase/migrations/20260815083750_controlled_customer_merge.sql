create or replace function public.merge_customer_records(
  p_source_customer_id uuid,
  p_target_customer_id uuid,
  p_source_expected_updated_at timestamptz,
  p_target_expected_updated_at timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  source_customer public.customers%rowtype;
  target_customer public.customers%rowtype;
  moved_bookings integer;
  moved_passengers integer;
  moved_payments integer;
  moved_corporate_contacts integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_customers') then
    raise exception 'Permission denied';
  end if;
  if p_source_customer_id = p_target_customer_id then
    raise exception 'Source and target customers must be different';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'A merge reason of at least 10 characters is required';
  end if;
  if p_source_expected_updated_at is null or p_target_expected_updated_at is null then
    raise exception 'Expected source and target versions are required';
  end if;

  perform id
  from public.customers
  where id in (p_source_customer_id, p_target_customer_id)
  order by id
  for update;

  select * into source_customer
  from public.customers where id = p_source_customer_id;
  select * into target_customer
  from public.customers where id = p_target_customer_id;

  if source_customer.id is null or source_customer.archived_at is not null then
    raise exception 'Active source customer not found';
  end if;
  if target_customer.id is null or target_customer.archived_at is not null then
    raise exception 'Active target customer not found';
  end if;
  if source_customer.updated_at <> p_source_expected_updated_at
     or target_customer.updated_at <> p_target_expected_updated_at then
    raise exception 'Customer changed after merge review. Reload both records.';
  end if;
  if source_customer.auth_user_id is not null
     and target_customer.auth_user_id is not null
     and source_customer.auth_user_id <> target_customer.auth_user_id then
    raise exception 'Customers belong to different authenticated users and cannot be merged';
  end if;

  update public.bookings
  set customer_id = p_target_customer_id, updated_at = now()
  where customer_id = p_source_customer_id;
  get diagnostics moved_bookings = row_count;

  update public.booking_passengers
  set customer_id = p_target_customer_id, updated_at = now()
  where customer_id = p_source_customer_id;
  get diagnostics moved_passengers = row_count;

  update public.payments
  set customer_id = p_target_customer_id, updated_at = now()
  where customer_id = p_source_customer_id;
  get diagnostics moved_payments = row_count;

  update public.corporate_contacts
  set customer_id = p_target_customer_id, updated_at = now()
  where customer_id = p_source_customer_id;
  get diagnostics moved_corporate_contacts = row_count;

  update public.customers
  set auth_user_id = coalesce(target_customer.auth_user_id, source_customer.auth_user_id),
      email = coalesce(target_customer.email, source_customer.email),
      phone = coalesce(target_customer.phone, source_customer.phone),
      whatsapp = coalesce(target_customer.whatsapp, source_customer.whatsapp),
      nationality = coalesce(target_customer.nationality, source_customer.nationality),
      notes = trim(both from concat_ws(
        E'\n',
        nullif(target_customer.notes, ''),
        case when nullif(source_customer.notes, '') is not null
          then 'Merged customer note: ' || source_customer.notes end
      )),
      updated_at = now()
  where id = p_target_customer_id;

  update public.customers
  set active = false,
      auth_user_id = null,
      archived_at = now(),
      notes = trim(both from concat_ws(
        E'\n',
        nullif(source_customer.notes, ''),
        'Merged into customer ' || p_target_customer_id::text || ': ' || trim(p_reason)
      )),
      updated_at = now()
  where id = p_source_customer_id;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(),
    'customer.merged',
    'customer',
    p_target_customer_id,
    jsonb_build_object(
      'source_customer_id', p_source_customer_id,
      'target_customer_id', p_target_customer_id,
      'reason', trim(p_reason),
      'moved_bookings', moved_bookings,
      'moved_passengers', moved_passengers,
      'moved_payments', moved_payments,
      'moved_corporate_contacts', moved_corporate_contacts
    )
  );

  return jsonb_build_object(
    'ok', true,
    'source_customer_id', p_source_customer_id,
    'target_customer_id', p_target_customer_id,
    'moved_bookings', moved_bookings,
    'moved_passengers', moved_passengers,
    'moved_payments', moved_payments,
    'moved_corporate_contacts', moved_corporate_contacts
  );
end;
$function$;

revoke execute on function public.merge_customer_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_customer_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;
