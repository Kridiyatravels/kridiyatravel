-- Staff approval bridge for corporate account applications.
-- Apply after 20260728_corporate_portal_access_layer.sql.
--
-- Flow:
-- 1. Corporate site submits an application into public.enquiries.
-- 2. Staff reviews it in admin.
-- 3. Staff creates the company's Supabase Auth user manually.
-- 4. Staff calls approve_corporate_application with the enquiry id and user id.
-- 5. The company can log in to corporate-account.html and only sees its own company data.

begin;

create or replace function public.approve_corporate_application(
  p_enquiry_id uuid,
  p_auth_user_id uuid default null,
  p_role text default 'travel_coordinator',
  p_can_request boolean default true,
  p_can_approve_quotes boolean default false,
  p_can_view_finance boolean default false,
  p_can_view_documents boolean default true,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_user_id uuid := auth.uid();
  v_enquiry public.enquiries%rowtype;
  v_details jsonb;
  v_company_name text;
  v_contact_name text;
  v_job_title text;
  v_email text;
  v_phone text;
  v_whatsapp text;
  v_billing_email text;
  v_payment_terms text;
  v_lpo_required boolean;
  v_route text;
  v_customer_id uuid;
  v_booking_reference text;
  v_note text;
  v_booking_id uuid;
  v_account_id uuid;
  v_contact_id uuid;
  v_member_id uuid;
  v_enquiry_reference text;
  v_portal_status text := 'pending_user';
begin
  if v_actor_user_id is not null then
    if not public.has_staff_permission('create_bookings') then
      raise exception 'Booking creation permission required';
    end if;

    if not public.has_staff_permission('edit_corporates') then
      raise exception 'Corporate edit permission required';
    end if;
  end if;

  select *
  into v_enquiry
  from public.enquiries
  where id = p_enquiry_id;

  if not found then
    raise exception 'Corporate application enquiry not found';
  end if;

  v_enquiry_reference := v_enquiry.reference;

  select id, corporate_account_id, corporate_contact_id
  into v_booking_id, v_account_id, v_contact_id
  from public.bookings
  where enquiry_id = p_enquiry_id
    and archived_at is null
  order by created_at asc
  limit 1;

  if v_booking_id is null then
    v_details := coalesce(v_enquiry.details, '{}'::jsonb);
    v_company_name := nullif(trim(coalesce(v_details ->> 'Company_name', '')), '');
    v_contact_name := nullif(trim(coalesce(v_details ->> 'Name', v_enquiry.full_name, '')), '');
    v_job_title := nullif(trim(coalesce(v_details ->> 'Job_title', '')), '');
    v_email := nullif(trim(coalesce(v_enquiry.email, v_details ->> 'Email', '')), '');
    v_phone := nullif(trim(coalesce(v_enquiry.phone, v_details ->> 'Phone', '')), '');
    v_whatsapp := nullif(trim(coalesce(v_details ->> 'WhatsApp', v_phone, '')), '');
    v_billing_email := nullif(trim(coalesce(v_details ->> 'Billing_email', v_email, '')), '');
    v_payment_terms := lower(replace(coalesce(v_details ->> 'Preferred_payment_terms', 'payment_before_booking'), ' ', '_'));
    v_lpo_required := lower(coalesce(v_details ->> 'LPO_required', '')) = 'yes';
    v_route := nullif(trim(coalesce(v_details ->> 'Route_or_destination', v_enquiry.summary, '')), '');

    if v_company_name is null then
      raise exception 'Company name is required on the enquiry details';
    end if;

    select id
    into v_account_id
    from public.corporate_accounts
    where lower(company_name) = lower(v_company_name)
      and archived_at is null
    order by created_at asc
    limit 1;

    if v_account_id is null then
      insert into public.corporate_accounts (
        company_name, billing_email, accounts_email, phone, payment_terms,
        credit_allowed, monthly_billing, lpo_required, status, notes, created_by
      ) values (
        v_company_name, v_billing_email, v_billing_email, v_phone,
        coalesce(nullif(v_payment_terms, ''), 'payment_before_booking'),
        false, false, v_lpo_required, 'active',
        'Approved from corporate application ' || v_enquiry_reference,
        v_actor_user_id
      ) returning id into v_account_id;
    end if;

    if v_contact_name is not null then
      select cc.id, cc.customer_id
      into v_contact_id, v_customer_id
      from public.corporate_contacts cc
      where cc.corporate_account_id = v_account_id
        and cc.active = true
        and (
          lower(cc.email) = lower(v_email)
          or (cc.email is null and lower(cc.full_name) = lower(v_contact_name))
        )
      order by cc.created_at asc
      limit 1;

      if v_contact_id is null then
        insert into public.customers (
          customer_type, full_name, email, phone, whatsapp, source, notes, created_by
        ) values (
          'corporate_contact', v_contact_name, v_email, v_phone, v_whatsapp,
          'corporate', 'Approved from enquiry ' || v_enquiry_reference, v_actor_user_id
        ) returning id into v_customer_id;

        insert into public.corporate_contacts (
          corporate_account_id, customer_id, full_name, job_title, email, phone, whatsapp,
          is_authorized_contact, is_accounts_contact, notes, created_by
        ) values (
          v_account_id, v_customer_id, v_contact_name, v_job_title, v_email, v_phone, v_whatsapp,
          true, coalesce(v_billing_email = v_email, false),
          'Approved from enquiry ' || v_enquiry_reference, v_actor_user_id
        ) returning id into v_contact_id;
      end if;
    end if;

    v_booking_reference := public.next_booking_reference();
    v_note := concat_ws(E'\n',
      'Approved corporate application ' || v_enquiry_reference,
      'Original summary: ' || v_enquiry.summary,
      'Requested services: ' || nullif(v_details ->> 'Service_needed', ''),
      'Monthly volume: ' || nullif(v_details ->> 'Monthly_travel_volume', ''),
      'Billing/LPO: ' || nullif(v_details ->> 'Billing_or_LPO_requirement', ''),
      'Original notes: ' || nullif(v_details ->> 'Notes', ''),
      nullif(trim(coalesce(p_notes, '')), '')
    );

    insert into public.bookings (
      booking_reference,
      enquiry_id,
      service_type,
      title,
      booking_kind,
      customer_id,
      corporate_account_id,
      corporate_contact_id,
      route_or_destination,
      supplier_name,
      staff_notes,
      source,
      status,
      payment_status,
      created_by
    ) values (
      v_booking_reference,
      p_enquiry_id,
      'corporate'::public.booking_service_type,
      v_company_name || ' corporate account',
      'corporate',
      v_customer_id,
      v_account_id,
      v_contact_id,
      v_route,
      null,
      nullif(v_note, ''),
      'corporate',
      'enquiry',
      'not_requested',
      v_actor_user_id
    ) returning id into v_booking_id;
  end if;

  if v_account_id is null then
    raise exception 'Corporate account could not be resolved from application';
  end if;

  update public.corporate_accounts
  set status = 'active',
      notes = concat_ws(E'\n', nullif(notes, ''), 'Approved from corporate application ' || v_enquiry_reference),
      updated_at = now()
  where id = v_account_id
    and archived_at is null;

  if p_auth_user_id is not null then
    if not exists (select 1 from auth.users where id = p_auth_user_id) then
      raise exception 'Corporate Auth user not found';
    end if;

    insert into public.corporate_portal_members (
      corporate_account_id,
      corporate_contact_id,
      user_id,
      role,
      status,
      can_request,
      can_approve_quotes,
      can_view_finance,
      can_view_documents,
      notes,
      invited_by
    ) values (
      v_account_id,
      v_contact_id,
      p_auth_user_id,
      coalesce(nullif(trim(coalesce(p_role, '')), ''), 'travel_coordinator'),
      'active',
      coalesce(p_can_request, true),
      coalesce(p_can_approve_quotes, false),
      coalesce(p_can_view_finance, false),
      coalesce(p_can_view_documents, true),
      concat_ws(E'\n', 'Approved from enquiry ' || v_enquiry_reference, nullif(trim(coalesce(p_notes, '')), '')),
      v_actor_user_id
    )
    on conflict (corporate_account_id, user_id)
    do update set
      corporate_contact_id = excluded.corporate_contact_id,
      role = excluded.role,
      status = excluded.status,
      can_request = excluded.can_request,
      can_approve_quotes = excluded.can_approve_quotes,
      can_view_finance = excluded.can_view_finance,
      can_view_documents = excluded.can_view_documents,
      notes = excluded.notes,
      updated_at = now()
    returning id into v_member_id;

    v_portal_status := 'active';
  end if;

  update public.enquiries
  set status = 'confirmed',
      details = jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(details, '{}'::jsonb),
            '{Corporate_approval_status}',
            to_jsonb('approved'::text),
            true
          ),
          '{Corporate_portal_status}',
          to_jsonb(v_portal_status),
          true
        ),
        '{Corporate_approved_at}',
        to_jsonb(now()),
        true
      ),
      updated_at = now()
  where id = p_enquiry_id;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_actor_user_id,
    p_auth_user_id,
    'corporate_application.approved',
    'corporate_account',
    v_account_id,
    jsonb_build_object(
      'enquiry_id', p_enquiry_id,
      'enquiry_reference', v_enquiry_reference,
      'booking_id', v_booking_id,
      'corporate_contact_id', v_contact_id,
      'portal_member_id', v_member_id,
      'portal_status', v_portal_status
    )
  );

  return jsonb_build_object(
    'ok', true,
    'enquiry_id', p_enquiry_id,
    'enquiry_reference', v_enquiry_reference,
    'booking_id', v_booking_id,
    'corporate_account_id', v_account_id,
    'corporate_contact_id', v_contact_id,
    'portal_member_id', v_member_id,
    'portal_status', v_portal_status
  );
end;
$function$;

revoke execute on function public.approve_corporate_application(uuid, uuid, text, boolean, boolean, boolean, boolean, text) from public, anon;
grant execute on function public.approve_corporate_application(uuid, uuid, text, boolean, boolean, boolean, boolean, text) to authenticated, service_role;

commit;
