begin;

create or replace function private.sync_enquiry_next_action_task()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_automation_key text := 'enquiry-next-action:' || new.id;
  v_priority text := case
    when new.priority in ('low', 'normal', 'high', 'urgent') then new.priority
    else 'normal'
  end;
begin
  if new.status = 'closed'
     or nullif(trim(coalesce(new.next_action, '')), '') is null
     or new.next_action_at is null then
    update public.tasks_reminders
    set status = 'done',
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where automation_key = v_automation_key
      and status in ('open', 'snoozed');
    return new;
  end if;

  if tg_op = 'INSERT'
     or old.next_action is distinct from new.next_action
     or old.next_action_at is distinct from new.next_action_at
     or old.status = 'closed' then
    insert into public.tasks_reminders (
      title, task_type, entity_type, entity_id, assigned_to, due_at,
      status, priority, notes, automation_key
    ) values (
      trim(new.next_action), 'follow_up', 'enquiry', new.id,
      new.assigned_staff_id, new.next_action_at, 'open', v_priority,
      'Complete the enquiry next action and record the outcome.',
      v_automation_key
    )
    on conflict (automation_key) where automation_key is not null do update
    set title = excluded.title,
        assigned_to = excluded.assigned_to,
        due_at = excluded.due_at,
        status = 'open',
        priority = excluded.priority,
        notes = excluded.notes,
        completed_at = null,
        snoozed_until = null,
        updated_at = now();
  else
    update public.tasks_reminders
    set assigned_to = new.assigned_staff_id,
        priority = v_priority,
        updated_at = now()
    where automation_key = v_automation_key
      and status in ('open', 'snoozed');
  end if;

  return new;
end;
$$;

revoke all on function private.sync_enquiry_next_action_task() from public, anon, authenticated;

drop trigger if exists enquiries_sync_next_action_task on public.enquiries;
create trigger enquiries_sync_next_action_task
after insert or update of next_action, next_action_at, assigned_staff_id, priority, status
on public.enquiries
for each row execute function private.sync_enquiry_next_action_task();

-- Backfill current scheduled actions, including the Phase 2 production test.
insert into public.tasks_reminders (
  title, task_type, entity_type, entity_id, assigned_to, due_at,
  status, priority, notes, automation_key
)
select trim(e.next_action), 'follow_up', 'enquiry', e.id,
       e.assigned_staff_id, e.next_action_at, 'open',
       case when e.priority in ('low', 'normal', 'high', 'urgent') then e.priority else 'normal' end,
       'Complete the enquiry next action and record the outcome.',
       'enquiry-next-action:' || e.id
from public.enquiries e
where e.status <> 'closed'
  and nullif(trim(coalesce(e.next_action, '')), '') is not null
  and e.next_action_at is not null
on conflict (automation_key) where automation_key is not null do update
set title = excluded.title,
    assigned_to = excluded.assigned_to,
    due_at = excluded.due_at,
    priority = excluded.priority,
    notes = excluded.notes,
    updated_at = now();

comment on function private.sync_enquiry_next_action_task() is
  'Synchronizes each enquiry CRM next action with its role-aware operations work-queue task.';

commit;
