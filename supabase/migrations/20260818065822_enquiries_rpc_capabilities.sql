create or replace function public.list_operations_enquiries(
  p_search text default null,
  p_status text default null,
  p_pipeline_stage text default null,
  p_priority text default null,
  p_service_type text default null,
  p_limit integer default 100,
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null
)
returns table (
  id uuid,
  reference text,
  service_type text,
  status public.enquiry_status,
  full_name text,
  email text,
  phone text,
  summary text,
  source text,
  pipeline_stage text,
  priority text,
  assigned_staff_id uuid,
  lead_temperature text,
  lead_score integer,
  next_action text,
  next_action_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  last_activity_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_status text := nullif(lower(trim(coalesce(p_status, ''))), '');
  v_pipeline_stage text := nullif(lower(trim(coalesce(p_pipeline_stage, ''))), '');
  v_priority text := nullif(lower(trim(coalesce(p_priority, ''))), '');
  v_service_type text := nullif(lower(trim(coalesce(p_service_type, ''))), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('view_enquiries') then
    raise exception 'Permission denied';
  end if;

  if (p_after_updated_at is null) <> (p_after_id is null) then
    raise exception 'Both enquiry pagination cursor values are required';
  end if;

  if v_status is not null and v_status <> all (array[
    'received',
    'checking_availability',
    'quote_sent',
    'confirmed',
    'payment_pending',
    'booked',
    'documents_sent',
    'closed'
  ]) then
    raise exception 'Invalid enquiry status';
  end if;

  if v_pipeline_stage is not null and v_pipeline_stage <> all (array[
    'new',
    'contacted',
    'qualified',
    'checking_availability',
    'quote_preparation',
    'quote_sent',
    'follow_up',
    'accepted',
    'booking',
    'won',
    'lost',
    'not_eligible',
    'duplicate',
    'test_archived',
    'no_response'
  ]) then
    raise exception 'Invalid enquiry pipeline stage';
  end if;

  if v_priority is not null and v_priority <> all (array[
    'low', 'normal', 'high', 'urgent'
  ]) then
    raise exception 'Invalid enquiry priority';
  end if;

  if v_service_type is not null and v_service_type <> all (array[
    'flight', 'hotel', 'holiday', 'visa', 'umrah', 'cruise', 'other'
  ]) then
    raise exception 'Invalid enquiry service type';
  end if;

  return query
  select
    e.id,
    e.reference,
    e.service_type,
    e.status,
    e.full_name,
    e.email,
    e.phone,
    e.summary,
    coalesce(
      nullif(trim(e.last_touch_source), ''),
      nullif(trim(e.first_touch_source), ''),
      nullif(trim(e.utm_source), ''),
      nullif(trim(e.self_reported_source), ''),
      nullif(trim(e.details ->> 'source'), '')
    ) as source,
    e.pipeline_stage,
    e.priority,
    e.assigned_staff_id,
    e.lead_temperature,
    e.lead_score,
    e.next_action,
    e.next_action_at,
    e.created_at,
    e.updated_at,
    e.last_activity_at
  from public.enquiries e
  where (v_status is null or e.status::text = v_status)
    and (v_pipeline_stage is null or e.pipeline_stage = v_pipeline_stage)
    and (v_priority is null or e.priority = v_priority)
    and (v_service_type is null or e.service_type = v_service_type)
    and (
      v_search is null
      or strpos(lower(e.full_name), lower(v_search)) > 0
      or strpos(lower(e.email), lower(v_search)) > 0
      or strpos(lower(e.reference), lower(v_search)) > 0
    )
    and (
      p_after_updated_at is null
      or e.updated_at < p_after_updated_at
      or (e.updated_at = p_after_updated_at and e.id < p_after_id)
    )
  order by e.updated_at desc, e.id desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

create or replace function public.get_operations_enquiry_detail(
  p_enquiry_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('view_enquiries') then
    raise exception 'Permission denied';
  end if;

  select jsonb_build_object(
    'enquiry', to_jsonb(e),
    'linked_booking', (
      select jsonb_build_object(
        'id', b.id,
        'booking_reference', b.booking_reference,
        'title', b.title,
        'service_type', b.service_type,
        'status', b.status,
        'created_at', b.created_at,
        'updated_at', b.updated_at
      )
      from public.bookings b
      where b.enquiry_id = e.id
        and b.archived_at is null
      order by b.created_at desc, b.id desc
      limit 1
    )
  )
  into v_result
  from public.enquiries e
  where e.id = p_enquiry_id;

  if v_result is null then
    raise exception 'Enquiry not found';
  end if;

  return v_result;
end;
$$;

create or replace function public.update_operations_enquiry_lifecycle(
  p_enquiry_id uuid,
  p_status text,
  p_pipeline_stage text,
  p_priority text,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_pipeline_stage text := lower(trim(coalesce(p_pipeline_stage, '')));
  v_priority text := lower(trim(coalesce(p_priority, '')));
  v_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_enquiries') then
    raise exception 'Permission denied';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected enquiry version is required';
  end if;

  if v_status <> all (array[
    'received',
    'checking_availability',
    'quote_sent',
    'confirmed',
    'payment_pending',
    'booked',
    'documents_sent',
    'closed'
  ]) then
    raise exception 'Invalid enquiry status';
  end if;

  if v_pipeline_stage <> all (array[
    'new',
    'contacted',
    'qualified',
    'checking_availability',
    'quote_preparation',
    'quote_sent',
    'follow_up',
    'accepted',
    'booking',
    'won',
    'lost',
    'not_eligible',
    'duplicate',
    'test_archived',
    'no_response'
  ]) then
    raise exception 'Invalid enquiry pipeline stage';
  end if;

  if v_priority <> all (array[
    'low', 'normal', 'high', 'urgent'
  ]) then
    raise exception 'Invalid enquiry priority';
  end if;

  if not exists (
    select 1
    from public.enquiries e
    where e.id = p_enquiry_id
  ) then
    raise exception 'Enquiry not found';
  end if;

  update public.enquiries
  set status = v_status::public.enquiry_status,
      pipeline_stage = v_pipeline_stage,
      priority = v_priority,
      last_activity_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = p_enquiry_id
    and updated_at = p_expected_updated_at
  returning updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  -- The existing enquiries_audit_lifecycle_change trigger records the actor,
  -- changed fields, and before/after lifecycle values in public.audit_events.
  return v_updated_at;
end;
$$;

revoke all on function public.list_operations_enquiries(text, text, text, text, text, integer, timestamptz, uuid) from public, anon;
revoke all on function public.get_operations_enquiry_detail(uuid) from public, anon;
revoke all on function public.update_operations_enquiry_lifecycle(uuid, text, text, text, timestamptz) from public, anon;

grant execute on function public.list_operations_enquiries(text, text, text, text, text, integer, timestamptz, uuid) to authenticated, service_role;
grant execute on function public.get_operations_enquiry_detail(uuid) to authenticated, service_role;
grant execute on function public.update_operations_enquiry_lifecycle(uuid, text, text, text, timestamptz) to authenticated, service_role;
