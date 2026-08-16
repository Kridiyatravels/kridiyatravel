alter table public.corporate_desk_cases add column response_due_at timestamptz;
alter table public.corporate_desk_cases add column first_responded_at timestamptz;
update public.corporate_desk_cases set response_due_at=created_at+case when urgency='emergency'then interval '15 minutes' when urgency='urgent'then interval '2 hours' else interval '1 day' end;

create function public.set_corporate_desk_case_sla()returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='INSERT' and new.response_due_at is null then new.response_due_at:=coalesce(new.created_at,now())+case when new.urgency='emergency'then interval '15 minutes' when new.urgency='urgent'then interval '2 hours' else interval '1 day' end;end if;
 if tg_op='UPDATE' and old.first_responded_at is null and new.first_responded_at is null and nullif(btrim(coalesce(new.staff_response,'')),'')is not null then
  new.first_responded_at:=now();
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(auth.uid(),'corporate_desk_case_first_response','corporate_desk_case',new.id,jsonb_build_object('response_due_at',new.response_due_at,'responded_at',new.first_responded_at,'sla_breached',new.first_responded_at>new.response_due_at));
 end if;
 return new;
end$$;
create trigger corporate_desk_case_sla_before_write before insert or update on public.corporate_desk_cases for each row execute function public.set_corporate_desk_case_sla();
alter table public.corporate_desk_cases alter column response_due_at set not null;
create index corporate_desk_cases_sla_idx on public.corporate_desk_cases(response_due_at)where first_responded_at is null and status not in('resolved','closed');

drop function public.list_corporate_desk_cases(text,integer);
create function public.list_corporate_desk_cases(p_status text default null,p_limit integer default 200)returns table(id uuid,corporate_account_id uuid,company_name text,submitted_by uuid,booking_id uuid,quote_id uuid,quote_title text,category text,urgency text,subject text,description text,status text,assigned_to uuid,staff_response text,task_id uuid,resolved_at timestamptz,response_due_at timestamptz,first_responded_at timestamptz,sla_breached boolean,created_at timestamptz,updated_at timestamptz)language sql stable security definer set search_path=public,pg_temp as $$select c.id,c.corporate_account_id,a.company_name,c.submitted_by,c.booking_id,c.quote_id,q.title,c.category,c.urgency,c.subject,c.description,c.status,c.assigned_to,c.staff_response,c.task_id,c.resolved_at,c.response_due_at,c.first_responded_at,(c.first_responded_at is null and c.status not in('resolved','closed')and now()>c.response_due_at),c.created_at,c.updated_at from public.corporate_desk_cases c join public.corporate_accounts a on a.id=c.corporate_account_id left join public.quotes q on q.id=c.quote_id where public.is_staff()and(p_status is null or c.status=p_status)order by(c.first_responded_at is null and c.status not in('resolved','closed')and now()>c.response_due_at)desc,case c.urgency when'emergency'then 0 when'urgent'then 1 else 2 end,c.created_at desc limit least(greatest(coalesce(p_limit,200),1),500)$$;
revoke execute on function public.list_corporate_desk_cases(text,integer) from public,anon,authenticated;grant execute on function public.list_corporate_desk_cases(text,integer) to authenticated;
