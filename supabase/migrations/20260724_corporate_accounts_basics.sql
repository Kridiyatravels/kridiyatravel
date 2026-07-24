-- Corporate account basics for staff operations.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.list_corporate_accounts()
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
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
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cc.id,
        'full_name', cc.full_name,
        'job_title', cc.job_title,
        'email', cc.email,
        'phone', cc.phone,
        'whatsapp', cc.whatsapp,
        'is_authorized_contact', cc.is_authorized_contact,
        'is_accounts_contact', cc.is_accounts_contact,
        'active', cc.active
      ) order by cc.created_at asc)
      from public.corporate_contacts cc
      where cc.corporate_account_id = ca.id and cc.active = true
    ), '[]'::jsonb),
    'booking_count', (
      select count(*) from public.bookings b where b.corporate_account_id = ca.id and b.archived_at is null
    ),
    'booking_value', (
      select coalesce(sum(coalesce(b.selling_price, b.amount, 0)), 0)
      from public.bookings b
      where b.corporate_account_id = ca.id and b.archived_at is null
    )
  ) order by ca.company_name), '[]'::jsonb)
  from public.corporate_accounts ca
  where ca.archived_at is null
    and (public.has_staff_permission('view_corporates') or public.has_staff_permission('edit_corporates') or public.has_staff_permission('manage_staff'));
$function$;

create or replace function public.create_corporate_account(
  p_company_name text,
  p_billing_email text default null,
  p_accounts_email text default null,
  p_phone text default null,
  p_address text default null,
  p_trade_license_no text default null,
  p_trn text default null,
  p_payment_terms text default 'payment_before_booking',
  p_credit_allowed boolean default false,
  p_monthly_billing boolean default false,
  p_lpo_required boolean default false,
  p_status text default 'prospect',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  insert into public.corporate_accounts (
    company_name, billing_email, accounts_email, phone, address,
    trade_license_no, trn, payment_terms, credit_allowed, monthly_billing,
    lpo_required, status, notes, created_by
  ) values (
    trim(p_company_name), nullif(trim(coalesce(p_billing_email, '')), ''), nullif(trim(coalesce(p_accounts_email, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_address, '')), ''),
    nullif(trim(coalesce(p_trade_license_no, '')), ''), nullif(trim(coalesce(p_trn, '')), ''),
    coalesce(nullif(p_payment_terms, ''), 'payment_before_booking'), coalesce(p_credit_allowed, false), coalesce(p_monthly_billing, false),
    coalesce(p_lpo_required, false), coalesce(nullif(p_status, ''), 'prospect'), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.create_corporate_contact(
  p_corporate_account_id uuid,
  p_full_name text,
  p_job_title text default null,
  p_email text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_is_authorized_contact boolean default false,
  p_is_accounts_contact boolean default false,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_customer_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Corporate edit permission required';
  end if;

  if not exists (select 1 from public.corporate_accounts where id = p_corporate_account_id and archived_at is null) then
    raise exception 'Corporate account not found';
  end if;

  insert into public.customers (
    customer_type, full_name, email, phone, whatsapp, source, notes, created_by
  ) values (
    'corporate_contact', trim(p_full_name), nullif(trim(coalesce(p_email, '')), ''), nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(coalesce(p_whatsapp, '')), ''), 'corporate', nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_customer_id;

  insert into public.corporate_contacts (
    corporate_account_id, customer_id, full_name, job_title, email, phone, whatsapp,
    is_authorized_contact, is_accounts_contact, notes, created_by
  ) values (
    p_corporate_account_id, v_customer_id, trim(p_full_name), nullif(trim(coalesce(p_job_title, '')), ''),
    nullif(trim(coalesce(p_email, '')), ''), nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_whatsapp, '')), ''),
    coalesce(p_is_authorized_contact, false), coalesce(p_is_accounts_contact, false), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$function$;
