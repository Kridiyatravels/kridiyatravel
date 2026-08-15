alter table public.quotes add column if not exists quote_version integer not null default 1 check (quote_version > 0);
alter table public.customer_support_requests add column if not exists quote_id uuid references public.quotes(id) on delete set null;
create index if not exists customer_support_requests_quote_idx on public.customer_support_requests(quote_id) where quote_id is not null;

create table public.quote_decision_evidence (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes(id) on delete restrict,
  customer_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check (decision in ('accepted','declined')),
  quote_version integer not null,
  quote_snapshot jsonb not null,
  snapshot_sha256 text not null check (char_length(snapshot_sha256)=64),
  terms_confirmed boolean not null default false,
  decided_at timestamptz not null default now()
);
create unique index quote_decision_evidence_once_idx on public.quote_decision_evidence(quote_id);
create index quote_decision_evidence_customer_idx on public.quote_decision_evidence(customer_user_id,decided_at desc);
alter table public.quote_decision_evidence enable row level security;
create policy quote_decision_evidence_staff_select on public.quote_decision_evidence for select to authenticated using (public.is_staff());
revoke all on public.quote_decision_evidence from public,anon,authenticated;
grant select on public.quote_decision_evidence to authenticated;
grant all on public.quote_decision_evidence to service_role;

create or replace function public.bump_quote_version_on_material_change()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if public.is_staff() and (to_jsonb(new)-array['status','responded_at','updated_at','quote_version']) is distinct from (to_jsonb(old)-array['status','responded_at','updated_at','quote_version']) then
    new.quote_version:=old.quote_version+1;
  else new.quote_version:=old.quote_version;
  end if;
  return new;
end $$;
drop trigger if exists quotes_bump_material_version on public.quotes;
create trigger quotes_bump_material_version before update on public.quotes for each row execute function public.bump_quote_version_on_material_change();

create or replace function public.respond_to_my_quote(p_quote_id uuid,p_decision text,p_expected_updated_at timestamptz,p_terms_confirmed boolean default false)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid:=auth.uid(); v_quote public.quotes%rowtype; v_snapshot jsonb; v_evidence uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'Decision must be accepted or declined'; end if;
  select q.* into v_quote from public.quotes q join public.enquiries e on e.id=q.enquiry_id
  where q.id=p_quote_id and e.user_id=v_user for update of q;
  if not found then raise exception 'Quote not found for this account'; end if;
  if v_quote.status<>'sent' then raise exception 'This quote is no longer awaiting a decision'; end if;
  if v_quote.updated_at<>p_expected_updated_at then raise exception 'This quote changed. Refresh before deciding'; end if;
  if v_quote.valid_until is not null and v_quote.valid_until<now() then raise exception 'This quote has expired'; end if;
  if p_decision='accepted' and not p_terms_confirmed then raise exception 'Confirm the quote terms before accepting'; end if;
  v_snapshot:=jsonb_build_object('id',v_quote.id,'enquiry_id',v_quote.enquiry_id,'booking_id',v_quote.booking_id,'version',v_quote.quote_version,'title',v_quote.title,'description',v_quote.description,'price_amount',v_quote.price_amount,'currency',v_quote.currency,'valid_until',v_quote.valid_until,'terms',v_quote.terms,'airline',v_quote.airline,'stops',v_quote.stops,'outbound',v_quote.outbound,'inbound',v_quote.inbound,'baggage',v_quote.baggage,'addons',v_quote.addons,'option_data',v_quote.option_data);
  update public.quotes set status=p_decision::public.quote_status,responded_at=now() where id=p_quote_id;
  insert into public.quote_decision_evidence(quote_id,customer_user_id,decision,quote_version,quote_snapshot,snapshot_sha256,terms_confirmed)
  values(p_quote_id,v_user,p_decision,v_quote.quote_version,v_snapshot,encode(digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex'),p_terms_confirmed) returning id into v_evidence;
  return v_evidence;
end $$;

create or replace function public.request_my_quote_revision(p_quote_id uuid,p_message text,p_expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid:=auth.uid(); v_quote public.quotes%rowtype; v_request uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if char_length(btrim(coalesce(p_message,''))) not between 10 and 2000 then raise exception 'Revision request must be 10 to 2000 characters'; end if;
  select q.* into v_quote from public.quotes q join public.enquiries e on e.id=q.enquiry_id where q.id=p_quote_id and e.user_id=v_user;
  if not found then raise exception 'Quote not found for this account'; end if;
  if v_quote.status<>'sent' or v_quote.updated_at<>p_expected_updated_at then raise exception 'This quote changed or is no longer open. Refresh and try again'; end if;
  v_request:=public.create_my_support_request('amendment','Quote revision: '||left(v_quote.title,150),btrim(p_message),'normal',null,v_quote.enquiry_id);
  update public.customer_support_requests set quote_id=p_quote_id where id=v_request;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_user,'quote.revision_requested','quote',p_quote_id,jsonb_build_object('support_request_id',v_request,'quote_version',v_quote.quote_version));
  return v_request;
end $$;

revoke execute on function public.bump_quote_version_on_material_change() from public,anon,authenticated;
revoke execute on function public.respond_to_my_quote(uuid,text,timestamptz,boolean) from public,anon;
revoke execute on function public.request_my_quote_revision(uuid,text,timestamptz) from public,anon;
grant execute on function public.respond_to_my_quote(uuid,text,timestamptz,boolean) to authenticated,service_role;
grant execute on function public.request_my_quote_revision(uuid,text,timestamptz) to authenticated,service_role;
grant execute on function public.bump_quote_version_on_material_change() to service_role;

comment on table public.quote_decision_evidence is 'Immutable snapshot and digest of the exact quote version accepted or declined by its owning customer.';
