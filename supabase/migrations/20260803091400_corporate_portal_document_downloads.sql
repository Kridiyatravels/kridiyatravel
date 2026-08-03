-- Corporate portal document downloads.
-- Adds portal-safe document download fields to the existing corporate booking
-- detail RPC. The RPC still returns only documents for the authenticated
-- user's linked company and only rows marked visible_to_customer.

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
        'booking_id', bd.booking_id,
        'document_type', bd.document_type,
        'file_name', bd.file_name,
        'storage_path', bd.storage_path,
        'external_reference', bd.external_reference,
        'visible_to_customer', bd.visible_to_customer,
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

revoke execute on function public.get_my_corporate_booking_detail(uuid) from public, anon;
grant execute on function public.get_my_corporate_booking_detail(uuid) to authenticated, service_role;
