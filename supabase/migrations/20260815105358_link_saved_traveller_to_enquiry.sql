alter table public.enquiries
  add column if not exists primary_traveller_id uuid
  references public.travellers(id) on delete set null;

create index if not exists enquiries_primary_traveller_idx
  on public.enquiries(primary_traveller_id)
  where primary_traveller_id is not null;

create or replace function public.link_my_enquiry_traveller(
  p_enquiry_id uuid,
  p_traveller_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_reference text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_enquiry_id is null or p_traveller_id is null then raise exception 'Enquiry and traveller are required'; end if;

  select e.reference into v_reference
  from public.enquiries e
  where e.id = p_enquiry_id and e.user_id = v_user_id
  for update;
  if v_reference is null then raise exception 'Enquiry not found for this account'; end if;

  if not exists (
    select 1 from public.travellers t
    join public.customers c on c.id = t.customer_id
    where t.id = p_traveller_id and t.archived_at is null and t.active = true
      and c.auth_user_id = v_user_id and c.archived_at is null
  ) then
    raise exception 'Traveller not found for this account';
  end if;

  update public.enquiries set primary_traveller_id = p_traveller_id
  where id = p_enquiry_id;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values(v_user_id,'enquiry.primary_traveller_linked','enquiry',p_enquiry_id,
    jsonb_build_object('reference',v_reference,'traveller_id',p_traveller_id));
  return true;
end;
$$;

revoke execute on function public.link_my_enquiry_traveller(uuid,uuid) from public,anon;
grant execute on function public.link_my_enquiry_traveller(uuid,uuid) to authenticated,service_role;

