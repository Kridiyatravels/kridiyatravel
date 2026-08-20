-- Corporate account/contact editing capabilities and complete contact visibility.
-- This migration adds RPC-only write paths; it does not grant direct table access.

create or replace function public.update_operations_corporate_account(
  p_corporate_account_id uuid,
  p_company_name text,
  p_trade_license_no text,
  p_trn text,
  p_address text,
  p_phone text,
  p_billing_email text,
  p_accounts_email text,
  p_payment_terms text,
  p_credit_allowed boolean,
  p_lpo_required boolean,
  p_monthly_billing boolean,
  p_status text,
  p_notes text,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.corporate_accounts%rowtype;
  v_after public.corporate_accounts%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Permission denied';
  end if;

  if p_corporate_account_id is null then
    raise exception 'Corporate account is required';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected corporate account version is required';
  end if;

  if char_length(trim(coalesce(p_company_name, ''))) not between 2 and 180 then
    raise exception 'Company name must be between 2 and 180 characters';
  end if;

  if nullif(trim(coalesce(p_billing_email, '')), '') is not null
     and char_length(trim(p_billing_email)) > 320 then
    raise exception 'Billing email must not exceed 320 characters';
  end if;

  if nullif(trim(coalesce(p_accounts_email, '')), '') is not null
     and char_length(trim(p_accounts_email)) > 320 then
    raise exception 'Accounts email must not exceed 320 characters';
  end if;

  if nullif(trim(coalesce(p_phone, '')), '') is not null
     and char_length(trim(p_phone)) > 40 then
    raise exception 'Phone must not exceed 40 characters';
  end if;

  if p_payment_terms not in (
    'payment_before_booking',
    'credit_approved',
    'monthly_billing'
  ) then
    raise exception 'Invalid corporate payment terms';
  end if;

  if p_status not in ('active', 'prospect', 'on_hold', 'inactive', 'archived') then
    raise exception 'Invalid corporate account status';
  end if;

  if p_credit_allowed is null
     or p_lpo_required is null
     or p_monthly_billing is null then
    raise exception 'Corporate billing controls are required';
  end if;

  select ca.*
  into v_before
  from public.corporate_accounts ca
  where ca.id = p_corporate_account_id
    and ca.archived_at is null;

  if not found then
    raise exception 'Corporate account not found';
  end if;

  update public.corporate_accounts ca
  set
    company_name = trim(p_company_name),
    trade_license_no = nullif(trim(coalesce(p_trade_license_no, '')), ''),
    trn = nullif(trim(coalesce(p_trn, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    billing_email = nullif(lower(trim(coalesce(p_billing_email, ''))), ''),
    accounts_email = nullif(lower(trim(coalesce(p_accounts_email, ''))), ''),
    payment_terms = p_payment_terms,
    credit_allowed = p_credit_allowed,
    lpo_required = p_lpo_required,
    monthly_billing = p_monthly_billing,
    status = p_status,
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    updated_at = clock_timestamp()
  where ca.id = p_corporate_account_id
    and ca.archived_at is null
    and ca.updated_at = p_expected_updated_at
  returning ca.* into v_after;

  if not found then
    raise exception 'Corporate account changed after this page was loaded. Reload and review the latest values.';
  end if;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'corporate_account.details_updated',
    'corporate_account',
    v_after.id,
    jsonb_build_object(
      'before', to_jsonb(v_before),
      'after', to_jsonb(v_after)
    )
  );

  return v_after.updated_at;
end;
$function$;

create or replace function public.update_operations_corporate_contact(
  p_corporate_contact_id uuid,
  p_full_name text,
  p_job_title text,
  p_email text,
  p_phone text,
  p_whatsapp text,
  p_is_authorized_contact boolean,
  p_is_accounts_contact boolean,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.corporate_contacts%rowtype;
  v_after public.corporate_contacts%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Permission denied';
  end if;

  if p_corporate_contact_id is null then
    raise exception 'Corporate contact is required';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected corporate contact version is required';
  end if;

  if char_length(trim(coalesce(p_full_name, ''))) not between 2 and 160 then
    raise exception 'Contact name must be between 2 and 160 characters';
  end if;

  if nullif(trim(coalesce(p_email, '')), '') is not null
     and char_length(trim(p_email)) > 320 then
    raise exception 'Email must not exceed 320 characters';
  end if;

  if nullif(trim(coalesce(p_phone, '')), '') is not null
     and char_length(trim(p_phone)) > 40 then
    raise exception 'Phone must not exceed 40 characters';
  end if;

  if nullif(trim(coalesce(p_whatsapp, '')), '') is not null
     and char_length(trim(p_whatsapp)) > 40 then
    raise exception 'WhatsApp must not exceed 40 characters';
  end if;

  if p_is_authorized_contact is null or p_is_accounts_contact is null then
    raise exception 'Corporate contact role flags are required';
  end if;

  select cc.*
  into v_before
  from public.corporate_contacts cc
  where cc.id = p_corporate_contact_id;

  if not found then
    raise exception 'Corporate contact not found';
  end if;

  update public.corporate_contacts cc
  set
    full_name = trim(p_full_name),
    job_title = nullif(trim(coalesce(p_job_title, '')), ''),
    email = nullif(lower(trim(coalesce(p_email, ''))), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    whatsapp = nullif(trim(coalesce(p_whatsapp, '')), ''),
    is_authorized_contact = p_is_authorized_contact,
    is_accounts_contact = p_is_accounts_contact,
    updated_at = clock_timestamp()
  where cc.id = p_corporate_contact_id
    and cc.updated_at = p_expected_updated_at
  returning cc.* into v_after;

  if not found then
    raise exception 'Corporate contact changed after this page was loaded. Reload and review the latest values.';
  end if;

  -- Corporate contacts are mirrored into customers when created. Keep the linked
  -- customer identity fields synchronized so bookings do not retain stale details.
  if v_after.customer_id is not null then
    update public.customers c
    set
      full_name = v_after.full_name,
      email = v_after.email,
      phone = v_after.phone,
      whatsapp = v_after.whatsapp,
      updated_at = v_after.updated_at
    where c.id = v_after.customer_id
      and c.customer_type = 'corporate_contact'
      and c.archived_at is null;
  end if;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'corporate_contact.details_updated',
    'corporate_contact',
    v_after.id,
    jsonb_build_object(
      'corporate_account_id', v_after.corporate_account_id,
      'linked_customer_id', v_after.customer_id,
      'before', to_jsonb(v_before),
      'after', to_jsonb(v_after)
    )
  );

  return v_after.updated_at;
end;
$function$;

-- Replace the existing corporate list/read RPC so the account detail page can
-- show inactive contacts and obtain the versions required for optimistic locking.
create or replace function public.list_corporate_accounts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  -- Preserve the established effective access of this existing read path:
  -- explicit corporate viewers/editors and staff-management users can read it.
  if not (
    public.has_staff_permission('view_corporates')
    or public.has_staff_permission('edit_corporates')
    or public.has_staff_permission('manage_staff')
  ) then
    raise exception 'Permission denied';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ca.id,
        'company_name', ca.company_name,
        'trade_license_no', ca.trade_license_no,
        'trn', ca.trn,
        'billing_email', ca.billing_email,
        'accounts_email', ca.accounts_email,
        'phone', ca.phone,
        'address', ca.address,
        'payment_terms', ca.payment_terms,
        'credit_allowed', ca.credit_allowed,
        'monthly_billing', ca.monthly_billing,
        'lpo_required', ca.lpo_required,
        'status', ca.status,
        'notes', ca.notes,
        'created_at', ca.created_at,
        'updated_at', ca.updated_at,
        'contacts', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', cc.id,
              'customer_id', cc.customer_id,
              'full_name', cc.full_name,
              'job_title', cc.job_title,
              'email', cc.email,
              'phone', cc.phone,
              'whatsapp', cc.whatsapp,
              'is_authorized_contact', cc.is_authorized_contact,
              'is_accounts_contact', cc.is_accounts_contact,
              'active', cc.active,
              'notes', cc.notes,
              'created_at', cc.created_at,
              'updated_at', cc.updated_at
            )
            order by cc.active desc, cc.created_at asc
          )
          from public.corporate_contacts cc
          where cc.corporate_account_id = ca.id
        ), '[]'::jsonb),
        'booking_count', (
          select count(*)
          from public.bookings b
          where b.corporate_account_id = ca.id
            and b.archived_at is null
        ),
        'booking_value', (
          select coalesce(sum(coalesce(b.selling_price, b.amount, 0)), 0)
          from public.bookings b
          where b.corporate_account_id = ca.id
            and b.archived_at is null
        )
      )
      order by ca.company_name
    ),
    '[]'::jsonb
  )
  into v_result
  from public.corporate_accounts ca
  where ca.archived_at is null;

  return v_result;
end;
$function$;

revoke execute on function public.update_operations_corporate_account(
  uuid, text, text, text, text, text, text, text, text,
  boolean, boolean, boolean, text, text, timestamptz
) from public, anon;
grant execute on function public.update_operations_corporate_account(
  uuid, text, text, text, text, text, text, text, text,
  boolean, boolean, boolean, text, text, timestamptz
) to authenticated, service_role;

revoke execute on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, timestamptz
) from public, anon;
grant execute on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, timestamptz
) to authenticated, service_role;

revoke execute on function public.list_corporate_accounts() from public, anon;
grant execute on function public.list_corporate_accounts() to authenticated, service_role;

comment on function public.update_operations_corporate_account(
  uuid, text, text, text, text, text, text, text, text,
  boolean, boolean, boolean, text, text, timestamptz
) is 'Permission-gated corporate account detail update with optimistic locking and audit logging.';

comment on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, timestamptz
) is 'Permission-gated corporate contact update with optimistic locking, linked-customer synchronization, and audit logging.';

comment on function public.list_corporate_accounts()
is 'Lists non-archived corporate accounts, including active and inactive contacts and concurrency timestamps.';

notify pgrst, 'reload schema';
