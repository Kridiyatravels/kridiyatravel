create or replace function public.create_operations_task(
  p_title text,
  p_task_type text default 'follow_up',
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_due_at timestamptz default null,
  p_priority text default 'normal',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_task_id uuid;
  v_title text := btrim(coalesce(p_title, ''));
  v_task_type text := lower(btrim(coalesce(p_task_type, 'follow_up')));
  v_entity_type text := lower(btrim(coalesce(p_entity_type, '')));
  v_priority text := lower(btrim(coalesce(p_priority, 'normal')));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if v_actor is null or not public.is_staff() then
    raise exception 'Staff access required';
  end if;

  if char_length(v_title) not between 2 and 220 then
    raise exception 'Task title must be between 2 and 220 characters';
  end if;

  if v_task_type not in (
    'follow_up',
    'appointment',
    'customer_call',
    'supplier_check',
    'payment',
    'documents',
    'ticketing',
    'visa',
    'corporate_approval',
    'payment_reminder',
    'document_request',
    'supplier_payment',
    'internal',
    'other'
  ) then
    raise exception 'Invalid task type';
  end if;

  if v_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'Invalid task priority';
  end if;

  if v_notes is not null and char_length(v_notes) > 5000 then
    raise exception 'Task notes must be 5000 characters or fewer';
  end if;

  if v_task_type = 'appointment' and p_due_at is null then
    raise exception 'Appointment date and time are required';
  end if;

  if v_entity_type in ('', 'general') then
    v_entity_type := null;
  end if;

  if v_entity_type is null and p_entity_id is not null then
    raise exception 'General tasks cannot have an entity ID';
  end if;

  if v_entity_type is not null and p_entity_id is null then
    raise exception 'Entity ID is required for linked tasks';
  end if;

  if v_entity_type is not null
    and v_entity_type not in ('booking', 'enquiry', 'customer', 'corporate_account') then
    raise exception 'Invalid task entity type';
  end if;

  if v_entity_type = 'booking' then
    if not (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
    ) then
      raise exception 'Booking task permission required';
    end if;

    if not exists (
      select 1
      from public.bookings b
      where b.id = p_entity_id
        and b.archived_at is null
    ) then
      raise exception 'Booking not found';
    end if;
  elsif v_entity_type = 'enquiry' then
    if not public.has_staff_permission('edit_enquiries') then
      raise exception 'Enquiry task permission required';
    end if;

    if not exists (
      select 1
      from public.enquiries e
      where e.id = p_entity_id
    ) then
      raise exception 'Enquiry not found';
    end if;
  elsif v_entity_type = 'customer' then
    if not public.has_staff_permission('edit_customers') then
      raise exception 'Customer task permission required';
    end if;

    if not exists (
      select 1
      from public.customers c
      where c.id = p_entity_id
        and c.archived_at is null
    ) then
      raise exception 'Customer not found';
    end if;
  elsif v_entity_type = 'corporate_account' then
    if not public.has_staff_permission('edit_corporates') then
      raise exception 'Corporate task permission required';
    end if;

    if not exists (
      select 1
      from public.corporate_accounts ca
      where ca.id = p_entity_id
        and ca.archived_at is null
    ) then
      raise exception 'Corporate account not found';
    end if;
  end if;

  insert into public.tasks_reminders (
    title,
    task_type,
    entity_type,
    entity_id,
    assigned_to,
    due_at,
    status,
    priority,
    notes,
    created_by
  )
  values (
    v_title,
    v_task_type,
    v_entity_type,
    p_entity_id,
    v_actor,
    p_due_at,
    'open',
    v_priority,
    v_notes,
    v_actor
  )
  returning id into v_task_id;

  if v_entity_type = 'booking' and p_due_at is not null then
    update public.bookings
    set
      follow_up_at = p_due_at,
      updated_at = clock_timestamp()
    where id = p_entity_id;
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
    case
      when v_entity_type = 'booking' and v_task_type = 'appointment'
        then 'booking.appointment_scheduled'
      when v_entity_type = 'booking'
        then 'booking.task_created'
      else 'task.created'
    end,
    coalesce(v_entity_type, 'task'),
    coalesce(p_entity_id, v_task_id),
    jsonb_build_object(
      'task_id', v_task_id,
      'title', v_title,
      'task_type', v_task_type,
      'entity_type', v_entity_type,
      'entity_id', p_entity_id,
      'assigned_to', v_actor,
      'due_at', p_due_at,
      'priority', v_priority
    )
  );

  return v_task_id;
end;
$function$;

comment on function public.create_operations_task(text, text, text, uuid, timestamptz, text, text)
is 'Creates general or booking/enquiry/customer/corporate-account tasks using admin-aware entity permission checks.';

revoke execute on function public.create_operations_task(text, text, text, uuid, timestamptz, text, text)
from public, anon;
grant execute on function public.create_operations_task(text, text, text, uuid, timestamptz, text, text)
to authenticated, service_role;
