\set ON_ERROR_STOP on

begin;

do $test$
declare
  v_expected text[] := array[
    'create_corporate_account(text,text,text,text,text,text,text,text,boolean,boolean,boolean,text,text)',
    'create_corporate_contact(uuid,text,text,text,text,text,boolean,boolean,text)',
    'delete_booking_document(uuid)',
    'delete_booking_passenger(uuid)',
    'generate_booking_payment_request_document(uuid,numeric,text)',
    'generate_booking_receipt_document(uuid,uuid)',
    'record_booking_document(uuid,text,text,text,text,boolean)',
    'record_booking_passenger(uuid,text,text,text,date,text,date,text)',
    'update_booking_corporate_controls(uuid,text,text)'
  ];
  v_signature text;
  v_oid oid;
begin
  foreach v_signature in array v_expected loop
    v_oid := to_regprocedure('public.' || v_signature);
    if v_oid is null then
      raise exception 'TEST FAILED: missing captured RPC public.%', v_signature;
    end if;

    if not has_function_privilege('authenticated', v_oid, 'EXECUTE')
       or not has_function_privilege('service_role', v_oid, 'EXECUTE')
       or has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception 'TEST FAILED: unexpected EXECUTE ACL for public.%', v_signature;
    end if;
  end loop;

  raise notice 'PASS RPC capture: all 9 exact signatures exist with authenticated/service_role execute and anon denied';
end;
$test$;

do $test$
declare
  v_config text[];
begin
  if to_regclass('public.doc_receipt_seq') is null then
    raise exception 'TEST FAILED: public.doc_receipt_seq is missing';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where n.nspname = 'public'
      and c.relname = 'staff_permissions'
      and t.tgname = 'staff_permissions_set_updated_at'
      and not t.tgisinternal
      and pn.nspname = 'public'
      and p.proname = 'set_updated_at'
  ) then
    raise exception 'TEST FAILED: staff_permissions_set_updated_at trigger is missing or points to the wrong function';
  end if;

  if not exists (
    select 1
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'payments'
      and pol.polname = 'payments_select_customer_own'
      and pol.polcmd = 'r'
  ) then
    raise exception 'TEST FAILED: payments_select_customer_own policy is missing';
  end if;

  select p.proconfig
  into v_config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'set_updated_at'
    and p.pronargs = 0;

  if v_config is distinct from array['search_path=public, pg_temp']::text[] then
    raise exception 'TEST FAILED: set_updated_at search_path is %, expected public, pg_temp', v_config;
  end if;

  raise notice 'PASS schema artifacts: sequence, trigger, customer payment policy, and hardened set_updated_at are present';
end;
$test$;

insert into public.enquiries (
  id,
  reference,
  service_type,
  full_name,
  email,
  phone,
  summary,
  details
)
values (
  'fa000000-0000-0000-0000-000000000001',
  'ENQ-FRESH-REBUILD-AUTH-LINK',
  'flight',
  'Enquiry Name',
  'fresh-rebuild-auth-link@example.test',
  '+971500000001',
  'Fresh rebuild signup-link fixture',
  '{}'::jsonb
);

insert into public.customers (
  id,
  full_name,
  email,
  phone,
  source
)
values (
  'fa000000-0000-0000-0000-000000000002',
  'Existing Customer Name',
  'fresh-rebuild-auth-link@example.test',
  '+971500000002',
  'manual'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  'fa000000-0000-0000-0000-000000000003',
  'authenticated',
  'authenticated',
  'fresh-rebuild-auth-link@example.test',
  '{}'::jsonb,
  '{"full_name":"Signup Metadata Name","whatsapp":"+971500000003"}'::jsonb,
  now(),
  now()
);

do $test$
begin
  if not exists (
    select 1
    from public.profiles
    where id = 'fa000000-0000-0000-0000-000000000003'
      and full_name = 'Signup Metadata Name'
      and preferred_email = 'fresh-rebuild-auth-link@example.test'
      and phone = '+971500000001'
      and whatsapp = '+971500000003'
  ) then
    raise exception 'TEST FAILED: handle_new_auth_user did not create the expected profile';
  end if;

  if not exists (
    select 1
    from public.enquiries
    where id = 'fa000000-0000-0000-0000-000000000001'
      and user_id = 'fa000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'TEST FAILED: handle_new_auth_user did not link the matching enquiry';
  end if;

  if not exists (
    select 1
    from public.customers
    where id = 'fa000000-0000-0000-0000-000000000002'
      and auth_user_id = 'fa000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'TEST FAILED: handle_new_auth_user did not link the matching customer';
  end if;

  if (select count(*) from public.customers where lower(email) = 'fresh-rebuild-auth-link@example.test') <> 1 then
    raise exception 'TEST FAILED: handle_new_auth_user created a duplicate customer';
  end if;

  raise notice 'PASS signup behavior: profile created, matching enquiry/customer linked, and no duplicate customer created';
end;
$test$;

rollback;
