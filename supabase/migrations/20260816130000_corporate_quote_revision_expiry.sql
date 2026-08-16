alter table public.corporate_desk_cases add column quote_id uuid references public.quotes(id) on delete set null;
create index corporate_desk_cases_quote_idx on public.corporate_desk_cases(quote_id,created_at desc) where quote_id is not null;
create unique index corporate_desk_cases_open_quote_revision_uidx on public.corporate_desk_cases(quote_id) where quote_id is not null and category='amendment' and status not in('resolved','closed');

create or replace function public.request_my_corporate_quote_revision(p_quote_id uuid,p_message text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();v_quote public.quotes%rowtype;v_booking public.bookings%rowtype;v_case uuid;v_task uuid;
begin
 if v_actor is null then raise exception 'Authentication required';end if;
 if char_length(btrim(coalesce(p_message,''))) not between 10 and 2000 then raise exception 'Revision request must be 10 to 2000 characters';end if;
 select q.* into v_quote from public.quotes q where q.id=p_quote_id for update;
 if not found then raise exception 'Quote revision access denied';end if;
 select b.* into v_booking from public.bookings b join public.corporate_portal_members m on m.corporate_account_id=b.corporate_account_id and m.user_id=v_actor and m.status='active' and m.can_approve_quotes where (b.id=v_quote.booking_id or(v_quote.booking_id is null and b.enquiry_id=v_quote.enquiry_id))and b.archived_at is null and b.booking_kind='corporate' limit 1;
 if not found then raise exception 'Quote revision access denied';end if;
 if v_quote.status<>'sent' then raise exception 'Only sent quotes can be revised';end if;
 if v_quote.valid_until is not null and v_quote.valid_until<=now() then raise exception 'This quote has expired. Ask Kridiya for a fresh option';end if;
 if exists(select 1 from public.corporate_desk_cases where quote_id=p_quote_id and category='amendment' and status not in('resolved','closed'))then raise exception 'A revision request is already open for this quote';end if;
 insert into public.corporate_desk_cases(corporate_account_id,submitted_by,booking_id,quote_id,category,urgency,subject,description)values(v_booking.corporate_account_id,v_actor,v_booking.id,p_quote_id,'amendment','normal','Quote revision: '||left(v_quote.title,150),btrim(p_message))returning id into v_case;
 insert into public.tasks_reminders(title,task_type,entity_type,entity_id,due_at,priority,notes,created_by,automation_key)values('Corporate quote revision: '||left(v_quote.title,140),'follow_up','corporate_desk_case',v_case,now()+interval '1 day','normal','Review the linked corporate quote and release a revised option.',v_actor,'corporate-quote-revision:'||v_case)returning id into v_task;
 update public.corporate_desk_cases set task_id=v_task where id=v_case;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'corporate_portal.quote_revision_requested','quote',p_quote_id,jsonb_build_object('case_id',v_case,'task_id',v_task,'booking_id',v_booking.id,'corporate_account_id',v_booking.corporate_account_id,'quote_version',v_quote.quote_version));
 return v_case;
end$$;

create or replace function public.list_my_corporate_quotes(p_corporate_account_id uuid default null,p_limit integer default 100)returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
select coalesce(jsonb_agg(x.payload order by x.created_at desc),'[]'::jsonb) from(select q.created_at,jsonb_build_object('id',q.id,'booking_id',b.id,'booking_reference',b.booking_reference,'booking_title',b.title,'service_type',b.service_type,'route_or_destination',b.route_or_destination,'title',q.title,'description',q.description,'price_amount',q.price_amount,'currency',q.currency,'valid_until',q.valid_until,'terms',q.terms,'status',case when q.status='sent' and q.valid_until is not null and q.valid_until<=now()then'expired' else q.status::text end,'responded_at',q.responded_at,'created_at',q.created_at,'updated_at',q.updated_at,'can_approve',m.can_approve_quotes,'revision_pending',exists(select 1 from public.corporate_desk_cases c where c.quote_id=q.id and c.category='amendment' and c.status not in('resolved','closed')))payload from public.quotes q join public.bookings b on(b.id=q.booking_id or(q.booking_id is null and b.enquiry_id=q.enquiry_id))and b.archived_at is null and b.booking_kind='corporate' join public.corporate_portal_members m on m.corporate_account_id=b.corporate_account_id and m.user_id=(select auth.uid())and m.status='active' where(select auth.uid())is not null and(p_corporate_account_id is null or b.corporate_account_id=p_corporate_account_id)order by q.created_at desc limit greatest(1,least(coalesce(p_limit,100),200)))x;
$$;

create or replace function public.respond_my_corporate_quote(p_quote_id uuid,p_status text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_quote public.quotes%rowtype;v_booking public.bookings%rowtype;v_actor uuid:=auth.uid();v_policy public.corporate_travel_policies%rowtype;v_required integer:=1;v_count integer;v_final boolean:=false;v_decision text;
begin if v_actor is null then raise exception 'Authentication required';end if;if p_status not in('accepted','declined') then raise exception 'Quote can only be accepted or declined';end if;
 select q.* into v_quote from public.quotes q where q.id=p_quote_id for update;if not found then raise exception 'Quote approval access denied';end if;
 select b.* into v_booking from public.bookings b join public.corporate_portal_members m on m.corporate_account_id=b.corporate_account_id and m.user_id=v_actor and m.status='active' and m.can_approve_quotes where (b.id=v_quote.booking_id or(v_quote.booking_id is null and b.enquiry_id=v_quote.enquiry_id))and b.archived_at is null and b.booking_kind='corporate' limit 1;if not found then raise exception 'Quote approval access denied';end if;
 if v_quote.status<>'sent' then raise exception 'Only sent quotes can be accepted or declined';end if;
 if v_quote.valid_until is not null and v_quote.valid_until<=now()then raise exception 'This quote has expired. Ask Kridiya for a fresh option';end if;
 if exists(select 1 from public.corporate_desk_cases where quote_id=p_quote_id and category='amendment' and status not in('resolved','closed'))then raise exception 'This quote has an open revision request';end if;
 select p.* into v_policy from public.corporate_travel_policies p where p.corporate_account_id=v_booking.corporate_account_id and p.branch_id is null and p.status='active' and current_date>=p.effective_from and(p.effective_to is null or current_date<=p.effective_to) order by p.effective_from desc limit 1;
 if found and(v_policy.requires_second_approval or(v_policy.approval_threshold is not null and v_quote.price_amount>v_policy.approval_threshold))then v_required:=2;end if;
 v_decision:=case when p_status='accepted' then 'approved' else 'declined' end;
 if exists(select 1 from public.corporate_quote_approvals where quote_id=p_quote_id and approver_user_id=v_actor)then raise exception 'You already recorded a decision; a different authorized approver is required';end if;
 insert into public.corporate_quote_approvals(quote_id,booking_id,corporate_account_id,approver_user_id,decision,required_approvals,policy_id,policy_snapshot)values(p_quote_id,v_booking.id,v_booking.corporate_account_id,v_actor,v_decision,v_required,v_policy.id,jsonb_build_object('policy_name',v_policy.policy_name,'approval_threshold',v_policy.approval_threshold,'requires_second_approval',v_policy.requires_second_approval,'quote_amount',v_quote.price_amount,'currency',v_quote.currency));
 perform set_config('kridiya.quote_decision_rpc','on',true);
 if v_decision='declined' then update public.quotes set status='declined',responded_at=now() where id=p_quote_id;v_final:=true;else select count(distinct approver_user_id)into v_count from public.corporate_quote_approvals where quote_id=p_quote_id and decision='approved';if v_count>=v_required then update public.quotes set status='accepted',responded_at=now() where id=p_quote_id;update public.bookings set status=case when status in('enquiry','quote_sent')then'payment_pending'::public.booking_status else status end,selling_price=coalesce(selling_price,v_quote.price_amount),currency=coalesce(nullif(currency,''),v_quote.currency),updated_at=now()where id=v_booking.id;v_final:=true;end if;end if;
 insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)values(v_actor,'corporate_portal.quote_approval_recorded','quote',p_quote_id,jsonb_build_object('decision',v_decision,'required_approvals',v_required,'approval_count',coalesce(v_count,0),'finalized',v_final,'policy_id',v_policy.id,'booking_id',v_booking.id));
 return jsonb_build_object('ok',true,'quote_id',p_quote_id,'decision',v_decision,'required_approvals',v_required,'approval_count',coalesce(v_count,case when v_decision='declined'then 0 else 1 end),'finalized',v_final,'status',case when v_final then p_status else 'approval_pending' end);end$$;

revoke execute on function public.request_my_corporate_quote_revision(uuid,text) from public,anon;
revoke execute on function public.list_my_corporate_quotes(uuid,integer) from public,anon;
revoke execute on function public.respond_my_corporate_quote(uuid,text) from public,anon;
grant execute on function public.request_my_corporate_quote_revision(uuid,text) to authenticated;
grant execute on function public.list_my_corporate_quotes(uuid,integer) to authenticated;
grant execute on function public.respond_my_corporate_quote(uuid,text) to authenticated;
