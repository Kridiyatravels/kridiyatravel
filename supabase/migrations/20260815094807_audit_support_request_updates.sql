create or replace function public.audit_customer_support_request_update()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status or new.resolution is distinct from old.resolution or new.assigned_to is distinct from old.assigned_to then
    if new.status in ('resolved','closed') and new.resolved_at is null then new.resolved_at := now(); end if;
    if new.status not in ('resolved','closed') then new.resolved_at := null; end if;
    if new.status in ('resolved','closed','cancelled') and new.task_id is not null then
      update public.tasks_reminders set status=case when new.status='cancelled' then 'cancelled' else 'done' end,
        completed_at=case when new.status='cancelled' then null else now() end
      where id=new.task_id and status not in ('done','cancelled');
    end if;
    insert into public.audit_events(actor_user_id,target_user_id,event_type,entity_type,entity_id,metadata)
    values(auth.uid(),new.customer_user_id,'customer_support_request_updated','customer_support_request',new.id,
      jsonb_build_object('old_status',old.status,'new_status',new.status,'resolution_changed',new.resolution is distinct from old.resolution,'assigned_to',new.assigned_to));
  end if;
  return new;
end $$;

drop trigger if exists audit_customer_support_request_update on public.customer_support_requests;
create trigger audit_customer_support_request_update before update on public.customer_support_requests
for each row execute function public.audit_customer_support_request_update();

revoke execute on function public.audit_customer_support_request_update() from public, anon, authenticated;
grant execute on function public.audit_customer_support_request_update() to service_role;
