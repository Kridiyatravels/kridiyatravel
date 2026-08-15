create or replace function public.get_canonical_audit_timeline(
  p_entity_type text,
  p_entity_id uuid,
  p_limit integer default 100,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  context_type text := lower(trim(coalesce(p_entity_type, '')));
  result_limit integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  booking_ids uuid[] := '{}'::uuid[];
  enquiry_ids uuid[] := '{}'::uuid[];
  quote_ids uuid[] := '{}'::uuid[];
  payment_ids uuid[] := '{}'::uuid[];
  document_ids uuid[] := '{}'::uuid[];
  supplier_payment_ids uuid[] := '{}'::uuid[];
  customer_ids uuid[] := '{}'::uuid[];
  company_ids uuid[] := '{}'::uuid[];
  traveller_ids uuid[] := '{}'::uuid[];
  timeline jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_staff_permission('view_activity')
    or public.has_staff_permission('view_reports')
    or public.has_staff_permission('edit_bookings')
    or public.has_staff_permission('edit_customers')
    or public.has_staff_permission('edit_corporates')
    or public.has_staff_permission('view_payments')
  ) then raise exception 'Permission denied'; end if;
  if p_entity_id is null then raise exception 'Entity ID is required'; end if;
  if context_type not in (
    'booking', 'enquiry', 'quote', 'payment', 'document',
    'customer', 'corporate_account', 'company', 'traveller'
  ) then raise exception 'Unsupported timeline entity type'; end if;
  if context_type = 'company' then context_type := 'corporate_account'; end if;

  case context_type
    when 'booking' then
      select array[b.id],
             array_remove(array[b.enquiry_id], null),
             array_remove(array[b.customer_id], null),
             array_remove(array[b.corporate_account_id], null)
      into booking_ids, enquiry_ids, customer_ids, company_ids
      from public.bookings b where b.id = p_entity_id;
      if coalesce(cardinality(booking_ids), 0) = 0 then raise exception 'Booking not found'; end if;
    when 'enquiry' then
      if not exists (select 1 from public.enquiries where id = p_entity_id) then
        raise exception 'Enquiry not found';
      end if;
      enquiry_ids := array[p_entity_id];
    when 'quote' then
      select array[q.id], array_remove(array[q.booking_id], null),
             array_remove(array[q.enquiry_id], null)
      into quote_ids, booking_ids, enquiry_ids
      from public.quotes q where q.id = p_entity_id;
      if coalesce(cardinality(quote_ids), 0) = 0 then raise exception 'Quote not found'; end if;
    when 'payment' then
      select array[p.id], array_remove(array[p.booking_id], null),
             array_remove(array[p.enquiry_id], null),
             array_remove(array[p.customer_id], null),
             array_remove(array[p.corporate_account_id], null),
             array_remove(array[p.receipt_document_id], null)
      into payment_ids, booking_ids, enquiry_ids, customer_ids, company_ids, document_ids
      from public.payments p where p.id = p_entity_id;
      if coalesce(cardinality(payment_ids), 0) = 0 then raise exception 'Payment not found'; end if;
    when 'document' then
      select array[d.id], array_remove(array[d.enquiry_id], null)
      into document_ids, enquiry_ids
      from public.documents d where d.id = p_entity_id;
      if coalesce(cardinality(document_ids), 0) = 0 then raise exception 'Document not found'; end if;
    when 'customer' then
      if not exists (select 1 from public.customers where id = p_entity_id) then
        raise exception 'Customer not found';
      end if;
      customer_ids := array[p_entity_id];
    when 'corporate_account' then
      if not exists (select 1 from public.corporate_accounts where id = p_entity_id) then
        raise exception 'Company not found';
      end if;
      company_ids := array[p_entity_id];
    when 'traveller' then
      select array[t.id], array_remove(array[t.customer_id], null),
             array_remove(array[t.corporate_account_id], null)
      into traveller_ids, customer_ids, company_ids
      from public.travellers t where t.id = p_entity_id;
      if coalesce(cardinality(traveller_ids), 0) = 0 then raise exception 'Traveller not found'; end if;
  end case;

  if context_type = 'customer' and cardinality(customer_ids) > 0 then
    booking_ids := booking_ids || coalesce((
      select array_agg(b.id) from public.bookings b
      where b.customer_id = any(customer_ids)
    ), '{}'::uuid[]);
    payment_ids := payment_ids || coalesce((
      select array_agg(p.id) from public.payments p
      where p.customer_id = any(customer_ids)
    ), '{}'::uuid[]);
    traveller_ids := traveller_ids || coalesce((
      select array_agg(t.id) from public.travellers t
      where t.customer_id = any(customer_ids)
    ), '{}'::uuid[]);
  end if;

  if context_type = 'corporate_account' and cardinality(company_ids) > 0 then
    booking_ids := booking_ids || coalesce((
      select array_agg(b.id) from public.bookings b
      where b.corporate_account_id = any(company_ids)
    ), '{}'::uuid[]);
    payment_ids := payment_ids || coalesce((
      select array_agg(p.id) from public.payments p
      where p.corporate_account_id = any(company_ids)
    ), '{}'::uuid[]);
    traveller_ids := traveller_ids || coalesce((
      select array_agg(t.id) from public.travellers t
      where t.corporate_account_id = any(company_ids)
    ), '{}'::uuid[]);
  end if;

  if cardinality(booking_ids) > 0 then
    enquiry_ids := enquiry_ids || coalesce((
      select array_agg(distinct b.enquiry_id) from public.bookings b
      where b.id = any(booking_ids) and b.enquiry_id is not null
    ), '{}'::uuid[]);
    customer_ids := customer_ids || coalesce((
      select array_agg(distinct b.customer_id) from public.bookings b
      where b.id = any(booking_ids) and b.customer_id is not null
    ), '{}'::uuid[]);
    company_ids := company_ids || coalesce((
      select array_agg(distinct b.corporate_account_id) from public.bookings b
      where b.id = any(booking_ids) and b.corporate_account_id is not null
    ), '{}'::uuid[]);
    quote_ids := quote_ids || coalesce((
      select array_agg(q.id) from public.quotes q where q.booking_id = any(booking_ids)
    ), '{}'::uuid[]);
    payment_ids := payment_ids || coalesce((
      select array_agg(p.id) from public.payments p where p.booking_id = any(booking_ids)
    ), '{}'::uuid[]);
    supplier_payment_ids := supplier_payment_ids || coalesce((
      select array_agg(sp.id) from public.supplier_payments sp
      where sp.booking_id = any(booking_ids)
    ), '{}'::uuid[]);
  end if;

  if cardinality(enquiry_ids) > 0 then
    booking_ids := booking_ids || coalesce((
      select array_agg(b.id) from public.bookings b where b.enquiry_id = any(enquiry_ids)
    ), '{}'::uuid[]);
    quote_ids := quote_ids || coalesce((
      select array_agg(q.id) from public.quotes q where q.enquiry_id = any(enquiry_ids)
    ), '{}'::uuid[]);
    payment_ids := payment_ids || coalesce((
      select array_agg(p.id) from public.payments p where p.enquiry_id = any(enquiry_ids)
    ), '{}'::uuid[]);
    document_ids := document_ids || coalesce((
      select array_agg(d.id) from public.documents d where d.enquiry_id = any(enquiry_ids)
    ), '{}'::uuid[]);
  end if;

  if cardinality(document_ids) > 0 then
    payment_ids := payment_ids || coalesce((
      select array_agg(p.id) from public.payments p
      where p.receipt_document_id = any(document_ids)
    ), '{}'::uuid[]);
  end if;

  booking_ids := array(select distinct unnest(booking_ids));
  enquiry_ids := array(select distinct unnest(enquiry_ids));
  quote_ids := array(select distinct unnest(quote_ids));
  payment_ids := array(select distinct unnest(payment_ids));
  document_ids := array(select distinct unnest(document_ids));
  supplier_payment_ids := array(select distinct unnest(supplier_payment_ids));
  customer_ids := array(select distinct unnest(customer_ids));
  company_ids := array(select distinct unnest(company_ids));
  traveller_ids := array(select distinct unnest(traveller_ids));

  select coalesce(jsonb_agg(to_jsonb(event_row) order by event_row.created_at desc), '[]'::jsonb)
  into timeline
  from (
    select ae.id, ae.event_type, ae.entity_type, ae.entity_id,
           ae.actor_user_id, actor.full_name as actor_name,
           ae.target_user_id, ae.metadata, ae.created_at,
           case when ae.entity_type = context_type and ae.entity_id = p_entity_id
             then 'direct' else 'related' end as correlation
    from public.audit_events ae
    left join public.staff_profiles actor on actor.user_id = ae.actor_user_id
    where (p_before is null or ae.created_at < p_before)
      and (
        (ae.entity_type = 'booking' and ae.entity_id = any(booking_ids))
        or (ae.entity_type = 'enquiry' and ae.entity_id = any(enquiry_ids))
        or (ae.entity_type = 'quote' and ae.entity_id = any(quote_ids))
        or (ae.entity_type = 'payment' and ae.entity_id = any(payment_ids))
        or (ae.entity_type = 'document' and ae.entity_id = any(document_ids))
        or (ae.entity_type = 'supplier_payment' and ae.entity_id = any(supplier_payment_ids))
        or (context_type = 'customer'
            and ae.entity_type = 'customer' and ae.entity_id = any(customer_ids))
        or (context_type = 'corporate_account'
            and ae.entity_type = 'corporate_account' and ae.entity_id = any(company_ids))
        or (ae.entity_type = 'traveller' and ae.entity_id = any(traveller_ids))
        or (ae.metadata->>'booking_id') = any(booking_ids::text[])
        or (ae.metadata->>'enquiry_id') = any(enquiry_ids::text[])
        or (context_type = 'corporate_account'
            and (ae.metadata->>'corporate_account_id') = any(company_ids::text[]))
      )
    order by ae.created_at desc, ae.id desc
    limit result_limit
  ) event_row;

  return jsonb_build_object(
    'entity_type', context_type,
    'entity_id', p_entity_id,
    'events', timeline,
    'event_count', jsonb_array_length(timeline),
    'has_more', jsonb_array_length(timeline) = result_limit,
    'next_before', case when jsonb_array_length(timeline) = 0 then null else
      timeline->(jsonb_array_length(timeline) - 1)->>'created_at' end
  );
end;
$function$;

revoke execute on function public.get_canonical_audit_timeline(
  text,uuid,integer,timestamptz
) from public, anon;
grant execute on function public.get_canonical_audit_timeline(
  text,uuid,integer,timestamptz
) to authenticated, service_role;

