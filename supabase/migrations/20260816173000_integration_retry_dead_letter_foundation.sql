alter table public.integration_operations
  add column if not exists idempotency_key text,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists max_attempts integer not null default 3,
  add column if not exists retry_state text not null default 'not_applicable',
  add column if not exists next_retry_at timestamptz,
  add column if not exists request_context jsonb not null default '{}'::jsonb,
  add column if not exists result_metadata jsonb not null default '{}'::jsonb,
  add column if not exists dead_letter_at timestamptz,
  add column if not exists dead_letter_reason text,
  add column if not exists operational_exception_id uuid references public.operational_exceptions(id) on delete set null,
  add column if not exists recovered_at timestamptz,
  add column if not exists recovered_by uuid references auth.users(id) on delete set null,
  add column if not exists recovery_note text;

alter table public.integration_operations
  add constraint integration_operations_attempt_count_check check (attempt_count between 0 and 100),
  add constraint integration_operations_max_attempts_check check (max_attempts between 1 and 10),
  add constraint integration_operations_retry_state_check check (retry_state in ('not_applicable','queued','running','retry_scheduled','dead_letter','manual_retry','abandoned','recovered')),
  add constraint integration_operations_request_context_object_check check (jsonb_typeof(request_context) = 'object'),
  add constraint integration_operations_result_metadata_object_check check (jsonb_typeof(result_metadata) = 'object');

create unique index integration_operations_idempotency_uidx
  on public.integration_operations(integration, operation, idempotency_key)
  where idempotency_key is not null;
create index integration_operations_recovery_queue_idx
  on public.integration_operations(retry_state, next_retry_at, created_at desc)
  where retry_state in ('queued','retry_scheduled','dead_letter','manual_retry');

comment on column public.integration_operations.request_context is
  'Non-secret operational context only. Never store credentials, tokens, payment data, or full customer payloads.';

create function public.queue_integration_operation(
  p_integration text, p_operation text, p_idempotency_key text,
  p_entity_type text default null, p_entity_id uuid default null,
  p_request_context jsonb default '{}'::jsonb, p_max_attempts integer default 3
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null or not public.is_staff() then raise exception 'Staff access required'; end if;
  if char_length(btrim(coalesce(p_integration,''))) not between 2 and 80 then raise exception 'Integration must be 2 to 80 characters'; end if;
  if char_length(btrim(coalesce(p_operation,''))) not between 2 and 120 then raise exception 'Operation must be 2 to 120 characters'; end if;
  if char_length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 200 then raise exception 'Idempotency key must be 8 to 200 characters'; end if;
  if p_max_attempts not between 1 and 10 then raise exception 'Maximum attempts must be 1 to 10'; end if;
  if jsonb_typeof(coalesce(p_request_context,'{}')) <> 'object' then raise exception 'Request context must be a JSON object'; end if;
  insert into public.integration_operations(integration,operation,idempotency_key,entity_type,entity_id,actor_user_id,status,retry_state,request_context,max_attempts)
  values(lower(btrim(p_integration)),lower(btrim(p_operation)),btrim(p_idempotency_key),nullif(lower(btrim(coalesce(p_entity_type,''))),''),p_entity_id,v_actor,'processing','queued',coalesce(p_request_context,'{}'),p_max_attempts)
  on conflict(integration,operation,idempotency_key) where idempotency_key is not null do update set idempotency_key=excluded.idempotency_key
  returning id into v_id;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_actor,'integration_operation.queued','integration_operation',v_id,jsonb_build_object('integration',lower(btrim(p_integration)),'operation',lower(btrim(p_operation)),'max_attempts',p_max_attempts));
  return v_id;
end$$;

create function public.record_integration_attempt(
  p_operation_id uuid, p_succeeded boolean, p_http_status integer default null,
  p_error text default null, p_result_metadata jsonb default '{}'::jsonb
) returns text language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_op public.integration_operations%rowtype; v_attempt integer; v_state text; v_owner uuid; v_exception uuid; v_task uuid;
begin
  if jsonb_typeof(coalesce(p_result_metadata,'{}')) <> 'object' then raise exception 'Result metadata must be a JSON object'; end if;
  select * into v_op from public.integration_operations where id=p_operation_id for update;
  if not found then raise exception 'Integration operation not found'; end if;
  if v_op.retry_state in ('abandoned','recovered') then raise exception 'Integration operation is already closed'; end if;
  v_attempt:=v_op.attempt_count+1;
  if p_succeeded then
    v_state:='recovered';
    update public.integration_operations set attempt_count=v_attempt,status='succeeded',retry_state=v_state,http_status=p_http_status,last_error=null,result_metadata=coalesce(p_result_metadata,'{}'),next_retry_at=null,completed_at=now(),recovered_at=now() where id=p_operation_id;
    if v_op.operational_exception_id is not null then
      update public.operational_exceptions set status='resolved',resolution='Integration completed successfully after governed retry.',recovery_action='Successful retry confirmed by the integration worker.',resolved_at=now(),updated_at=now() where id=v_op.operational_exception_id and status not in('resolved','closed');
      update public.tasks_reminders set status='done',completed_at=now() where id=(select task_id from public.operational_exceptions where id=v_op.operational_exception_id);
    end if;
  elsif v_attempt < v_op.max_attempts then
    v_state:='retry_scheduled';
    update public.integration_operations set attempt_count=v_attempt,status='failed',retry_state=v_state,http_status=p_http_status,last_error=left(coalesce(p_error,'Unspecified integration failure'),4000),result_metadata=coalesce(p_result_metadata,'{}'),next_retry_at=now()+make_interval(mins=>least(60,power(2,v_attempt)::integer)),completed_at=now() where id=p_operation_id;
  else
    v_state:='dead_letter';
    select sr.user_id into v_owner from public.staff_roles sr join public.staff_profiles sp on sp.user_id=sr.user_id and sp.active where sr.role::text='owner' order by sr.created_at limit 1;
    v_owner:=coalesce(v_op.actor_user_id,v_owner);
    if v_owner is null then raise exception 'No active staff owner is available for dead-letter escalation'; end if;
    insert into public.operational_exceptions(category,severity,urgency,status,title,description,entity_type,entity_id,owner_user_id,response_due_at,resolution_due_at,evidence,created_by)
    values('integration','high','urgent','open','Dead letter: '||left(v_op.integration||' / '||v_op.operation,160),'Integration exhausted '||v_op.max_attempts||' governed attempts. Latest error: '||left(coalesce(p_error,'Unspecified integration failure'),1000),'integration',p_operation_id,v_owner,now()+interval '30 minutes',now()+interval '4 hours',jsonb_build_array(jsonb_build_object('integration_operation_id',p_operation_id,'http_status',p_http_status)),v_owner)
    returning id into v_exception;
    insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,assigned_to,notes,created_by,automation_key)
    values('Recover integration: '||left(v_op.integration||' / '||v_op.operation,155),'follow_up','integration_operation',p_operation_id,now()+interval '30 minutes','urgent',v_owner,'Review the dead letter, retry safely or abandon with a documented reason.',v_owner,'integration-dead-letter:'||p_operation_id) returning id into v_task;
    update public.operational_exceptions set task_id=v_task where id=v_exception;
    update public.integration_operations set attempt_count=v_attempt,status='failed',retry_state=v_state,http_status=p_http_status,last_error=left(coalesce(p_error,'Unspecified integration failure'),4000),result_metadata=coalesce(p_result_metadata,'{}'),next_retry_at=null,dead_letter_at=now(),dead_letter_reason=left(coalesce(p_error,'Attempts exhausted'),4000),operational_exception_id=v_exception,completed_at=now() where id=p_operation_id;
  end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_op.actor_user_id,'integration_operation.attempt_recorded','integration_operation',p_operation_id,jsonb_build_object('attempt',v_attempt,'max_attempts',v_op.max_attempts,'succeeded',p_succeeded,'retry_state',v_state,'http_status',p_http_status,'operational_exception_id',v_exception));
  return v_state;
end$$;

create function public.list_integration_recovery_queue(p_retry_state text default null,p_limit integer default 300)
returns setof public.integration_operations language sql stable security definer set search_path=public,pg_temp as $$
  select x.* from public.integration_operations x
  where public.is_staff() and x.retry_state <> 'not_applicable' and (p_retry_state is null or x.retry_state=p_retry_state)
  order by case x.retry_state when 'dead_letter' then 0 when 'manual_retry' then 1 when 'retry_scheduled' then 2 else 3 end, coalesce(x.next_retry_at,x.created_at),x.created_at desc
  limit least(greatest(coalesce(p_limit,300),1),500)
$$;

create function public.recover_integration_operation(p_operation_id uuid,p_action text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_op public.integration_operations%rowtype; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if v_actor is null or not public.is_staff() then raise exception 'Staff access required'; end if;
  if v_action not in('retry','abandon','recovered') then raise exception 'Invalid recovery action'; end if;
  if char_length(btrim(coalesce(p_note,''))) not between 10 and 1000 then raise exception 'Recovery note must be 10 to 1000 characters'; end if;
  select * into v_op from public.integration_operations where id=p_operation_id for update;
  if not found then raise exception 'Integration operation not found'; end if;
  if v_action='retry' then
    update public.integration_operations set status='processing',retry_state='manual_retry',next_retry_at=now(),completed_at=null,recovered_by=v_actor,recovery_note=btrim(p_note) where id=p_operation_id;
  elsif v_action='abandon' then
    update public.integration_operations set retry_state='abandoned',next_retry_at=null,recovered_at=now(),recovered_by=v_actor,recovery_note=btrim(p_note) where id=p_operation_id;
  else
    update public.integration_operations set retry_state='recovered',status='succeeded',next_retry_at=null,recovered_at=now(),recovered_by=v_actor,recovery_note=btrim(p_note),completed_at=coalesce(completed_at,now()) where id=p_operation_id;
  end if;
  if v_op.operational_exception_id is not null and v_action in('abandon','recovered') then
    update public.operational_exceptions set status='resolved',resolution=case when v_action='abandon' then 'Integration operation intentionally abandoned: ' else 'Integration operation manually confirmed recovered: ' end||btrim(p_note),resolved_at=now(),updated_at=now() where id=v_op.operational_exception_id and status not in('resolved','closed');
    update public.tasks_reminders set status='done',completed_at=now() where id=(select task_id from public.operational_exceptions where id=v_op.operational_exception_id);
  end if;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_actor,'integration_operation.recovery_action','integration_operation',p_operation_id,jsonb_build_object('action',v_action,'note',btrim(p_note),'from_state',v_op.retry_state));
end$$;

revoke execute on function public.queue_integration_operation(text,text,text,text,uuid,jsonb,integer) from public,anon;
revoke execute on function public.list_integration_recovery_queue(text,integer) from public,anon;
revoke execute on function public.recover_integration_operation(uuid,text,text) from public,anon;
revoke execute on function public.record_integration_attempt(uuid,boolean,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.queue_integration_operation(text,text,text,text,uuid,jsonb,integer) to authenticated;
grant execute on function public.list_integration_recovery_queue(text,integer) to authenticated;
grant execute on function public.recover_integration_operation(uuid,text,text) to authenticated;
grant execute on function public.record_integration_attempt(uuid,boolean,integer,text,jsonb) to service_role;
