create or replace function public.update_operations_enquiry_crm_details(
  p_enquiry_id uuid,
  p_lead_temperature text,
  p_lead_score integer,
  p_next_action text,
  p_next_action_at timestamptz,
  p_lost_reason text,
  p_estimated_booking_value numeric,
  p_estimated_gross_profit numeric,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.enquiries%rowtype;
  v_lead_temperature text := nullif(lower(btrim(coalesce(p_lead_temperature, ''))), '');
  v_next_action text := nullif(btrim(coalesce(p_next_action, '')), '');
  v_lost_reason text := nullif(lower(btrim(coalesce(p_lost_reason, ''))), '');
  v_updated_at timestamptz;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_enquiries') then
    raise exception 'Permission denied';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected enquiry version is required';
  end if;

  if v_lead_temperature is not null
    and v_lead_temperature not in ('cold', 'warm', 'hot') then
    raise exception 'Invalid lead temperature';
  end if;

  if p_lead_score is not null and (p_lead_score < 0 or p_lead_score > 100) then
    raise exception 'Lead score must be between 0 and 100';
  end if;

  if v_next_action is not null and char_length(v_next_action) > 500 then
    raise exception 'Next action must be 500 characters or fewer';
  end if;

  if p_next_action_at is not null and v_next_action is null then
    raise exception 'Next action is required when a due time is provided';
  end if;

  if v_lost_reason is not null and v_lost_reason not in (
    'price',
    'no_response',
    'dates_changed',
    'not_available',
    'booked_elsewhere',
    'duplicate',
    'invalid_enquiry',
    'visa_ineligible',
    'payment_issue',
    'other'
  ) then
    raise exception 'Invalid lost reason';
  end if;

  if p_estimated_booking_value is not null and (
    p_estimated_booking_value::text in ('NaN', 'Infinity', '-Infinity')
    or p_estimated_booking_value < 0
  ) then
    raise exception 'Estimated booking value must be a finite non-negative amount';
  end if;

  if p_estimated_gross_profit is not null
    and p_estimated_gross_profit::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'Estimated gross profit must be finite';
  end if;

  select e.*
  into v_before
  from public.enquiries e
  where e.id = p_enquiry_id;

  if not found then
    raise exception 'Enquiry not found';
  end if;

  update public.enquiries e
  set
    lead_temperature = v_lead_temperature,
    lead_score = p_lead_score,
    next_action = v_next_action,
    next_action_at = p_next_action_at,
    lost_reason = v_lost_reason,
    estimated_booking_value = p_estimated_booking_value,
    estimated_gross_profit = p_estimated_gross_profit,
    last_activity_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where e.id = p_enquiry_id
    and e.updated_at = p_expected_updated_at
  returning e.updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'enquiry.crm_updated',
    'enquiry',
    p_enquiry_id,
    jsonb_build_object(
      'reference', v_before.reference,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'before', jsonb_build_object(
        'lead_temperature', v_before.lead_temperature,
        'lead_score', v_before.lead_score,
        'next_action', v_before.next_action,
        'next_action_at', v_before.next_action_at,
        'lost_reason', v_before.lost_reason,
        'estimated_booking_value', v_before.estimated_booking_value,
        'estimated_gross_profit', v_before.estimated_gross_profit
      ),
      'after', jsonb_build_object(
        'lead_temperature', v_lead_temperature,
        'lead_score', p_lead_score,
        'next_action', v_next_action,
        'next_action_at', p_next_action_at,
        'lost_reason', v_lost_reason,
        'estimated_booking_value', p_estimated_booking_value,
        'estimated_gross_profit', p_estimated_gross_profit
      )
    )
  );

  return v_updated_at;
end;
$function$;

comment on function public.update_operations_enquiry_crm_details(
  uuid, text, integer, text, timestamptz, text, numeric, numeric, timestamptz
)
is 'Updates the explicitly supported enquiry CRM fields with edit_enquiries authorization, validation, optimistic locking, and before/after audit evidence.';


create or replace function public.record_operations_enquiry_first_response(
  p_enquiry_id uuid,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.enquiries%rowtype;
  v_recorded_at timestamptz := clock_timestamp();
  v_updated_at timestamptz;
  v_completed_task_count integer := 0;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_enquiries') then
    raise exception 'Permission denied';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected enquiry version is required';
  end if;

  select e.*
  into v_before
  from public.enquiries e
  where e.id = p_enquiry_id;

  if not found then
    raise exception 'Enquiry not found';
  end if;

  if v_before.updated_at <> p_expected_updated_at then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  if v_before.first_response_at is not null then
    raise exception 'First response has already been recorded';
  end if;

  update public.enquiries e
  set
    first_response_at = v_recorded_at,
    pipeline_stage = case
      when e.pipeline_stage = 'new' then 'contacted'
      else e.pipeline_stage
    end,
    last_activity_at = v_recorded_at,
    updated_at = v_recorded_at
  where e.id = p_enquiry_id
    and e.updated_at = p_expected_updated_at
  returning e.updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  update public.tasks_reminders t
  set
    status = 'done',
    completed_at = coalesce(t.completed_at, v_recorded_at),
    snoozed_until = null,
    updated_at = v_recorded_at
  where t.entity_type = 'enquiry'
    and t.entity_id = p_enquiry_id
    and t.task_type = 'follow_up'
    and t.automation_key is null
    and t.title = 'First response: ' || v_before.reference
    and t.status in ('open', 'snoozed');

  get diagnostics v_completed_task_count = row_count;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'enquiry.first_response_recorded',
    'enquiry',
    p_enquiry_id,
    jsonb_build_object(
      'reference', v_before.reference,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'completed_task_count', v_completed_task_count,
      'before', jsonb_build_object(
        'first_response_at', v_before.first_response_at,
        'pipeline_stage', v_before.pipeline_stage,
        'last_activity_at', v_before.last_activity_at
      ),
      'after', jsonb_build_object(
        'first_response_at', v_recorded_at,
        'pipeline_stage', case
          when v_before.pipeline_stage = 'new' then 'contacted'
          else v_before.pipeline_stage
        end,
        'last_activity_at', v_recorded_at
      ),
      'unchanged_milestones', jsonb_build_object(
        'qualified_at', v_before.qualified_at,
        'quote_sent_at', v_before.quote_sent_at,
        'booking_confirmed_at', v_before.booking_confirmed_at
      )
    )
  );

  return v_updated_at;
end;
$function$;

comment on function public.record_operations_enquiry_first_response(uuid, timestamptz)
is 'Records the first-response SLA milestone and completes open enquiry follow-up tasks. Qualification, quote-sent, and booking-confirmed milestones are intentionally unchanged.';


create or replace function public.close_operations_enquiry(
  p_enquiry_id uuid,
  p_lost_reason text,
  p_note text,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.enquiries%rowtype;
  v_lost_reason text := nullif(lower(btrim(coalesce(p_lost_reason, ''))), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_pipeline_stage text;
  v_note_id uuid;
  v_updated_at timestamptz;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_enquiries') then
    raise exception 'Permission denied';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected enquiry version is required';
  end if;

  if v_lost_reason is null or v_lost_reason not in (
    'price',
    'no_response',
    'dates_changed',
    'not_available',
    'booked_elsewhere',
    'duplicate',
    'invalid_enquiry',
    'visa_ineligible',
    'payment_issue',
    'other'
  ) then
    raise exception 'A valid lost reason is required';
  end if;

  if v_note is null or char_length(v_note) > 2000 then
    raise exception 'Close note must be between 1 and 2000 characters';
  end if;

  select e.*
  into v_before
  from public.enquiries e
  where e.id = p_enquiry_id;

  if not found then
    raise exception 'Enquiry not found';
  end if;

  if v_before.updated_at <> p_expected_updated_at then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  if v_before.status = 'closed' then
    raise exception 'Enquiry is already closed';
  end if;

  v_pipeline_stage := case v_lost_reason
    when 'invalid_enquiry' then 'test_archived'
    when 'duplicate' then 'duplicate'
    when 'visa_ineligible' then 'not_eligible'
    when 'no_response' then 'no_response'
    else 'lost'
  end;

  update public.enquiries e
  set
    status = 'closed'::public.enquiry_status,
    pipeline_stage = v_pipeline_stage,
    lost_reason = v_lost_reason,
    next_action = null,
    next_action_at = null,
    last_activity_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where e.id = p_enquiry_id
    and e.updated_at = p_expected_updated_at
  returning e.updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Enquiry changed after this page was loaded. Reload and review the latest values.';
  end if;

  insert into public.enquiry_notes (
    enquiry_id,
    note,
    created_by
  )
  values (
    p_enquiry_id,
    v_note,
    v_actor
  )
  returning id into v_note_id;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    case
      when v_lost_reason = 'invalid_enquiry' then 'enquiry.test_archived'
      else 'enquiry.closed_lost'
    end,
    'enquiry',
    p_enquiry_id,
    jsonb_build_object(
      'reference', v_before.reference,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'note_id', v_note_id,
      'before', jsonb_build_object(
        'status', v_before.status,
        'pipeline_stage', v_before.pipeline_stage,
        'lost_reason', v_before.lost_reason,
        'next_action', v_before.next_action,
        'next_action_at', v_before.next_action_at
      ),
      'after', jsonb_build_object(
        'status', 'closed',
        'pipeline_stage', v_pipeline_stage,
        'lost_reason', v_lost_reason,
        'next_action', null,
        'next_action_at', null
      )
    )
  );

  return v_updated_at;
end;
$function$;

comment on function public.close_operations_enquiry(uuid, text, text, timestamptz)
is 'Closes an enquiry with a validated loss outcome, aligned terminal pipeline stage, required note, optimistic locking, and audit evidence.';


revoke execute on function public.update_operations_enquiry_crm_details(
  uuid, text, integer, text, timestamptz, text, numeric, numeric, timestamptz
) from public, anon;
revoke execute on function public.record_operations_enquiry_first_response(uuid, timestamptz)
from public, anon;
revoke execute on function public.close_operations_enquiry(uuid, text, text, timestamptz)
from public, anon;

grant execute on function public.update_operations_enquiry_crm_details(
  uuid, text, integer, text, timestamptz, text, numeric, numeric, timestamptz
) to authenticated, service_role;
grant execute on function public.record_operations_enquiry_first_response(uuid, timestamptz)
to authenticated, service_role;
grant execute on function public.close_operations_enquiry(uuid, text, text, timestamptz)
to authenticated, service_role;
