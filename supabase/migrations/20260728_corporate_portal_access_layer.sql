-- Kridiya Business Travel - corporate client portal access layer.
-- Apply after the existing admin/corporate booking migrations are live.
--
-- Purpose:
-- - Staff/admin keeps full control in admin.kridiyatravel.com.
-- - Approved corporate users can log in and see only their company records.
-- - Corporate users can submit new requests into the same bookings system.
-- - Corporate users never see supplier cost, gross profit, staff notes, or other companies.

begin;

create table if not exists public.corporate_portal_members (
  id uuid primary key default gen_random_uuid(),
  corporate_account_id uuid not null references public.corporate_accounts(id) on delete cascade,
  corporate_contact_id uuid references public.corporate_contacts(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'requester',
  status text not null default 'active',
  can_request boolean not null default true,
  can_approve_quotes boolean not null default false,
  can_view_finance boolean not null default false,
  can_view_documents boolean not null default true,
  notes text,
  invited_by uuid references auth.users(id) on delete set null,
  invited_at timestamptz not null default now(),
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint corporate_portal_members_role_check
    check (role in ('owner', 'travel_coordinator', 'finance', 'requester', 'viewer')),
  constraint corporate_portal_members_status_check
    check (status in ('invited', 'active', 'suspended', 'revoked')),
  constraint corporate_portal_members_unique_user_company unique (corporate_account_id, user_id)
);

create index if not exists corporate_portal_members_user_idx
on public.corporate_portal_members(user_id)
where status in ('invited', 'active');

create index if not exists corporate_portal_members_account_idx
on public.corporate_portal_members(corporate_account_id);

drop trigger if exists corporate_portal_members_set_updated_at on public.corporate_portal_members;
create trigger corporate_portal_members_set_updated_at
before update on public.corporate_portal_members
for each row execute function public.set_updated_at();

alter table public.corporate_portal_members enable row level security;

drop policy if exists corporate_portal_members_select_self_or_staff on public.corporate_portal_members;
create policy corporate_portal_members_select_self_or_staff
on public.corporate_portal_members for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.is_staff()
);

drop policy if exists corporate_portal_members_write_staff on public.corporate_portal_members;
create policy corporate_portal_members_write_staff
on public.corporate_portal_members for all
to authenticated
using (public.has_staff_permission('edit_corporates'))
with check (public.has_staff_permission('edit_corporates'));

revoke all on public.corporate_portal_members from anon, authenticated;
grant select on public.corporate_portal_members to authenticated;
grant insert, update, delete on public.corporate_portal_members to authenticated;

create or replace function public.is_corporate_portal_member(p_corporate_account_id uuid)
returns boolean
language sql
security definer
set search_path to 'public'
stable
as $function$
  select exists (
    select 1
    from public.corporate_portal_members cpm
    join public.corporate_accounts ca on ca.id = cpm.corporate_account_id
    where cpm.user_id = (select auth.uid())
      and cpm.corporate_account_id = p_corporate_account_id
      and cpm.status = 'active'
      and ca.archived_at is null
      and ca.status in ('active', 'approved', 'customer', 'prospect')
  );
$function$;

create or replace function public.manage_corporate_portal_member(
  p_corporate_account_id uuid,
  p_user_id uuid,
  p_corporate_contact_id uuid default null,
  p_role text default 'requester',
  p_status text default 'active',
  p_can_request boolean default true,
  p_can_approve_quotes boolean default false,
  p_can_view_finance boolean default false,
  p_can_view_documents boolean default true,
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

  if not exists (
    select 1 from public.corporate_accounts
    where id = p_corporate_account_id and archived_at is null
  ) then
    raise exception 'Corporate account not found';
  end if;

  if p_corporate_contact_id is not null and not exists (
    select 1 from public.corporate_contacts
    where id = p_corporate_contact_id
      and corporate_account_id = p_corporate_account_id
      and active = true
  ) then
    raise exception 'Corporate contact does not belong to selected company';
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
    p_corporate_account_id,
    p_corporate_contact_id,
    p_user_id,
    coalesce(nullif(trim(coalesce(p_role, '')), ''), 'requester'),
    coalesce(nullif(trim(coalesce(p_status, '')), ''), 'active'),
    coalesce(p_can_request, true),
    coalesce(p_can_approve_quotes, false),
    coalesce(p_can_view_finance, false),
    coalesce(p_can_view_documents, true),
    nullif(trim(coalesce(p_notes, '')), ''),
    auth.uid()
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
  returning id into v_id;

  insert into public.audit_events (actor_user_id, target_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    p_user_id,
    'corporate_portal.member_upserted',
    'corporate_account',
    p_corporate_account_id,
    jsonb_build_object('member_id', v_id, 'role', p_role, 'status', p_status)
  );

  return v_id;
end;
$function$;

create or replace function public.get_my_corporate_portal()
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'corporate_account_id', ca.id,
    'company_name', ca.company_name,
    'status', ca.status,
    'payment_terms', ca.payment_terms,
    'monthly_billing', ca.monthly_billing,
    'lpo_required', ca.lpo_required,
    'member_role', cpm.role,
    'can_request', cpm.can_request,
    'can_approve_quotes', cpm.can_approve_quotes,
    'can_view_finance', cpm.can_view_finance,
    'can_view_documents', cpm.can_view_documents
  ) order by ca.company_name), '[]'::jsonb)
  from public.corporate_portal_members cpm
  join public.corporate_accounts ca on ca.id = cpm.corporate_account_id
  where cpm.user_id = (select auth.uid())
    and cpm.status = 'active'
    and ca.archived_at is null;
$function$;

create or replace function public.list_my_corporate_bookings(
  p_corporate_account_id uuid default null,
  p_limit integer default 100
)
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id,
    'booking_reference', b.booking_reference,
    'title', b.title,
    'service_type', b.service_type,
    'route_or_destination', b.route_or_destination,
    'travel_start', b.travel_start,
    'travel_end', b.travel_end,
    'status', b.status,
    'payment_status', b.payment_status,
    'document_status', b.document_status,
    'amount', case when cpm.can_view_finance then coalesce(b.selling_price, b.amount) else null end,
    'currency', b.currency,
    'created_at', b.created_at,
    'updated_at', b.updated_at
  ) order by b.created_at desc), '[]'::jsonb)
  from public.bookings b
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where b.archived_at is null
    and b.booking_kind = 'corporate'
    and (p_corporate_account_id is null or b.corporate_account_id = p_corporate_account_id)
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$function$;

create or replace function public.get_my_corporate_booking_detail(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
stable
as $function$
  select jsonb_build_object(
    'booking', jsonb_build_object(
      'id', b.id,
      'booking_reference', b.booking_reference,
      'title', b.title,
      'service_type', b.service_type,
      'route_or_destination', b.route_or_destination,
      'travel_start', b.travel_start,
      'travel_end', b.travel_end,
      'status', b.status,
      'payment_status', b.payment_status,
      'document_status', b.document_status,
      'amount', case when cpm.can_view_finance then coalesce(b.selling_price, b.amount) else null end,
      'currency', b.currency,
      'customer_notes', b.customer_notes,
      'created_at', b.created_at,
      'updated_at', b.updated_at
    ),
    'corporate', jsonb_build_object(
      'id', ca.id,
      'company_name', ca.company_name,
      'payment_terms', ca.payment_terms,
      'monthly_billing', ca.monthly_billing,
      'lpo_required', ca.lpo_required
    ),
    'documents', case when cpm.can_view_documents then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bd.id,
        'document_type', bd.document_type,
        'file_name', bd.file_name,
        'created_at', bd.created_at
      ) order by bd.created_at desc)
      from public.booking_documents bd
      where bd.booking_id = b.id
        and bd.visible_to_customer = true
    ), '[]'::jsonb) else '[]'::jsonb end,
    'payments', case when cpm.can_view_finance then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'payment_reference', p.payment_reference,
        'amount', p.amount,
        'currency', p.currency,
        'method', p.method,
        'status', p.status,
        'received_at', p.received_at,
        'created_at', p.created_at
      ) order by p.created_at desc)
      from public.payments p
      where p.booking_id = b.id
        and p.payment_direction = 'customer_in'
    ), '[]'::jsonb) else '[]'::jsonb end
  )
  from public.bookings b
  join public.corporate_accounts ca on ca.id = b.corporate_account_id
  join public.corporate_portal_members cpm
    on cpm.corporate_account_id = b.corporate_account_id
   and cpm.user_id = (select auth.uid())
   and cpm.status = 'active'
  where b.id = p_booking_id
    and b.archived_at is null
    and b.booking_kind = 'corporate';
$function$;

create or replace function public.create_my_corporate_request(
  p_corporate_account_id uuid,
  p_title text,
  p_service_type public.booking_service_type,
  p_route_or_destination text default null,
  p_travel_start date default null,
  p_travel_end date default null,
  p_customer_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_booking_id uuid;
  v_reference text;
  v_contact_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select corporate_contact_id
  into v_contact_id
  from public.corporate_portal_members
  where user_id = auth.uid()
    and corporate_account_id = p_corporate_account_id
    and status = 'active'
    and can_request = true;

  if not found then
    raise exception 'Corporate request access denied';
  end if;

  v_reference := public.next_booking_reference();

  insert into public.bookings (
    user_id,
    booking_reference,
    service_type,
    title,
    booking_kind,
    corporate_account_id,
    corporate_contact_id,
    route_or_destination,
    travel_start,
    travel_end,
    customer_notes,
    source,
    status,
    payment_status,
    created_by
  ) values (
    auth.uid(),
    v_reference,
    p_service_type,
    trim(p_title),
    'corporate',
    p_corporate_account_id,
    v_contact_id,
    nullif(trim(coalesce(p_route_or_destination, '')), ''),
    p_travel_start,
    p_travel_end,
    nullif(trim(coalesce(p_customer_notes, '')), ''),
    'corporate_portal',
    'enquiry',
    'not_requested',
    auth.uid()
  ) returning id into v_booking_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'corporate_portal.request_created',
    'booking',
    v_booking_id,
    jsonb_build_object(
      'reference', v_reference,
      'corporate_account_id', p_corporate_account_id,
      'service_type', p_service_type
    )
  );

  return v_booking_id;
end;
$function$;

revoke execute on function public.is_corporate_portal_member(uuid) from public, anon;
revoke execute on function public.manage_corporate_portal_member(uuid, uuid, uuid, text, text, boolean, boolean, boolean, boolean, text) from public, anon;
revoke execute on function public.get_my_corporate_portal() from public, anon;
revoke execute on function public.list_my_corporate_bookings(uuid, integer) from public, anon;
revoke execute on function public.get_my_corporate_booking_detail(uuid) from public, anon;
revoke execute on function public.create_my_corporate_request(uuid, text, public.booking_service_type, text, date, date, text) from public, anon;

grant execute on function public.is_corporate_portal_member(uuid) to authenticated, service_role;
grant execute on function public.manage_corporate_portal_member(uuid, uuid, uuid, text, text, boolean, boolean, boolean, boolean, text) to authenticated, service_role;
grant execute on function public.get_my_corporate_portal() to authenticated, service_role;
grant execute on function public.list_my_corporate_bookings(uuid, integer) to authenticated, service_role;
grant execute on function public.get_my_corporate_booking_detail(uuid) to authenticated, service_role;
grant execute on function public.create_my_corporate_request(uuid, text, public.booking_service_type, text, date, date, text) to authenticated, service_role;

commit;
