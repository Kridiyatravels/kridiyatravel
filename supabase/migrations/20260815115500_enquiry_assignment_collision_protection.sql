-- Stage 3: prevent staff from silently taking enquiries already owned by a colleague.
create or replace function public.assign_enquiry(
  p_enquiry_id uuid,
  p_assigned_staff_id uuid,
  p_priority text default null
)
returns public.enquiries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := (select auth.uid());
  v_before public.enquiries;
  v_row public.enquiries;
  v_admin boolean;
begin
  if v_actor is null or not public.is_staff() then
    raise exception 'Staff access required';
  end if;
  v_admin := public.is_admin();

  select * into v_before
  from public.enquiries
  where id = p_enquiry_id
  for update;
  if not found then raise exception 'Enquiry not found'; end if;

  if p_assigned_staff_id is not null and not exists (
    select 1 from public.staff_profiles
    where user_id = p_assigned_staff_id and active = true
  ) then
    raise exception 'Assigned staff member is not active';
  end if;
  if p_priority is not null and p_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'Invalid priority';
  end if;

  -- Staff may claim unassigned work and release or update their own work.
  -- Reassigning a colleague's enquiry is an explicit owner/admin action.
  if not v_admin and v_before.assigned_staff_id is not null and v_before.assigned_staff_id <> v_actor then
    raise exception 'This enquiry is already assigned to another staff member';
  end if;
  if not v_admin and p_assigned_staff_id is not null and p_assigned_staff_id <> v_actor then
    raise exception 'Owner/admin access required to assign another staff member';
  end if;

  update public.enquiries
  set assigned_staff_id = p_assigned_staff_id,
      priority = coalesce(p_priority, priority),
      last_activity_at = now()
  where id = p_enquiry_id
  returning * into v_row;

  update public.tasks_reminders
  set assigned_to = p_assigned_staff_id,
      priority = coalesce(p_priority, priority),
      updated_at = now()
  where entity_type = 'enquiry'
    and entity_id = p_enquiry_id
    and status in ('open', 'snoozed');

  if p_assigned_staff_id is not null and p_assigned_staff_id is distinct from v_before.assigned_staff_id then
    insert into public.staff_notifications (
      recipient_id, audience, category, priority, title, body,
      entity_type, entity_id, action_url, dedupe_key, created_by
    ) values (
      p_assigned_staff_id, 'personal', 'assignment', coalesce(p_priority, v_row.priority),
      'Enquiry assigned to you', v_row.reference || ' - ' || v_row.full_name,
      'enquiry', v_row.id, 'admin.html?focus=' || v_row.id,
      'assignment:' || v_row.id || ':' || p_assigned_staff_id, v_actor
    ) on conflict (dedupe_key) where dedupe_key is not null do nothing;
  end if;

  insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_actor,
    'enquiry.assignment_updated',
    'enquiry',
    v_row.id,
    jsonb_build_object(
      'reference', v_row.reference,
      'previous_assigned_staff_id', v_before.assigned_staff_id,
      'assigned_staff_id', v_row.assigned_staff_id,
      'previous_priority', v_before.priority,
      'priority', v_row.priority,
      'admin_override', v_admin and v_before.assigned_staff_id is distinct from v_row.assigned_staff_id
    )
  );

  return v_row;
end;
$$;

revoke execute on function public.assign_enquiry(uuid, uuid, text) from public, anon;
grant execute on function public.assign_enquiry(uuid, uuid, text) to authenticated, service_role;

