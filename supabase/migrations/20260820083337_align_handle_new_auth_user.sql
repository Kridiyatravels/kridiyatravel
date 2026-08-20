-- Exact production capture of the auth.users signup trigger function.
-- This intentionally preserves current enquiry/customer linking behavior.

CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_name  text;
  v_phone text;
  v_cust_id uuid;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    (select e.full_name from public.enquiries e
       where lower(e.email) = lower(new.email) order by e.created_at desc limit 1),
    split_part(new.email, '@', 1)
  );
  v_phone := coalesce(
    nullif(trim(new.raw_user_meta_data->>'phone'), ''),
    (select e.phone from public.enquiries e
       where lower(e.email) = lower(new.email) and e.phone is not null
       order by e.created_at desc limit 1)
  );

  insert into public.profiles (id, full_name, preferred_email, phone, whatsapp)
  values (
    new.id, v_name, new.email, v_phone,
    nullif(trim(new.raw_user_meta_data->>'whatsapp'), '')
  )
  on conflict (id) do nothing;

  update public.enquiries
     set user_id = new.id, updated_at = now()
   where user_id is null
     and lower(email) = lower(new.email);

  select id into v_cust_id from public.customers where auth_user_id = new.id limit 1;
  if v_cust_id is null then
    update public.customers
       set auth_user_id = new.id, updated_at = now()
     where auth_user_id is null
       and lower(email) = lower(new.email)
       and archived_at is null
    returning id into v_cust_id;
  end if;
  if v_cust_id is null then
    insert into public.customers (full_name, email, phone, auth_user_id, source)
    values (v_name, new.email, v_phone, new.id, 'website');
  end if;

  return new;
end;
$$;
