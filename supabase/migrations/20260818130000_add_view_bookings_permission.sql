-- Add a first-class booking read permission and preserve every staff member's
-- pre-migration effective booking visibility.

alter table public.staff_permissions
  add column if not exists view_bookings boolean not null default false;

update public.staff_permissions
set
  view_bookings = true,
  updated_at = now()
where
  create_bookings
  or edit_bookings
  or view_payments
  or view_reports;

comment on column public.staff_permissions.view_bookings is
  'Allows an active staff member to read non-archived operations bookings.';

create or replace function public.has_staff_permission(permission_name text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  allowed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
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
    when 'view_bookings' then select sp.view_bookings into allowed from public.staff_permissions sp where sp.user_id = auth.uid();
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
$function$;

create or replace function public.update_staff_permissions_internal_20260815(
  target_user_id uuid,
  permissions jsonb
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_admin() then
    raise exception 'Only admins can update staff permissions';
  end if;

  insert into public.staff_permissions (
    user_id, view_enquiries, edit_enquiries, view_customers, edit_customers,
    view_corporates, edit_corporates, view_bookings, create_bookings, edit_bookings,
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
    coalesce((permissions->>'view_bookings')::boolean, false),
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
    view_bookings = excluded.view_bookings,
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
$function$;

create or replace function public.get_staff_management_profiles()
returns table(
  user_id uuid,
  email text,
  role public.staff_role,
  full_name text,
  department text,
  job_title text,
  phone text,
  notes text,
  active boolean,
  hold_until timestamptz,
  hold_reason text,
  created_at timestamptz,
  updated_at timestamptz,
  permissions jsonb
)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
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
        'view_bookings', coalesce(p.view_bookings, false),
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
$function$;

alter policy bookings_select_own_or_staff
on public.bookings
using (
  user_id = (select auth.uid())
  or (select public.has_staff_permission('view_bookings'))
);

create or replace function public.list_operations_bookings(limit_count integer default 200)
returns table(
  id uuid,
  booking_reference text,
  enquiry_id uuid,
  customer_id uuid,
  corporate_account_id uuid,
  corporate_contact_id uuid,
  corporate_company_name text,
  corporate_contact_name text,
  booking_kind text,
  service_type public.booking_service_type,
  title text,
  route_or_destination text,
  travel_start date,
  travel_end date,
  status public.booking_status,
  payment_status text,
  document_status text,
  supplier_name text,
  supplier_cost numeric,
  selling_price numeric,
  gross_profit numeric,
  currency text,
  priority text,
  follow_up_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path to 'public'
as $function$
  select guarded.*
  from (
    select
      b.id,
      b.booking_reference,
      b.enquiry_id,
      b.customer_id,
      b.corporate_account_id,
      b.corporate_contact_id,
      ca.company_name as corporate_company_name,
      cc.full_name as corporate_contact_name,
      b.booking_kind,
      b.service_type,
      b.title,
      b.route_or_destination,
      b.travel_start,
      b.travel_end,
      b.status,
      b.payment_status,
      b.document_status,
      b.supplier_name,
      case when public.has_staff_permission('view_supplier_cost') then b.supplier_cost else null end as supplier_cost,
      case when public.has_staff_permission('view_payments') or public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount) else null end as selling_price,
      case when public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) else null end as gross_profit,
      b.currency,
      b.priority,
      b.follow_up_at,
      b.created_at,
      b.updated_at
    from public.bookings b
    left join public.corporate_accounts ca on ca.id = b.corporate_account_id
    left join public.corporate_contacts cc on cc.id = b.corporate_contact_id
    where b.archived_at is null
      and public.has_staff_permission('view_bookings')
    order by b.created_at desc
    limit greatest(1, least(limit_count, 500))
  ) as guarded
  where auth.uid() is not null;
$function$;

create or replace function public.get_operations_booking_detail(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select guarded.*
  from (
    select jsonb_build_object(
      'booking', jsonb_build_object(
        'id', b.id,
        'booking_reference', b.booking_reference,
        'title', b.title,
        'booking_kind', b.booking_kind,
        'service_type', b.service_type,
        'route_or_destination', b.route_or_destination,
        'travel_start', b.travel_start,
        'travel_end', b.travel_end,
        'status', b.status,
        'payment_status', b.payment_status,
        'document_status', b.document_status,
        'supplier_name', b.supplier_name,
        'supplier_reference', b.supplier_reference,
        'supplier_currency', b.supplier_currency,
        'lpo_number', b.lpo_number,
        'approval_person', b.approval_person,
        'selling_price', case when public.has_staff_permission('view_payments') or public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount) else null end,
        'supplier_cost', case when public.has_staff_permission('view_supplier_cost') then b.supplier_cost else null end,
        'gross_profit', case when public.has_staff_permission('view_profit') then coalesce(b.selling_price, b.amount, 0) - coalesce(b.supplier_cost, 0) else null end,
        'currency', b.currency,
        'priority', b.priority,
        'staff_notes', b.staff_notes,
        'customer_notes', b.customer_notes,
        'created_at', b.created_at,
        'updated_at', b.updated_at
      ),
      'customer', case when c.id is null then null else jsonb_build_object(
        'id', c.id,
        'full_name', c.full_name,
        'email', c.email,
        'phone', c.phone,
        'whatsapp', c.whatsapp,
        'source', c.source
      ) end,
      'corporate', case when ca.id is null then null else jsonb_build_object(
        'id', ca.id,
        'company_name', ca.company_name,
        'billing_email', ca.billing_email,
        'accounts_email', ca.accounts_email,
        'payment_terms', ca.payment_terms,
        'lpo_required', ca.lpo_required,
        'credit_allowed', ca.credit_allowed,
        'monthly_billing', ca.monthly_billing,
        'trade_license_no', ca.trade_license_no,
        'trn', ca.trn,
        'phone', ca.phone,
        'status', ca.status
      ) end,
      'corporate_contact', case when cc.id is null then null else jsonb_build_object(
        'id', cc.id,
        'full_name', cc.full_name,
        'job_title', cc.job_title,
        'email', cc.email,
        'phone', cc.phone,
        'whatsapp', cc.whatsapp,
        'is_authorized_contact', cc.is_authorized_contact,
        'is_accounts_contact', cc.is_accounts_contact
      ) end,
      'passengers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', bp.id,
          'passenger_name', bp.passenger_name,
          'passenger_type', bp.passenger_type,
          'nationality', bp.nationality,
          'date_of_birth', bp.date_of_birth,
          'passport_number', bp.passport_number,
          'passport_expiry', bp.passport_expiry,
          'notes', bp.notes,
          'created_at', bp.created_at,
          'updated_at', bp.updated_at
        ) order by bp.created_at asc)
        from public.booking_passengers bp
        where bp.booking_id = b.id
      ), '[]'::jsonb),
      'booking_documents', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', bd.id,
          'document_type', bd.document_type,
          'file_name', bd.file_name,
          'storage_path', bd.storage_path,
          'external_reference', bd.external_reference,
          'visible_to_customer', bd.visible_to_customer,
          'created_at', bd.created_at
        ) order by bd.created_at desc)
        from public.booking_documents bd
        where bd.booking_id = b.id
      ), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id,
          'payment_reference', p.payment_reference,
          'amount', p.amount,
          'currency', p.currency,
          'method', p.method,
          'status', p.status,
          'received_at', p.received_at,
          'notes', p.notes,
          'proof_storage_path', p.proof_storage_path,
          'proof_file_name', p.proof_file_name,
          'proof_uploaded_at', p.proof_uploaded_at,
          'created_at', p.created_at
        ) order by p.created_at desc)
        from public.payments p
        where p.booking_id = b.id
          and public.has_staff_permission('view_payments')
      ), '[]'::jsonb),
      'supplier_payments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', sp.id,
          'supplier_name', sp.supplier_name,
          'supplier_reference', sp.supplier_reference,
          'amount_payable', sp.amount_payable,
          'amount_paid', sp.amount_paid,
          'currency', sp.currency,
          'status', sp.status,
          'due_date', sp.due_date,
          'paid_at', sp.paid_at,
          'notes', sp.notes,
          'supplier_invoice_path', sp.supplier_invoice_path,
          'supplier_invoice_file_name', sp.supplier_invoice_file_name,
          'supplier_invoice_uploaded_at', sp.supplier_invoice_uploaded_at,
          'sharepoint_invoice_url', sp.sharepoint_invoice_url,
          'created_at', sp.created_at
        ) order by sp.created_at desc)
        from public.supplier_payments sp
        where sp.booking_id = b.id
          and (public.has_staff_permission('view_supplier_cost') or public.has_staff_permission('view_payments'))
      ), '[]'::jsonb),
      'can_view_payments', public.has_staff_permission('view_payments'),
      'can_edit_payments', public.has_staff_permission('edit_payments'),
      'can_view_profit', public.has_staff_permission('view_profit'),
      'can_edit_bookings', public.has_staff_permission('edit_bookings'),
      'can_edit_documents', public.has_staff_permission('generate_documents') or public.has_staff_permission('edit_bookings'),
      'can_edit_corporates', public.has_staff_permission('edit_corporates') or public.has_staff_permission('edit_bookings')
    )
    from public.bookings b
    left join public.customers c on c.id = b.customer_id
    left join public.corporate_accounts ca on ca.id = b.corporate_account_id
    left join public.corporate_contacts cc on cc.id = b.corporate_contact_id
    where b.id = p_booking_id
      and b.archived_at is null
      and public.has_staff_permission('view_bookings')
  ) as guarded
  where auth.uid() is not null;
$function$;

create or replace function public.get_booking_workflow(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select guarded.*
  from (
    select jsonb_build_object(
      'tasks', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', t.id,
          'title', t.title,
          'task_type', t.task_type,
          'entity_type', t.entity_type,
          'entity_id', t.entity_id,
          'assigned_to', t.assigned_to,
          'assigned_to_name', sp.full_name,
          'due_at', t.due_at,
          'status', t.status,
          'priority', t.priority,
          'notes', t.notes,
          'created_by', t.created_by,
          'created_by_name', creator.full_name,
          'created_at', t.created_at,
          'updated_at', t.updated_at,
          'completed_at', t.completed_at
        ) order by case when t.status = 'completed' then 1 else 0 end, t.due_at nulls last, t.created_at desc)
        from public.tasks_reminders t
        left join public.staff_profiles sp on sp.user_id = t.assigned_to
        left join public.staff_profiles creator on creator.user_id = t.created_by
        where t.entity_type = 'booking'
          and t.entity_id = b.id
      ), '[]'::jsonb),
      'timeline', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', ae.id,
          'event_type', ae.event_type,
          'entity_type', ae.entity_type,
          'entity_id', ae.entity_id,
          'actor_user_id', ae.actor_user_id,
          'actor_name', actor.full_name,
          'metadata', ae.metadata,
          'created_at', ae.created_at
        ) order by ae.created_at desc)
        from public.audit_events ae
        left join public.staff_profiles actor on actor.user_id = ae.actor_user_id
        where ae.entity_type = 'booking'
          and ae.entity_id = b.id
        limit 80
      ), '[]'::jsonb),
      'can_edit_tasks', public.has_staff_permission('edit_bookings') or public.has_staff_permission('create_bookings'),
      'can_view_activity', public.has_staff_permission('view_reports') or public.has_staff_permission('edit_bookings')
    )
    from public.bookings b
    where b.id = p_booking_id
      and b.archived_at is null
      and public.has_staff_permission('view_bookings')
  ) as guarded
  where auth.uid() is not null;
$function$;

revoke execute on function public.list_operations_bookings(integer) from public, anon;
revoke execute on function public.get_operations_booking_detail(uuid) from public, anon;
revoke execute on function public.get_booking_workflow(uuid) from public, anon;

grant execute on function public.list_operations_bookings(integer) to authenticated, service_role;
grant execute on function public.get_operations_booking_detail(uuid) to authenticated, service_role;
grant execute on function public.get_booking_workflow(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
