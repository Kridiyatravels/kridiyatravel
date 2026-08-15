create or replace function public.protect_quote_customer_update()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if public.is_staff() then return new; end if;
  if pg_trigger_depth()>1 then return new; end if;
  if current_setting('kridiya.quote_decision_rpc',true)<>'on' then raise exception 'Use the secured quote decision service'; end if;
  if old.status<>'sent' or new.status not in ('accepted','declined') then raise exception 'Quotes can only be accepted or declined while status is sent'; end if;
  if (to_jsonb(new)-array['status','responded_at','updated_at','quote_version']) is distinct from (to_jsonb(old)-array['status','responded_at','updated_at','quote_version']) then raise exception 'Customers may only update quote status'; end if;
  new.responded_at:=now(); return new;
end $$;

create or replace function public.respond_to_my_quote(p_quote_id uuid,p_decision text,p_expected_updated_at timestamptz,p_terms_confirmed boolean default false)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid:=auth.uid(); v_quote public.quotes%rowtype; v_snapshot jsonb; v_evidence uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'Decision must be accepted or declined'; end if;
  select q.* into v_quote from public.quotes q join public.enquiries e on e.id=q.enquiry_id where q.id=p_quote_id and e.user_id=v_user for update of q;
  if not found then raise exception 'Quote not found for this account'; end if;
  if v_quote.status<>'sent' then raise exception 'This quote is no longer awaiting a decision'; end if;
  if v_quote.updated_at<>p_expected_updated_at then raise exception 'This quote changed. Refresh before deciding'; end if;
  if v_quote.valid_until is not null and v_quote.valid_until<now() then raise exception 'This quote has expired'; end if;
  if p_decision='accepted' and not p_terms_confirmed then raise exception 'Confirm the quote terms before accepting'; end if;
  v_snapshot:=jsonb_build_object('id',v_quote.id,'enquiry_id',v_quote.enquiry_id,'booking_id',v_quote.booking_id,'version',v_quote.quote_version,'title',v_quote.title,'description',v_quote.description,'price_amount',v_quote.price_amount,'currency',v_quote.currency,'valid_until',v_quote.valid_until,'terms',v_quote.terms,'airline',v_quote.airline,'stops',v_quote.stops,'outbound',v_quote.outbound,'inbound',v_quote.inbound,'baggage',v_quote.baggage,'addons',v_quote.addons,'option_data',v_quote.option_data);
  perform set_config('kridiya.quote_decision_rpc','on',true);
  update public.quotes set status=p_decision::public.quote_status,responded_at=now() where id=p_quote_id;
  insert into public.quote_decision_evidence(quote_id,customer_user_id,decision,quote_version,quote_snapshot,snapshot_sha256,terms_confirmed)
  values(p_quote_id,v_user,p_decision,v_quote.quote_version,v_snapshot,encode(digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex'),p_terms_confirmed) returning id into v_evidence;
  perform set_config('kridiya.quote_decision_rpc','off',true);
  return v_evidence;
end $$;

revoke execute on function public.protect_quote_customer_update() from public,anon,authenticated;
grant execute on function public.protect_quote_customer_update() to service_role;
