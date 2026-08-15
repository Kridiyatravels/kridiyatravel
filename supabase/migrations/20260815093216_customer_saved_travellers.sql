create or replace function public.list_my_travellers()
returns table (
  id uuid,
  full_name text,
  date_of_birth date,
  nationality text,
  passport_masked text,
  has_passport boolean,
  passport_expiry date,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $function$
  select t.id, t.full_name, t.date_of_birth, t.nationality,
    case when public.normalize_traveller_identity(t.passport_number) is null then null
      else '•••• ' || right(public.normalize_traveller_identity(t.passport_number), 4) end,
    public.normalize_traveller_identity(t.passport_number) is not null,
    t.passport_expiry, t.updated_at
  from public.travellers t
  join public.customers c on c.id=t.customer_id
  where auth.uid() is not null
    and c.auth_user_id=auth.uid()
    and c.archived_at is null
    and t.archived_at is null
  order by t.full_name,t.date_of_birth nulls last,t.id;
$function$;

revoke execute on function public.list_my_travellers() from public, anon;
grant execute on function public.list_my_travellers() to authenticated, service_role;

create or replace function public.save_my_traveller(
  p_traveller_id uuid,
  p_full_name text,
  p_date_of_birth date,
  p_nationality text,
  p_passport_number text,
  p_passport_expiry date,
  p_expected_updated_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  customer_id uuid;
  existing public.travellers%rowtype;
  saved_id uuid;
  passport_value text := nullif(trim(coalesce(p_passport_number,'')),'');
  event_name text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(trim(coalesce(p_full_name,''))) < 2 then
    raise exception 'Traveller full name is required';
  end if;
  if p_date_of_birth is not null and p_date_of_birth > current_date then
    raise exception 'Date of birth cannot be in the future';
  end if;
  if p_passport_expiry is not null and p_passport_expiry < current_date then
    raise exception 'Passport expiry must be today or later';
  end if;
  if passport_value is not null then perform public.require_recent_auth(1800); end if;

  select c.id into customer_id
  from public.customers c
  where c.auth_user_id=auth.uid() and c.archived_at is null
  order by c.created_at,c.id limit 1;
  if customer_id is null then raise exception 'Customer account is not linked'; end if;

  if p_traveller_id is null then
    insert into public.travellers (
      customer_id,full_name,date_of_birth,nationality,
      passport_number,passport_expiry,created_by
    ) values (
      customer_id,trim(p_full_name),p_date_of_birth,
      nullif(trim(coalesce(p_nationality,'')),''),passport_value,
      p_passport_expiry,auth.uid()
    ) returning id into saved_id;
    event_name := 'traveller.customer_created';
  else
    select t.* into existing
    from public.travellers t
    where t.id=p_traveller_id and t.customer_id=customer_id
      and t.archived_at is null
    for update;
    if existing.id is null then raise exception 'Traveller not found'; end if;
    if p_expected_updated_at is null or existing.updated_at<>p_expected_updated_at then
      raise exception 'Traveller changed after it was loaded. Refresh and try again.';
    end if;
    update public.travellers
    set full_name=trim(p_full_name), date_of_birth=p_date_of_birth,
        nationality=nullif(trim(coalesce(p_nationality,'')),''),
        passport_number=coalesce(passport_value,existing.passport_number),
        passport_expiry=case when passport_value is not null
          then p_passport_expiry else coalesce(p_passport_expiry,existing.passport_expiry) end,
        updated_at=now()
    where id=p_traveller_id
    returning id into saved_id;
    event_name := 'traveller.customer_updated';
  end if;

  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values (auth.uid(),event_name,'traveller',saved_id,jsonb_build_object(
    'customer_id',customer_id,
    'passport_supplied',passport_value is not null,
    'date_of_birth_supplied',p_date_of_birth is not null
  ));
  return saved_id;
end;
$function$;

revoke execute on function public.save_my_traveller(
  uuid,text,date,text,text,date,timestamptz
) from public, anon;
grant execute on function public.save_my_traveller(
  uuid,text,date,text,text,date,timestamptz
) to authenticated, service_role;

create or replace function public.archive_my_traveller(
  p_traveller_id uuid,
  p_expected_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare
  customer_id uuid;
  existing public.travellers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  select c.id into customer_id from public.customers c
  where c.auth_user_id=auth.uid() and c.archived_at is null
  order by c.created_at,c.id limit 1;
  if customer_id is null then raise exception 'Customer account is not linked'; end if;

  select t.* into existing from public.travellers t
  where t.id=p_traveller_id and t.customer_id=customer_id
    and t.archived_at is null for update;
  if existing.id is null then raise exception 'Traveller not found'; end if;
  if p_expected_updated_at is null or existing.updated_at<>p_expected_updated_at then
    raise exception 'Traveller changed after it was loaded. Refresh and try again.';
  end if;

  update public.travellers set active=false,archived_at=now(),updated_at=now()
  where id=p_traveller_id;
  insert into public.audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
  values (auth.uid(),'traveller.customer_archived','traveller',p_traveller_id,
    jsonb_build_object('customer_id',customer_id));
  return true;
end;
$function$;

revoke execute on function public.archive_my_traveller(uuid,timestamptz)
from public, anon;
grant execute on function public.archive_my_traveller(uuid,timestamptz)
to authenticated, service_role;
