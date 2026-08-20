-- Pre-deploy compatibility bridge for the legacy static admin Documents page.
--
-- This migration intentionally leaves the existing public.documents table
-- privileges and RLS policies unchanged. Both the legacy direct INSERT path
-- and the new RPC path therefore remain available while the static JavaScript
-- deployment propagates. The follow-up lock-down migration removes direct
-- authenticated writes after the RPC client is live.

create or replace function public.create_operations_document(
  p_document_type text,
  p_enquiry_id uuid,
  p_customer_name text,
  p_customer_email text,
  p_amount_total numeric,
  p_currency text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_document_type text := lower(trim(coalesce(p_document_type, '')));
  v_customer_name text := trim(coalesce(p_customer_name, ''));
  v_customer_email text := nullif(lower(trim(coalesce(p_customer_email, ''))), '');
  v_currency text := upper(trim(coalesce(p_currency, 'AED')));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_doc public.documents%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('generate_documents') then
    raise exception 'Document generation permission required';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_type t
    join pg_catalog.pg_namespace n
      on n.oid = t.typnamespace
    join pg_catalog.pg_enum e
      on e.enumtypid = t.oid
    where n.nspname = 'public'
      and t.typname = 'document_type'
      and e.enumlabel = v_document_type
  ) then
    raise exception 'Invalid document type';
  end if;

  if char_length(v_customer_name) < 2
    or char_length(v_customer_name) > 160
  then
    raise exception 'Customer name must be between 2 and 160 characters';
  end if;

  if v_customer_email is not null
    and (
      char_length(v_customer_email) > 320
      or v_customer_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    )
  then
    raise exception 'Invalid customer email';
  end if;

  if p_amount_total is not null
    and (
      p_amount_total = 'NaN'::numeric
      or p_amount_total < 0
      or p_amount_total > 9999999999.99
    )
  then
    raise exception 'Document amount is invalid';
  end if;

  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency must be a three-letter code';
  end if;

  if jsonb_typeof(v_payload) <> 'object'
    or pg_catalog.octet_length(v_payload::text) > 5000000
  then
    raise exception 'Document payload must be an object no larger than 5 MB';
  end if;

  if p_enquiry_id is not null then
    perform 1
    from public.enquiries e
    where e.id = p_enquiry_id;

    if not found then
      raise exception 'Enquiry not found';
    end if;
  end if;

  insert into public.documents (
    document_type,
    enquiry_id,
    customer_name,
    customer_email,
    amount_total,
    currency,
    payload,
    created_by
  )
  values (
    v_document_type::public.document_type,
    p_enquiry_id,
    v_customer_name,
    v_customer_email,
    p_amount_total,
    v_currency,
    v_payload,
    v_actor
  )
  returning * into v_doc;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'document.manual_issued',
    'document',
    v_doc.id,
    jsonb_build_object(
      'document_number', v_doc.document_number,
      'document_type', v_doc.document_type,
      'enquiry_id', v_doc.enquiry_id,
      'customer_name', v_doc.customer_name,
      'amount_total', v_doc.amount_total,
      'currency', v_doc.currency
    )
  );

  return jsonb_build_object(
    'id', v_doc.id,
    'document_number', v_doc.document_number,
    'document_type', v_doc.document_type,
    'enquiry_id', v_doc.enquiry_id,
    'customer_name', v_doc.customer_name,
    'customer_email', v_doc.customer_email,
    'amount_total', v_doc.amount_total,
    'currency', v_doc.currency,
    'payload', v_doc.payload,
    'created_by', v_doc.created_by,
    'created_at', v_doc.created_at
  );
end;
$function$;

revoke all on function public.create_operations_document(
  text,
  uuid,
  text,
  text,
  numeric,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function public.create_operations_document(
  text,
  uuid,
  text,
  text,
  numeric,
  text,
  jsonb
) to authenticated, service_role;

comment on function public.create_operations_document(
  text,
  uuid,
  text,
  text,
  numeric,
  text,
  jsonb
) is 'Issues a validated manual document for generate_documents staff, stamps the actor, and writes an audit event.';
