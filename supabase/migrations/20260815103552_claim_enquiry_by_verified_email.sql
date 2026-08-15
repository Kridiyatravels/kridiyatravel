create or replace function public.claim_my_enquiry(p_reference text)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_confirmed_at timestamptz;
  v_enquiry_id uuid;
  v_owner_id uuid;
  v_reference text := upper(btrim(coalesce(p_reference, '')));
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if v_reference !~ '^KD-[A-Z]{3}-[A-Z0-9]{8}$' then
    raise exception 'Enquiry could not be verified';
  end if;

  select lower(email), email_confirmed_at
    into v_email, v_confirmed_at
  from auth.users
  where id = v_user_id;

  if v_email is null or v_confirmed_at is null then
    raise exception 'A verified email is required';
  end if;

  select id, user_id
    into v_enquiry_id, v_owner_id
  from public.enquiries
  where upper(reference) = v_reference
    and lower(btrim(email)) = v_email
  for update;

  if v_enquiry_id is null or (v_owner_id is not null and v_owner_id <> v_user_id) then
    raise exception 'Enquiry could not be verified';
  end if;

  if v_owner_id is null then
    update public.enquiries set user_id = v_user_id where id = v_enquiry_id;
    insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_user_id, 'enquiry.claimed_by_verified_email', 'enquiry', v_enquiry_id,
      jsonb_build_object('reference', v_reference));
  end if;

  return v_enquiry_id;
end;
$$;

revoke execute on function public.claim_my_enquiry(text) from public, anon;
grant execute on function public.claim_my_enquiry(text) to authenticated, service_role;

