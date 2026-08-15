create or replace function public.update_corporate_desk_case(p_case_id uuid,p_status text,p_staff_response text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_old text; v_status text:=lower(btrim(coalesce(p_status,'')));
begin
 if v_user is null or not public.is_staff() then raise exception 'Staff access required'; end if;
 if v_status not in ('acknowledged','in_progress','waiting_company','resolved','closed') then raise exception 'Invalid status'; end if;
 if v_status in ('waiting_company','resolved','closed') and char_length(btrim(coalesce(p_staff_response,'')))<3 then raise exception 'A staff response is required'; end if;
 select status into v_old from public.corporate_desk_cases where id=p_case_id for update; if not found then raise exception 'Case not found'; end if;
 update public.corporate_desk_cases set status=v_status,assigned_to=coalesce(assigned_to,v_user),staff_response=case when p_staff_response is null then staff_response else btrim(p_staff_response) end,resolved_at=case when v_status in ('resolved','closed') then now() else null end,updated_at=now() where id=p_case_id;
 if v_status in ('resolved','closed') then update public.tasks_reminders set status='done',completed_at=coalesce(completed_at,now()) where entity_type='corporate_desk_case' and entity_id=p_case_id and status<>'done'; end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values(v_user,'corporate_desk_case_updated','corporate_desk_case',p_case_id,jsonb_build_object('from_status',v_old,'to_status',v_status));
end $$;
revoke execute on function public.update_corporate_desk_case(uuid,text,text) from public,anon;
grant execute on function public.update_corporate_desk_case(uuid,text,text) to authenticated;
