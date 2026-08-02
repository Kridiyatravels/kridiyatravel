-- Snapshot of functions found live in production but absent from all local SQL.
-- Captured 2026-08-02. This migration is for reproducibility; production
-- already contains these definitions and must not receive a blind replay.

begin;

CREATE OR REPLACE FUNCTION public.booking_profit_summary()
 RETURNS TABLE(booking_id uuid, booking_reference text, service_type booking_service_type, selling_price numeric, supplier_cost numeric, gross_profit numeric, currency text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    b.id,
    b.booking_reference,
    b.service_type,
    coalesce(b.selling_price, b.amount, 0) as selling_price,
    coalesce(b.supplier_cost, 0) as supplier_cost,
    coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) as gross_profit,
    b.currency,
    b.created_at
  from public.bookings b
  where public.has_staff_permission('view_profit')
    and b.archived_at is null;
$function$

revoke execute on function booking_profit_summary() from public, anon, authenticated;
grant execute on function booking_profit_summary() to authenticated;

CREATE OR REPLACE FUNCTION public.create_booking_quote_option(p_booking_id uuid, p_title text, p_description text DEFAULT NULL::text, p_price_amount numeric DEFAULT NULL::numeric, p_currency text DEFAULT 'AED'::text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_terms text DEFAULT NULL::text, p_option_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_booking public.bookings%rowtype;
  v_quote public.quotes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings')) then
    raise exception 'Booking quote permission required';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
    and archived_at is null;

  if not found then
    raise exception 'Booking not found';
  end if;

  if length(trim(coalesce(p_title, ''))) < 3 then
    raise exception 'Quote title is required';
  end if;

  if coalesce(p_price_amount, 0) <= 0 then
    raise exception 'Quote amount must be greater than zero';
  end if;

  insert into public.quotes (
    enquiry_id,
    booking_id,
    title,
    description,
    option_data,
    price_amount,
    currency,
    valid_until,
    terms,
    status,
    created_by
  ) values (
    v_booking.enquiry_id,
    v_booking.id,
    trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    coalesce(p_option_data, '{}'::jsonb),
    p_price_amount,
    coalesce(nullif(trim(coalesce(p_currency, '')), ''), 'AED'),
    p_valid_until,
    nullif(trim(coalesce(p_terms, '')), ''),
    'sent',
    auth.uid()
  )
  returning * into v_quote;

  update public.bookings
  set status = case when status = 'enquiry' then 'quote_sent' else status end,
      updated_at = now()
  where id = v_booking.id;

  if v_booking.enquiry_id is not null then
    update public.enquiries
    set status = 'quote_sent',
        quote_sent_at = coalesce(quote_sent_at, now())
    where id = v_booking.enquiry_id;
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'booking.quote_sent',
    'quote',
    v_quote.id,
    jsonb_build_object(
      'booking_id', v_booking.id,
      'booking_reference', v_booking.booking_reference,
      'enquiry_id', v_booking.enquiry_id,
      'amount', v_quote.price_amount,
      'currency', v_quote.currency
    )
  );

  return jsonb_build_object(
    'ok', true,
    'quote', jsonb_build_object(
      'id', v_quote.id,
      'booking_id', v_quote.booking_id,
      'enquiry_id', v_quote.enquiry_id,
      'title', v_quote.title,
      'description', v_quote.description,
      'option_data', v_quote.option_data,
      'price_amount', v_quote.price_amount,
      'currency', v_quote.currency,
      'valid_until', v_quote.valid_until,
      'terms', v_quote.terms,
      'status', v_quote.status,
      'created_at', v_quote.created_at
    )
  );
end;
$function$

revoke execute on function create_booking_quote_option(uuid,text,text,numeric,text,timestamp with time zone,text,jsonb) from public, anon, authenticated;
grant execute on function create_booking_quote_option(uuid,text,text,numeric,text,timestamp with time zone,text,jsonb) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.delete_staff_profile(target_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can delete staff profiles';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'You cannot delete your own staff profile';
  end if;
  if public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  delete from public.staff_permissions where user_id = target_user_id;
  delete from public.staff_roles where user_id = target_user_id;
  update public.staff_profiles
  set active = false,
      deleted_at = now(),
      hold_until = null,
      hold_reason = null,
      updated_at = now()
  where user_id = target_user_id;

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.profile_deleted', 'user', target_user_id, '{}'::jsonb);

  return 'deleted';
end;
$function$

revoke execute on function delete_staff_profile(uuid) from public, anon, authenticated;
grant execute on function delete_staff_profile(uuid) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_booking_quote_context(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'booking_id', b.id,
    'enquiry_id', b.enquiry_id,
    'source', b.source,
    'can_edit_quotes', public.has_staff_permission('create_bookings') or public.has_staff_permission('edit_bookings'),
    'quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'booking_id', q.booking_id,
        'enquiry_id', q.enquiry_id,
        'title', q.title,
        'description', q.description,
        'option_data', q.option_data,
        'addons', q.addons,
        'price_amount', q.price_amount,
        'currency', q.currency,
        'valid_until', q.valid_until,
        'terms', q.terms,
        'status', q.status,
        'responded_at', q.responded_at,
        'created_at', q.created_at
      ) order by q.created_at desc)
      from public.quotes q
      where q.booking_id = b.id
         or (b.enquiry_id is not null and q.enquiry_id = b.enquiry_id)
    ), '[]'::jsonb)
  )
  from public.bookings b
  where b.id = p_booking_id
    and b.archived_at is null
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_reports')
    );
$function$

revoke execute on function get_booking_quote_context(uuid) from public, anon, authenticated;
grant execute on function get_booking_quote_context(uuid) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_staff_management_profiles()
 RETURNS TABLE(user_id uuid, email text, role staff_role, full_name text, department text, job_title text, phone text, notes text, active boolean, hold_until timestamp with time zone, hold_reason text, created_at timestamp with time zone, updated_at timestamp with time zone, permissions jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can view staff management profiles';
  end if;

  return query
    select
      sr.user_id,
      au.email::text,
      sr.role,
      coalesce(sp.full_name, au.email::text),
      sp.department,
      sp.job_title,
      sp.phone,
      sp.notes,
      coalesce(sp.active, true),
      sp.hold_until,
      sp.hold_reason,
      coalesce(sp.created_at, sr.created_at),
      coalesce(sp.updated_at, sr.created_at),
      jsonb_build_object(
        'view_enquiries', coalesce(p.view_enquiries, false),
        'edit_enquiries', coalesce(p.edit_enquiries, false),
        'view_customers', coalesce(p.view_customers, false),
        'edit_customers', coalesce(p.edit_customers, false),
        'view_corporates', coalesce(p.view_corporates, false),
        'edit_corporates', coalesce(p.edit_corporates, false),
        'create_bookings', coalesce(p.create_bookings, false),
        'edit_bookings', coalesce(p.edit_bookings, false),
        'view_payments', coalesce(p.view_payments, false),
        'edit_payments', coalesce(p.edit_payments, false),
        'view_supplier_cost', coalesce(p.view_supplier_cost, false),
        'view_profit', coalesce(p.view_profit, false),
        'generate_documents', coalesce(p.generate_documents, false),
        'manage_portals', coalesce(p.manage_portals, false),
        'manage_templates', coalesce(p.manage_templates, false),
        'view_reports', coalesce(p.view_reports, false),
        'export_reports', coalesce(p.export_reports, false),
        'approve_refunds', coalesce(p.approve_refunds, false),
        'approve_discounts', coalesce(p.approve_discounts, false),
        'manage_staff', coalesce(p.manage_staff, false),
        'view_activity', coalesce(p.view_activity, false),
        'manage_settings', coalesce(p.manage_settings, false)
      )
    from public.staff_roles sr
    join auth.users au on au.id = sr.user_id
    left join public.staff_profiles sp on sp.user_id = sr.user_id and sp.deleted_at is null
    left join public.staff_permissions p on p.user_id = sr.user_id
    order by coalesce(sp.active, true) desc, coalesce(sp.full_name, au.email::text);
end;
$function$

revoke execute on function get_staff_management_profiles() from public, anon, authenticated;
grant execute on function get_staff_management_profiles() to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.has_staff_permission(permission_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  allowed boolean := false;
begin
  if public.is_admin() then
    return true;
  end if;
  if not public.is_staff() then
    return false;
  end if;

  case permission_name
    when 'view_enquiries' then select sp.view_enquiries into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_enquiries' then select sp.edit_enquiries into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_customers' then select sp.view_customers into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_customers' then select sp.edit_customers into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_corporates' then select sp.view_corporates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_corporates' then select sp.edit_corporates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'create_bookings' then select sp.create_bookings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_bookings' then select sp.edit_bookings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_payments' then select sp.view_payments into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'edit_payments' then select sp.edit_payments into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_supplier_cost' then select sp.view_supplier_cost into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_profit' then select sp.view_profit into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'generate_documents' then select sp.generate_documents into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_portals' then select sp.manage_portals into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_templates' then select sp.manage_templates into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_reports' then select sp.view_reports into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'export_reports' then select sp.export_reports into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'approve_refunds' then select sp.approve_refunds into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'approve_discounts' then select sp.approve_discounts into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_staff' then select sp.manage_staff into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'view_activity' then select sp.view_activity into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    when 'manage_settings' then select sp.manage_settings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
    else allowed := false;
  end case;

  return coalesce(allowed, false);
end;
$function$

revoke execute on function has_staff_permission(text) from public, anon, authenticated;
grant execute on function has_staff_permission(text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hold_staff(target_user_id uuid, hold_until timestamp with time zone, reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can hold staff access';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'You cannot hold your own staff account';
  end if;
  if hold_until is null or hold_until <= now() then
    raise exception 'Hold-until time must be in the future';
  end if;
  if public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  insert into public.staff_profiles (user_id, full_name, active, hold_until, hold_reason, created_by)
  select
    target_user_id,
    coalesce(nullif(trim(au.raw_user_meta_data->>'full_name'), ''), au.email::text),
    true,
    $2,
    nullif(trim(coalesce(reason, 'Temporary hold')), ''),
    auth.uid()
  from auth.users au
  where au.id = target_user_id
  on conflict (user_id) do update set
    active = true,
    hold_until = excluded.hold_until,
    hold_reason = excluded.hold_reason,
    deleted_at = null,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.held', 'user', target_user_id, jsonb_build_object('hold_until', hold_until, 'reason', reason));

  return 'held';
end;
$function$

revoke execute on function hold_staff(uuid,timestamp with time zone,text) from public, anon, authenticated;
grant execute on function hold_staff(uuid,timestamp with time zone,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.next_booking_reference()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n bigint;
begin
  n := nextval('public.booking_reference_seq');
  return 'KRI-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$function$

revoke execute on function next_booking_reference() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_payment_reference()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n bigint;
begin
  n := nextval('public.payment_reference_seq');
  return 'PAY-' || to_char(now(), 'YYYY') || '-' || lpad(n::text, 4, '0');
end;
$function$

revoke execute on function next_payment_reference() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reactivate_staff(target_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can reactivate staff access';
  end if;

  insert into public.staff_profiles (user_id, full_name, active, hold_until, hold_reason, created_by)
  select
    target_user_id,
    coalesce(nullif(trim(au.raw_user_meta_data->>'full_name'), ''), au.email::text),
    true,
    null,
    null,
    auth.uid()
  from auth.users au
  where au.id = target_user_id
  on conflict (user_id) do update set
    active = true,
    hold_until = null,
    hold_reason = null,
    deleted_at = null,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.reactivated', 'user', target_user_id, '{}'::jsonb);

  return 'reactivated';
end;
$function$

revoke execute on function reactivate_staff(uuid) from public, anon, authenticated;
grant execute on function reactivate_staff(uuid) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_customer_payment(p_booking_id uuid, p_amount numeric, p_method text, p_status text DEFAULT 'received'::text, p_currency text DEFAULT 'AED'::text, p_payment_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment_id uuid;
  v_ref text;
  v_booking_ref text;
begin
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;

  if p_amount is null or p_amount < 0 then
    raise exception 'Payment amount must be positive';
  end if;

  select booking_reference into v_booking_ref from public.bookings where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  v_ref := public.next_payment_reference();

  insert into public.payments (
    booking_id,
    payment_reference,
    amount,
    currency,
    method,
    status,
    payment_link,
    notes,
    received_at,
    created_by
  ) values (
    p_booking_id,
    v_ref,
    p_amount,
    upper(coalesce(p_currency, 'AED')),
    p_method,
    p_status,
    nullif(trim(coalesce(p_payment_link, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    case when p_status = 'received' then now() else null end,
    auth.uid()
  ) returning id into v_payment_id;

  update public.bookings
  set payment_status = case
        when p_status = 'received' then 'paid'
        when p_status = 'proof_received' then 'proof_received'
        else payment_status
      end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'payment.recorded', 'payment', v_payment_id, jsonb_build_object('booking_reference', v_booking_ref, 'payment_reference', v_ref, 'amount', p_amount, 'method', p_method, 'status', p_status));

  return v_payment_id;
end;
$function$

revoke execute on function record_customer_payment(uuid,numeric,text,text,text,text,text) from public, anon, authenticated;
grant execute on function record_customer_payment(uuid,numeric,text,text,text,text,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_supplier_payment(p_booking_id uuid, p_supplier_name text, p_amount_payable numeric, p_amount_paid numeric DEFAULT 0, p_status text DEFAULT 'pending'::text, p_currency text DEFAULT 'AED'::text, p_supplier_reference text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_supplier_payment_id uuid;
  v_booking_ref text;
begin
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Permission denied';
  end if;

  select booking_reference into v_booking_ref from public.bookings where id = p_booking_id and archived_at is null;
  if v_booking_ref is null then
    raise exception 'Booking not found';
  end if;

  insert into public.supplier_payments (
    booking_id,
    supplier_name,
    supplier_reference,
    amount_payable,
    amount_paid,
    currency,
    due_date,
    paid_at,
    status,
    notes,
    created_by
  ) values (
    p_booking_id,
    trim(p_supplier_name),
    nullif(trim(coalesce(p_supplier_reference, '')), ''),
    coalesce(p_amount_payable, 0),
    coalesce(p_amount_paid, 0),
    upper(coalesce(p_currency, 'AED')),
    p_due_date,
    case when p_status = 'paid' then now() else null end,
    p_status,
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
  ) returning id into v_supplier_payment_id;

  update public.bookings
  set supplier_name = trim(p_supplier_name),
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      supplier_cost = coalesce(p_amount_payable, supplier_cost),
      payment_status = case when p_status = 'paid' then 'supplier_paid' else payment_status end,
      updated_at = now()
  where id = p_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'supplier_payment.recorded', 'supplier_payment', v_supplier_payment_id, jsonb_build_object('booking_reference', v_booking_ref, 'supplier_name', p_supplier_name, 'amount_payable', p_amount_payable, 'status', p_status));

  return v_supplier_payment_id;
end;
$function$

revoke execute on function record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text) from public, anon, authenticated;
grant execute on function record_supplier_payment(uuid,text,numeric,numeric,text,text,text,date,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$

revoke execute on function rls_auto_enable() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.staff_management_admin_count(except_user_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::integer
  from public.staff_roles sr
  left join public.staff_profiles sp on sp.user_id = sr.user_id
  where sr.role in ('owner', 'admin')
    and (except_user_id is null or sr.user_id <> except_user_id)
    and coalesce(sp.active, true) = true
    and coalesce(sp.deleted_at is null, true)
    and (sp.hold_until is null or sp.hold_until <= now());
$function$

revoke execute on function staff_management_admin_count(uuid) from public, anon, authenticated;
grant execute on function staff_management_admin_count(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.update_operations_booking_status(p_booking_id uuid, p_status booking_status, p_payment_status text, p_document_status text, p_supplier_reference text DEFAULT NULL::text, p_staff_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ref text;
begin
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Permission denied';
  end if;

  update public.bookings
  set status = p_status,
      payment_status = p_payment_status,
      document_status = p_document_status,
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      staff_notes = nullif(trim(coalesce(p_staff_notes, '')), ''),
      updated_at = now()
  where id = p_booking_id
  returning booking_reference into v_ref;

  if v_ref is null then
    raise exception 'Booking not found';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'booking.status_updated', 'booking', p_booking_id, jsonb_build_object('reference', v_ref, 'status', p_status, 'payment_status', p_payment_status, 'document_status', p_document_status));
end;
$function$

revoke execute on function update_operations_booking_status(uuid,booking_status,text,text,text,text) from public, anon, authenticated;
grant execute on function update_operations_booking_status(uuid,booking_status,text,text,text,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_staff_permissions(target_user_id uuid, permissions jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can update staff permissions';
  end if;

  insert into public.staff_permissions (
    user_id, view_enquiries, edit_enquiries, view_customers, edit_customers,
    view_corporates, edit_corporates, create_bookings, edit_bookings,
    view_payments, edit_payments, view_supplier_cost, view_profit,
    generate_documents, manage_portals, manage_templates, view_reports,
    export_reports, approve_refunds, approve_discounts, manage_staff,
    view_activity, manage_settings
  )
  values (
    target_user_id,
    coalesce((permissions->>'view_enquiries')::boolean, false),
    coalesce((permissions->>'edit_enquiries')::boolean, false),
    coalesce((permissions->>'view_customers')::boolean, false),
    coalesce((permissions->>'edit_customers')::boolean, false),
    coalesce((permissions->>'view_corporates')::boolean, false),
    coalesce((permissions->>'edit_corporates')::boolean, false),
    coalesce((permissions->>'create_bookings')::boolean, false),
    coalesce((permissions->>'edit_bookings')::boolean, false),
    coalesce((permissions->>'view_payments')::boolean, false),
    coalesce((permissions->>'edit_payments')::boolean, false),
    coalesce((permissions->>'view_supplier_cost')::boolean, false),
    coalesce((permissions->>'view_profit')::boolean, false),
    coalesce((permissions->>'generate_documents')::boolean, false),
    coalesce((permissions->>'manage_portals')::boolean, false),
    coalesce((permissions->>'manage_templates')::boolean, false),
    coalesce((permissions->>'view_reports')::boolean, false),
    coalesce((permissions->>'export_reports')::boolean, false),
    coalesce((permissions->>'approve_refunds')::boolean, false),
    coalesce((permissions->>'approve_discounts')::boolean, false),
    coalesce((permissions->>'manage_staff')::boolean, false),
    coalesce((permissions->>'view_activity')::boolean, false),
    coalesce((permissions->>'manage_settings')::boolean, false)
  )
  on conflict (user_id) do update set
    view_enquiries = excluded.view_enquiries,
    edit_enquiries = excluded.edit_enquiries,
    view_customers = excluded.view_customers,
    edit_customers = excluded.edit_customers,
    view_corporates = excluded.view_corporates,
    edit_corporates = excluded.edit_corporates,
    create_bookings = excluded.create_bookings,
    edit_bookings = excluded.edit_bookings,
    view_payments = excluded.view_payments,
    edit_payments = excluded.edit_payments,
    view_supplier_cost = excluded.view_supplier_cost,
    view_profit = excluded.view_profit,
    generate_documents = excluded.generate_documents,
    manage_portals = excluded.manage_portals,
    manage_templates = excluded.manage_templates,
    view_reports = excluded.view_reports,
    export_reports = excluded.export_reports,
    approve_refunds = excluded.approve_refunds,
    approve_discounts = excluded.approve_discounts,
    manage_staff = excluded.manage_staff,
    view_activity = excluded.view_activity,
    manage_settings = excluded.manage_settings,
    updated_at = now();

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.permissions_updated', 'user', target_user_id, permissions);

  return 'updated';
end;
$function$

revoke execute on function update_staff_permissions(uuid,jsonb) from public, anon, authenticated;
grant execute on function update_staff_permissions(uuid,jsonb) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_staff_profile(target_user_id uuid, full_name text, department text DEFAULT NULL::text, job_title text DEFAULT NULL::text, phone text DEFAULT NULL::text, role staff_role DEFAULT 'staff'::staff_role, active boolean DEFAULT true, notes text DEFAULT NULL::text, hold_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can update staff profiles';
  end if;
  if target_user_id = auth.uid() and active = false then
    raise exception 'You cannot deactivate your own staff account';
  end if;
  if char_length(trim(coalesce(full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;
  if (role not in ('owner', 'admin')) and public.staff_management_admin_count(target_user_id) < 1 then
    raise exception 'Keep at least one active owner/admin account';
  end if;

  insert into public.staff_profiles (
    user_id, full_name, department, job_title, phone, notes, active, hold_until, hold_reason, created_by, deleted_at
  )
  values (
    target_user_id, trim(full_name), nullif(trim(coalesce(department, '')), ''),
    nullif(trim(coalesce(job_title, '')), ''), nullif(trim(coalesce(phone, '')), ''),
    nullif(trim(coalesce(notes, '')), ''), active, hold_until,
    case when hold_until is null then null else nullif(trim(coalesce(notes, '')), '') end,
    auth.uid(), null
  )
  on conflict (user_id) do update set
    full_name = excluded.full_name,
    department = excluded.department,
    job_title = excluded.job_title,
    phone = excluded.phone,
    notes = excluded.notes,
    active = excluded.active,
    hold_until = excluded.hold_until,
    hold_reason = excluded.hold_reason,
    deleted_at = null,
    updated_at = now();

  insert into public.staff_roles (user_id, role)
  values (target_user_id, role)
  on conflict (user_id) do update set role = excluded.role;

  insert into public.audit_events(actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), target_user_id, 'staff.profile_updated', 'user', target_user_id, jsonb_build_object('role', role, 'active', active, 'hold_until', hold_until));

  return 'updated';
end;
$function$

revoke execute on function update_staff_profile(uuid,text,text,text,text,staff_role,boolean,text,timestamp with time zone) from public, anon, authenticated;
grant execute on function update_staff_profile(uuid,text,text,text,text,staff_role,boolean,text,timestamp with time zone) to authenticated, service_role;

commit;

