-- Final operations document archive and governed staff-template lock-down.
--
-- Apply only after create_operations_document is live and the legacy static
-- admin has switched its Save & Print action to that RPC. This migration:
--   * adds permission-gated document list/detail RPCs;
--   * removes direct authenticated writes to public.documents;
--   * narrows staff document reads to generate_documents while preserving
--     the existing customer-owned enquiry-document read path;
--   * adds audited, permission-gated template override mutation RPCs; and
--   * removes direct authenticated template override mutations.

create or replace function public.list_operations_documents(
  p_search text default null,
  p_document_type text default null,
  p_created_from timestamptz default null,
  p_created_to timestamptz default null,
  p_limit integer default 100,
  p_after_created_at timestamptz default null,
  p_after_id uuid default null
)
returns table (
  id uuid,
  document_number text,
  document_type text,
  enquiry_id uuid,
  customer_name text,
  customer_email text,
  amount_total numeric,
  currency text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_document_type text := nullif(lower(trim(coalesce(p_document_type, ''))), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('generate_documents') then
    raise exception 'Document generation permission required';
  end if;

  if (p_after_created_at is null) <> (p_after_id is null) then
    raise exception 'Both document pagination cursor values are required';
  end if;

  if p_created_from is not null
    and p_created_to is not null
    and p_created_to < p_created_from
  then
    raise exception 'Document date range is invalid';
  end if;

  if v_document_type is not null
    and not exists (
      select 1
      from pg_catalog.pg_type t
      join pg_catalog.pg_namespace n
        on n.oid = t.typnamespace
      join pg_catalog.pg_enum e
        on e.enumtypid = t.oid
      where n.nspname = 'public'
        and t.typname = 'document_type'
        and e.enumlabel = v_document_type
    )
  then
    raise exception 'Invalid document type';
  end if;

  return query
  select
    d.id,
    d.document_number,
    d.document_type::text,
    d.enquiry_id,
    d.customer_name,
    d.customer_email,
    d.amount_total,
    d.currency,
    d.created_by,
    sp.full_name,
    d.created_at
  from public.documents d
  left join public.staff_profiles sp
    on sp.user_id = d.created_by
  where (
      v_search is null
      or strpos(lower(d.document_number), lower(v_search)) > 0
      or strpos(lower(d.customer_name), lower(v_search)) > 0
      or strpos(lower(coalesce(d.customer_email, '')), lower(v_search)) > 0
    )
    and (
      v_document_type is null
      or d.document_type::text = v_document_type
    )
    and (p_created_from is null or d.created_at >= p_created_from)
    and (p_created_to is null or d.created_at <= p_created_to)
    and (
      p_after_created_at is null
      or d.created_at < p_after_created_at
      or (d.created_at = p_after_created_at and d.id < p_after_id)
    )
  order by d.created_at desc, d.id desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$function$;

create or replace function public.get_operations_document_detail(
  p_document_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('generate_documents') then
    raise exception 'Document generation permission required';
  end if;

  if p_document_id is null then
    raise exception 'Document id is required';
  end if;

  select jsonb_build_object(
    'document', jsonb_build_object(
      'id', d.id,
      'document_number', d.document_number,
      'document_type', d.document_type,
      'enquiry_id', d.enquiry_id,
      'customer_name', d.customer_name,
      'customer_email', d.customer_email,
      'amount_total', d.amount_total,
      'currency', d.currency,
      'payload', d.payload,
      'created_by', d.created_by,
      'created_by_name', sp.full_name,
      'created_at', d.created_at
    ),
    'source', jsonb_strip_nulls(jsonb_build_object(
      'enquiry_id', d.enquiry_id,
      'record_id', d.payload ->> 'record_id',
      'booking_id', coalesce(
        d.payload ->> 'booking_id',
        d.payload -> 'booking' ->> 'id'
      ),
      'payment_id', coalesce(
        d.payload ->> 'payment_id',
        d.payload -> 'payment' ->> 'id'
      ),
      'quote_id', d.payload -> 'quote' ->> 'id',
      'corporate_account_id', coalesce(
        d.payload -> 'account' ->> 'id',
        d.payload -> 'account' ->> 'account_reference',
        case
          when d.document_type = 'monthly_statement'
            then d.payload ->> 'record_id'
          else null
        end
      )
    ))
  )
  into v_result
  from public.documents d
  left join public.staff_profiles sp
    on sp.user_id = d.created_by
  where d.id = p_document_id;

  if v_result is null then
    raise exception 'Document not found';
  end if;

  return v_result;
end;
$function$;

alter table public.documents enable row level security;

drop policy if exists documents_select_own_or_staff on public.documents;
drop policy if exists documents_insert_staff on public.documents;
drop policy if exists documents_update_staff on public.documents;

create policy documents_select_own_or_permitted_staff
on public.documents
for select
to authenticated
using (
  public.has_staff_permission('generate_documents')
  or exists (
    select 1
    from public.enquiries e
    where e.id = documents.enquiry_id
      and e.user_id = (select auth.uid())
  )
);

revoke all on table public.documents from anon, authenticated;
grant select on table public.documents to authenticated;

create or replace function public.upsert_staff_template_override(
  p_template_key text,
  p_subject text,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_template_key text := trim(coalesce(p_template_key, ''));
  v_subject text := nullif(trim(coalesce(p_subject, '')), '');
  v_before public.staff_template_overrides%rowtype;
  v_after public.staff_template_overrides%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_templates') then
    raise exception 'Template management permission required';
  end if;

  if char_length(v_template_key) < 2
    or char_length(v_template_key) > 180
    or v_template_key !~ '^[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$'
  then
    raise exception 'Invalid template key';
  end if;

  if p_body is null
    or char_length(trim(p_body)) = 0
    or char_length(p_body) > 20000
  then
    raise exception 'Template body must be between 1 and 20000 characters';
  end if;

  if v_subject is not null and char_length(v_subject) > 500 then
    raise exception 'Template subject must not exceed 500 characters';
  end if;

  select sto.*
  into v_before
  from public.staff_template_overrides sto
  where sto.template_key = v_template_key
  for update;

  insert into public.staff_template_overrides (
    template_key,
    subject,
    body,
    updated_by,
    updated_at
  )
  values (
    v_template_key,
    v_subject,
    p_body,
    v_actor,
    clock_timestamp()
  )
  on conflict (template_key) do update
  set
    subject = excluded.subject,
    body = excluded.body,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into v_after;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    metadata
  )
  values (
    v_actor,
    case
      when v_before.template_key is null then 'template.override_created'
      else 'template.override_updated'
    end,
    'staff_template_override',
    jsonb_build_object(
      'template_key', v_template_key,
      'before', case
        when v_before.template_key is null then null
        else to_jsonb(v_before)
      end,
      'after', to_jsonb(v_after)
    )
  );

  return to_jsonb(v_after);
end;
$function$;

create or replace function public.delete_staff_template_override(
  p_template_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_template_key text := trim(coalesce(p_template_key, ''));
  v_before public.staff_template_overrides%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_templates') then
    raise exception 'Template management permission required';
  end if;

  if char_length(v_template_key) < 2
    or char_length(v_template_key) > 180
    or v_template_key !~ '^[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$'
  then
    raise exception 'Invalid template key';
  end if;

  select sto.*
  into v_before
  from public.staff_template_overrides sto
  where sto.template_key = v_template_key
  for update;

  if not found then
    return jsonb_build_object(
      'template_key', v_template_key,
      'deleted', false
    );
  end if;

  delete from public.staff_template_overrides sto
  where sto.template_key = v_template_key;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    metadata
  )
  values (
    v_actor,
    'template.override_deleted',
    'staff_template_override',
    jsonb_build_object(
      'template_key', v_template_key,
      'before', to_jsonb(v_before),
      'after', null
    )
  );

  return jsonb_build_object(
    'template_key', v_template_key,
    'deleted', true
  );
end;
$function$;

alter table public.staff_template_overrides enable row level security;

drop policy if exists "Staff can insert template overrides"
  on public.staff_template_overrides;
drop policy if exists "Staff can update template overrides"
  on public.staff_template_overrides;
drop policy if exists "Staff can delete template overrides"
  on public.staff_template_overrides;
drop policy if exists "Staff can read template overrides"
  on public.staff_template_overrides;

create policy staff_template_overrides_select_staff
on public.staff_template_overrides
for select
to authenticated
using (public.is_staff());

revoke all on table public.staff_template_overrides from anon, authenticated;
grant select on table public.staff_template_overrides to authenticated;

revoke all on function public.list_operations_documents(
  text,
  text,
  timestamptz,
  timestamptz,
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated;
grant execute on function public.list_operations_documents(
  text,
  text,
  timestamptz,
  timestamptz,
  integer,
  timestamptz,
  uuid
) to authenticated, service_role;

revoke all on function public.get_operations_document_detail(uuid)
  from public, anon, authenticated;
grant execute on function public.get_operations_document_detail(uuid)
  to authenticated, service_role;

revoke all on function public.upsert_staff_template_override(text, text, text)
  from public, anon, authenticated;
grant execute on function public.upsert_staff_template_override(text, text, text)
  to authenticated, service_role;

revoke all on function public.delete_staff_template_override(text)
  from public, anon, authenticated;
grant execute on function public.delete_staff_template_override(text)
  to authenticated, service_role;

comment on function public.list_operations_documents(
  text,
  text,
  timestamptz,
  timestamptz,
  integer,
  timestamptz,
  uuid
) is 'Lists issued documents for generate_documents staff with search, filters, and keyset pagination.';

comment on function public.get_operations_document_detail(uuid)
is 'Returns one issued document and its full rendering payload to generate_documents staff.';

comment on function public.upsert_staff_template_override(text, text, text)
is 'Creates or updates a shared staff communication-template override with manage_templates authorization and audit logging.';

comment on function public.delete_staff_template_override(text)
is 'Deletes a shared staff communication-template override with manage_templates authorization and audit logging.';
