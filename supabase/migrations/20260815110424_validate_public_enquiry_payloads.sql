create or replace function public.validate_public_enquiry_payload()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  missing_fields text[] := '{}';
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    return new;
  end if;
  if current_user = 'authenticated' then
    if coalesce(public.is_staff(),false) then return new; end if;
  end if;

  if new.email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Enter a valid email address';
  end if;
  if new.phone is null or char_length(btrim(new.phone)) not between 7 and 30 then
    raise exception 'Enter a valid phone or WhatsApp number';
  end if;
  if jsonb_typeof(new.details) <> 'object' or octet_length(new.details::text) > 32768 then
    raise exception 'Enquiry details are invalid or too large';
  end if;

  case new.service_type
    when 'flight' then
      if nullif(btrim(new.details->>'Route'),'') is null then missing_fields:=array_append(missing_fields,'route'); end if;
      if nullif(btrim(new.details->>'Travellers'),'') is null then missing_fields:=array_append(missing_fields,'travellers'); end if;
      if nullif(btrim(new.details->>'Cabin'),'') is null then missing_fields:=array_append(missing_fields,'cabin'); end if;
    when 'hotel' then
      if nullif(btrim(new.details->>'City'),'') is null then missing_fields:=array_append(missing_fields,'city'); end if;
      if nullif(btrim(new.details->>'Stay'),'') is null then missing_fields:=array_append(missing_fields,'stay dates'); end if;
      if nullif(btrim(new.details->>'Rooms_Guests'),'') is null then missing_fields:=array_append(missing_fields,'rooms and guests'); end if;
    when 'holiday' then
      if nullif(btrim(new.details->>'Destination'),'') is null then missing_fields:=array_append(missing_fields,'destination'); end if;
      if coalesce(new.details->>'Travel_month','') !~ '^[0-9]{4}-[0-9]{2}$' then missing_fields:=array_append(missing_fields,'travel month'); end if;
    when 'visa' then
      if nullif(btrim(new.details->>'Country'),'') is null then missing_fields:=array_append(missing_fields,'visa country'); end if;
      if nullif(btrim(new.details->>'Nationality'),'') is null then missing_fields:=array_append(missing_fields,'nationality'); end if;
    when 'umrah' then
      if nullif(btrim(new.details->>'Package'),'') is null then missing_fields:=array_append(missing_fields,'Umrah package'); end if;
    when 'cruise' then
      if nullif(btrim(new.details->>'Cruise'),'') is null then missing_fields:=array_append(missing_fields,'cruise'); end if;
    when 'other' then
      if nullif(btrim(new.details->>'Message'),'') is null then missing_fields:=array_append(missing_fields,'message'); end if;
  end case;

  if cardinality(missing_fields) > 0 then
    raise exception 'Missing required enquiry details: %', array_to_string(missing_fields,', ');
  end if;
  return new;
end;
$$;

revoke execute on function public.validate_public_enquiry_payload() from public,anon,authenticated;
drop trigger if exists enquiries_validate_public_payload on public.enquiries;
create trigger enquiries_validate_public_payload
before insert on public.enquiries
for each row execute function public.validate_public_enquiry_payload();
