-- Enquiry lifecycle changes and their audit evidence must commit atomically.
create or replace function public.audit_enquiry_lifecycle_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  changed_fields text[] := '{}'::text[];
begin
  if old.status is distinct from new.status then
    changed_fields := array_append(changed_fields, 'status');
  end if;
  if old.pipeline_stage is distinct from new.pipeline_stage then
    changed_fields := array_append(changed_fields, 'pipeline_stage');
  end if;
  if old.assigned_staff_id is distinct from new.assigned_staff_id then
    changed_fields := array_append(changed_fields, 'assigned_staff_id');
  end if;
  if old.priority is distinct from new.priority then
    changed_fields := array_append(changed_fields, 'priority');
  end if;

  if cardinality(changed_fields) = 0 then
    return new;
  end if;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(),
    'enquiry.lifecycle_updated',
    'enquiry',
    new.id,
    jsonb_build_object(
      'reference', new.reference,
      'changed_fields', changed_fields,
      'before', jsonb_build_object(
        'status', old.status,
        'pipeline_stage', old.pipeline_stage,
        'assigned_staff_id', old.assigned_staff_id,
        'priority', old.priority
      ),
      'after', jsonb_build_object(
        'status', new.status,
        'pipeline_stage', new.pipeline_stage,
        'assigned_staff_id', new.assigned_staff_id,
        'priority', new.priority
      )
    )
  );

  return new;
end;
$function$;

drop trigger if exists enquiries_audit_lifecycle_change on public.enquiries;
create trigger enquiries_audit_lifecycle_change
after update of status, pipeline_stage, assigned_staff_id, priority
on public.enquiries
for each row execute function public.audit_enquiry_lifecycle_change();

revoke execute on function public.audit_enquiry_lifecycle_change()
  from public, anon, authenticated;
