drop function public.list_operations_tasks(integer);

create function public.list_operations_tasks(p_limit integer default 300)
returns table (
  id uuid,
  title text,
  task_type text,
  entity_type text,
  entity_id uuid,
  entity_reference text,
  entity_title text,
  assigned_to uuid,
  assigned_to_name text,
  due_at timestamptz,
  status text,
  priority text,
  notes text,
  snoozed_until timestamptz,
  escalated_at timestamptz,
  escalation_reason text,
  created_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz,
  due_bucket text,
  action_url text
)
language sql
security definer
set search_path = ''
as $function$
  select
    t.id,
    t.title,
    t.task_type,
    t.entity_type,
    t.entity_id,
    coalesce(
      e.reference,
      b.booking_reference,
      p.payment_reference,
      d.document_number,
      left(t.entity_id::text, 8)
    ) as entity_reference,
    coalesce(
      e.full_name || ' - ' || e.summary,
      b.title,
      p.payment_reference,
      d.customer_name,
      initcap(coalesce(t.entity_type, 'general'))
    ) as entity_title,
    t.assigned_to,
    sp.full_name,
    t.due_at,
    t.status,
    t.priority,
    t.notes,
    t.snoozed_until,
    t.escalated_at,
    t.escalation_reason,
    t.created_at,
    t.updated_at,
    t.completed_at,
    case
      when t.status = 'done' then 'completed'
      when t.status = 'snoozed' and t.snoozed_until > now() then 'snoozed'
      when t.due_at is null then 'no_due_date'
      when t.due_at < now() then 'overdue'
      when t.due_at::date = current_date then 'today'
      when t.due_at < now() + interval '8 days' then 'next_7_days'
      else 'later'
    end as due_bucket,
    case t.entity_type
      when 'enquiry' then 'admin.html?focus=' || t.entity_id
      when 'booking' then 'booking-detail.html?id=' || t.entity_id
      when 'payment' then 'payments.html?focus=' || t.entity_id
      when 'document' then 'documents.html?focus=' || t.entity_id
      else 'dashboard.html'
    end as action_url
  from public.tasks_reminders t
  left join public.enquiries e
    on t.entity_type = 'enquiry' and e.id = t.entity_id
  left join public.bookings b
    on t.entity_type = 'booking' and b.id = t.entity_id
  left join public.payments p
    on t.entity_type = 'payment' and p.id = t.entity_id
  left join public.documents d
    on t.entity_type = 'document' and d.id = t.entity_id
  left join public.staff_profiles sp
    on sp.user_id = t.assigned_to
  where public.is_staff()
    and (
      public.is_admin()
      or t.assigned_to is null
      or t.assigned_to = auth.uid()
    )
  order by
    case when t.escalated_at is not null and t.status <> 'done' then 0 else 1 end,
    case t.priority
      when 'urgent' then 0
      when 'high' then 1
      when 'normal' then 2
      else 3
    end,
    t.due_at nulls last,
    t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 300), 1000));
$function$;

comment on function public.list_operations_tasks(integer)
is 'Lists the caller-visible task queue and includes updated_at for optimistic locking.';

revoke execute on function public.list_operations_tasks(integer)
from public, anon;
grant execute on function public.list_operations_tasks(integer)
to authenticated, service_role;


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
    if not exists (
      select 1
      from public.staff_permissions sp
      where sp.user_id = v_actor
        and (sp.create_bookings or sp.edit_bookings)
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
    if not exists (
      select 1
      from public.staff_permissions sp
      where sp.user_id = v_actor
        and sp.edit_enquiries
    ) then
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
    if not exists (
      select 1
      from public.staff_permissions sp
      where sp.user_id = v_actor
        and sp.edit_customers
    ) then
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
    if not exists (
      select 1
      from public.staff_permissions sp
      where sp.user_id = v_actor
        and sp.edit_corporates
    ) then
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
is 'Creates general or booking/enquiry/customer/corporate-account tasks with entity-specific staff permission checks.';

revoke execute on function public.create_operations_task(text, text, text, uuid, timestamptz, text, text)
from public, anon;
grant execute on function public.create_operations_task(text, text, text, uuid, timestamptz, text, text)
to authenticated, service_role;


create or replace function public.create_booking_task(
  p_booking_id uuid,
  p_title text,
  p_task_type text default 'follow_up',
  p_due_at timestamptz default null,
  p_priority text default 'normal',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return public.create_operations_task(
    p_title,
    p_task_type,
    'booking',
    p_booking_id,
    p_due_at,
    p_priority,
    p_notes
  );
end;
$function$;

comment on function public.create_booking_task(uuid, text, text, timestamptz, text, text)
is 'Backward-compatible booking-task wrapper around create_operations_task.';

revoke execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text)
from public, anon;
grant execute on function public.create_booking_task(uuid, text, text, timestamptz, text, text)
to authenticated, service_role;


create or replace function public.update_operations_task(
  p_task_id uuid,
  p_status text,
  p_assigned_to uuid,
  p_due_at timestamptz,
  p_snoozed_until timestamptz,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.tasks_reminders%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_snoozed_until timestamptz;
  v_updated_at timestamptz;
begin
  if v_actor is null or not public.is_staff() then
    raise exception 'Staff access required';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected task version is required';
  end if;

  if v_status not in ('open', 'done', 'cancelled', 'snoozed') then
    raise exception 'Invalid task status';
  end if;

  if v_status = 'snoozed' then
    if p_snoozed_until is null or p_snoozed_until <= clock_timestamp() then
      raise exception 'A future snooze time is required';
    end if;
    v_snoozed_until := p_snoozed_until;
  else
    v_snoozed_until := null;
  end if;

  if p_assigned_to is not null and not exists (
    select 1
    from public.staff_profiles sp
    where sp.user_id = p_assigned_to
      and sp.active
  ) then
    raise exception 'Assigned staff member must be active';
  end if;

  select t.*
  into v_before
  from public.tasks_reminders t
  where t.id = p_task_id;

  if not found then
    raise exception 'Task not found';
  end if;

  if not public.is_admin()
    and v_before.assigned_to is not null
    and v_before.assigned_to <> v_actor then
    raise exception 'Task update permission required';
  end if;

  if p_assigned_to is distinct from v_before.assigned_to
    and not public.is_admin() then
    raise exception 'Owner/admin access required to reassign tasks';
  end if;

  update public.tasks_reminders t
  set
    status = v_status,
    assigned_to = p_assigned_to,
    due_at = p_due_at,
    snoozed_until = v_snoozed_until,
    completed_at = case
      when v_status = 'done' then coalesce(t.completed_at, clock_timestamp())
      else null
    end,
    updated_at = clock_timestamp()
  where t.id = p_task_id
    and t.updated_at = p_expected_updated_at
  returning t.updated_at into v_updated_at;

  if v_updated_at is null then
    raise exception 'Task changed after this page was loaded. Reload and review the latest values.';
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
    'task.updated',
    'task',
    p_task_id,
    jsonb_build_object(
      'linked_entity_type', v_before.entity_type,
      'linked_entity_id', v_before.entity_id,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at,
      'before', jsonb_build_object(
        'status', v_before.status,
        'assigned_to', v_before.assigned_to,
        'due_at', v_before.due_at,
        'snoozed_until', v_before.snoozed_until,
        'completed_at', v_before.completed_at
      ),
      'after', jsonb_build_object(
        'status', v_status,
        'assigned_to', p_assigned_to,
        'due_at', p_due_at,
        'snoozed_until', v_snoozed_until,
        'completed_at', case
          when v_status = 'done' then coalesce(v_before.completed_at, v_updated_at)
          else null
        end
      )
    )
  );

  return v_updated_at;
end;
$function$;

comment on function public.update_operations_task(uuid, text, uuid, timestamptz, timestamptz, timestamptz)
is 'Updates task status, assignment, due date, and snooze state with ownership rules, optimistic locking, and audit logging.';

revoke execute on function public.update_operations_task(uuid, text, uuid, timestamptz, timestamptz, timestamptz)
from public, anon;
grant execute on function public.update_operations_task(uuid, text, uuid, timestamptz, timestamptz, timestamptz)
to authenticated, service_role;
