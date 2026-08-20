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
  v_transition_at timestamptz := clock_timestamp();
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
      qualified_at = case
        when v_status = 'checking_availability'
          then coalesce(qualified_at, v_transition_at)
        else qualified_at
      end,
      quote_sent_at = case
        when v_status = 'quote_sent'
          then coalesce(quote_sent_at, v_transition_at)
        else quote_sent_at
      end,
      booking_confirmed_at = case
        when v_status in ('confirmed', 'booked')
          then coalesce(booking_confirmed_at, v_transition_at)
        else booking_confirmed_at
      end,
      last_activity_at = v_transition_at,
      updated_at = v_transition_at
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

comment on function public.update_operations_enquiry_lifecycle(uuid, text, text, text, timestamptz) is
  'Permission-gated enquiry lifecycle update with optimistic locking. Sets qualified_at, quote_sent_at, or booking_confirmed_at on the matching status transition only when that milestone is still null.';

revoke all on function public.update_operations_enquiry_lifecycle(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function public.update_operations_enquiry_lifecycle(uuid, text, text, text, timestamptz) to authenticated, service_role;
