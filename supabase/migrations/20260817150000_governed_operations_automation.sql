begin;

create table public.automation_definitions(
 id uuid primary key default gen_random_uuid(), automation_key text not null unique,
 name text not null, description text not null, version integer not null default 1 check(version>0),
 status text not null default 'enabled' check(status in('enabled','disabled')),
 schedule text not null, owner_user_id uuid not null references auth.users(id),
 max_retries integer not null default 3 check(max_retries between 0 and 10),
 disabled_reason text, last_changed_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.automation_definition_versions(
 id uuid primary key default gen_random_uuid(), automation_id uuid not null references public.automation_definitions(id) on delete cascade,
 version integer not null, snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 change_note text not null, changed_by uuid references auth.users(id), created_at timestamptz not null default now(),
 unique(automation_id,version)
);
create table public.automation_runs(
 id uuid primary key default gen_random_uuid(), automation_id uuid not null references public.automation_definitions(id) on delete cascade,
 run_key text not null, trigger_type text not null check(trigger_type in('scheduled','manual','retry')),
 status text not null check(status in('running','succeeded','failed','skipped','dry_run')),
 definition_version integer not null, attempt integer not null default 1 check(attempt between 1 and 20),
 dry_run boolean not null default false, result jsonb not null default '{}' check(jsonb_typeof(result)='object'),
 error_message text, triggered_by uuid references auth.users(id), started_at timestamptz not null default now(), completed_at timestamptz,
 unique(automation_id,run_key,attempt)
);
create index automation_runs_monitor_idx on public.automation_runs(automation_id,started_at desc);
alter table public.automation_definitions enable row level security;
alter table public.automation_definition_versions enable row level security;
alter table public.automation_runs enable row level security;
revoke all on public.automation_definitions,public.automation_definition_versions,public.automation_runs from public,anon,authenticated;
grant all on public.automation_definitions,public.automation_definition_versions,public.automation_runs to service_role;

insert into public.automation_definitions(automation_key,name,description,schedule,owner_user_id,last_changed_by)
select 'operations-follow-up','Operations follow-up controls','Creates deduplicated SLA, stale-enquiry and quote follow-up work.','*/5 * * * *',sr.user_id,sr.user_id
from public.staff_roles sr join public.staff_profiles sp on sp.user_id=sr.user_id and sp.active
where sr.role::text='owner' order by sr.created_at limit 1;
insert into public.automation_definition_versions(automation_id,version,snapshot,change_note,changed_by)
select id,version,jsonb_build_object('automation_key',automation_key,'name',name,'description',description,'schedule',schedule,'status',status,'owner_user_id',owner_user_id,'max_retries',max_retries),'Initial governed definition',last_changed_by
from public.automation_definitions where automation_key='operations-follow-up';

create function private.preview_operations_automation() returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'sla_alert_candidates',(select count(*) from public.enquiries e where e.first_response_at is null and e.sla_first_response_due_at<now() and e.status<>'closed' and not exists(select 1 from public.staff_notifications n where n.dedupe_key='sla-first-response:'||e.id)),
  'followup_task_candidates',(select count(*) from public.enquiries e where e.quote_sent_at<=now()-interval'24 hours' and e.status in('quote_sent','payment_pending') and not exists(select 1 from public.tasks_reminders t where t.automation_key='quote-followup-24h:'||e.id)),
  'stale_alert_candidates',(select count(*) from public.enquiries e where e.status in('received','checking_availability') and coalesce(e.last_activity_at,e.created_at)<=now()-interval'24 hours' and not exists(select 1 from public.quotes q where q.enquiry_id=e.id) and not exists(select 1 from public.staff_notifications n where n.dedupe_key='stale-enquiry-24h:'||e.id)),
  'previewed_at',now())
$$;
revoke all on function private.preview_operations_automation() from public,anon,authenticated;

create function private.run_governed_operations_automation(p_trigger text default 'scheduled',p_actor uuid default null,p_run_key text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_def public.automation_definitions%rowtype;v_run uuid;v_key text;v_attempt integer;v_result jsonb;
begin
 select*into v_def from public.automation_definitions where automation_key='operations-follow-up' for update;
 if not found then raise exception'Governed automation definition missing';end if;
 v_key:=coalesce(nullif(btrim(coalesce(p_run_key,'')),''),'scheduled:'||to_char(date_trunc('minute',now())-make_interval(mins=>extract(minute from now())::integer%5),'YYYYMMDDHH24MI'));
 select coalesce(max(attempt),0)+1 into v_attempt from public.automation_runs where automation_id=v_def.id and run_key=v_key;
 if v_def.status='disabled' then
  insert into public.automation_runs(automation_id,run_key,trigger_type,status,definition_version,attempt,result,triggered_by,completed_at) values(v_def.id,v_key,p_trigger,'skipped',v_def.version,v_attempt,jsonb_build_object('reason','disabled','disabled_reason',v_def.disabled_reason),p_actor,now()) returning id into v_run;return v_run;
 end if;
 insert into public.automation_runs(automation_id,run_key,trigger_type,status,definition_version,attempt,triggered_by) values(v_def.id,v_key,p_trigger,'running',v_def.version,v_attempt,p_actor) returning id into v_run;
 begin
  v_result:=private.refresh_operations_automations();
  update public.automation_runs set status='succeeded',result=v_result,completed_at=now() where id=v_run;
 exception when others then
  update public.automation_runs set status='failed',error_message=left(sqlerrm,4000),completed_at=now() where id=v_run;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(p_actor,'automation_run.failed','automation_run',v_run,jsonb_build_object('automation_id',v_def.id,'run_key',v_key,'attempt',v_attempt));
 end;
 return v_run;
end$$;
revoke all on function private.run_governed_operations_automation(text,uuid,text) from public,anon,authenticated;

create function public.list_governed_automations(p_limit integer default 100)returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select case when public.is_admin() then coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]')else'[]'::jsonb end from(
  select d.*,(select coalesce(jsonb_agg(to_jsonb(r) order by r.started_at desc),'[]')from(select id,run_key,trigger_type,status,definition_version,attempt,dry_run,result,error_message,triggered_by,started_at,completed_at from public.automation_runs where automation_id=d.id order by started_at desc limit 20)r)runs
  from public.automation_definitions d order by d.updated_at desc limit least(greatest(coalesce(p_limit,100),1),300))x
$$;
create function public.preview_governed_automation(p_automation_id uuid)returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$declare v_actor uuid:=auth.uid();v_def public.automation_definitions%rowtype;v_result jsonb;v_run uuid;begin if v_actor is null or not public.is_admin()then raise exception'Owner/admin access required';end if;select*into v_def from public.automation_definitions where id=p_automation_id;if not found then raise exception'Automation not found';end if;v_result:=private.preview_operations_automation();insert into public.automation_runs(automation_id,run_key,trigger_type,status,definition_version,dry_run,result,triggered_by,completed_at)values(v_def.id,'dry-run:'||gen_random_uuid(),'manual','dry_run',v_def.version,true,v_result,v_actor,now())returning id into v_run;insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'automation.previewed','automation_definition',v_def.id,jsonb_build_object('run_id',v_run,'version',v_def.version));return v_result||jsonb_build_object('run_id',v_run);end$$;
create function public.run_governed_automation(p_automation_id uuid,p_override_reason text)returns uuid language plpgsql security definer set search_path=public,pg_temp as $$declare v_actor uuid:=auth.uid();v_def public.automation_definitions%rowtype;v_run uuid;begin if v_actor is null or not public.is_admin()then raise exception'Owner/admin access required';end if;if char_length(btrim(coalesce(p_override_reason,'')))<10 then raise exception'Manual override reason is required';end if;select*into v_def from public.automation_definitions where id=p_automation_id;if not found then raise exception'Automation not found';end if;v_run:=private.run_governed_operations_automation('manual',v_actor,'manual:'||gen_random_uuid());insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'automation.manual_override','automation_definition',v_def.id,jsonb_build_object('run_id',v_run,'reason',btrim(p_override_reason)));return v_run;end$$;
create function public.configure_governed_automation(p_automation_id uuid,p_enabled boolean,p_owner_user_id uuid,p_max_retries integer,p_change_note text)returns void language plpgsql security definer set search_path=public,pg_temp as $$declare v_actor uuid:=auth.uid();v_def public.automation_definitions%rowtype;v_version integer;begin if v_actor is null or not public.is_admin()then raise exception'Owner/admin access required';end if;if char_length(btrim(coalesce(p_change_note,'')))<10 then raise exception'Change note is required';end if;if p_max_retries not between 0 and 10 then raise exception'Invalid retry limit';end if;if not exists(select 1 from public.staff_profiles where user_id=p_owner_user_id and active)then raise exception'Owner must be active staff';end if;select*into v_def from public.automation_definitions where id=p_automation_id for update;if not found then raise exception'Automation not found';end if;v_version:=v_def.version+1;update public.automation_definitions set status=case when p_enabled then'enabled'else'disabled'end,owner_user_id=p_owner_user_id,max_retries=p_max_retries,disabled_reason=case when p_enabled then null else btrim(p_change_note)end,version=v_version,last_changed_by=v_actor,updated_at=now()where id=p_automation_id;insert into public.automation_definition_versions(automation_id,version,snapshot,change_note,changed_by)select id,version,jsonb_build_object('automation_key',automation_key,'name',name,'description',description,'schedule',schedule,'status',status,'owner_user_id',owner_user_id,'max_retries',max_retries,'disabled_reason',disabled_reason),btrim(p_change_note),v_actor from public.automation_definitions where id=p_automation_id;insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'automation.configured','automation_definition',p_automation_id,jsonb_build_object('from_version',v_def.version,'to_version',v_version,'enabled',p_enabled,'change_note',btrim(p_change_note)));end$$;
create function public.retry_governed_automation_run(p_run_id uuid,p_reason text)returns uuid language plpgsql security definer set search_path=public,pg_temp as $$declare v_actor uuid:=auth.uid();v_old public.automation_runs%rowtype;v_def public.automation_definitions%rowtype;v_run uuid;begin if v_actor is null or not public.is_admin()then raise exception'Owner/admin access required';end if;if char_length(btrim(coalesce(p_reason,'')))<10 then raise exception'Retry reason is required';end if;select*into v_old from public.automation_runs where id=p_run_id;if not found or v_old.status<>'failed'then raise exception'Only failed runs can be retried';end if;select*into v_def from public.automation_definitions where id=v_old.automation_id;if v_old.attempt>=v_def.max_retries+1 then raise exception'Retry limit reached';end if;v_run:=private.run_governed_operations_automation('retry',v_actor,v_old.run_key);insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'automation.retry_requested','automation_definition',v_def.id,jsonb_build_object('prior_run_id',p_run_id,'new_run_id',v_run,'reason',btrim(p_reason)));return v_run;end$$;
revoke execute on function public.list_governed_automations(integer),public.preview_governed_automation(uuid),public.run_governed_automation(uuid,text),public.configure_governed_automation(uuid,boolean,uuid,integer,text),public.retry_governed_automation_run(uuid,text) from public,anon;
grant execute on function public.list_governed_automations(integer),public.preview_governed_automation(uuid),public.run_governed_automation(uuid,text),public.configure_governed_automation(uuid,boolean,uuid,integer,text),public.retry_governed_automation_run(uuid,text) to authenticated,service_role;

do $$declare v_job bigint;begin if exists(select 1 from pg_extension where extname='pg_cron')then select jobid into v_job from cron.job where jobname='kridiya-operations-automation'limit 1;if v_job is not null then perform cron.unschedule(v_job);end if;perform cron.schedule('kridiya-operations-automation','*/5 * * * *',$job$select private.run_governed_operations_automation('scheduled',null,null)$job$);end if;end$$;

commit;
