-- Payment proof storage, attachment RPC, booking-detail proof fields, and default bank details.
-- Prepared for project jmvqqpughlzeqrcyavwz on 2026-07-25.

alter table public.payments
  add column if not exists proof_storage_path text,
  add column if not exists proof_file_name text,
  add column if not exists proof_uploaded_by uuid references auth.users(id) on delete set null,
  add column if not exists proof_uploaded_at timestamptz;

create index if not exists payments_proof_uploaded_at_idx
on public.payments(proof_uploaded_at desc)
where proof_storage_path is not null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'booking-payment-proofs',
  'booking-payment-proofs',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists booking_payment_proofs_insert_staff on storage.objects;
drop policy if exists booking_payment_proofs_select_staff on storage.objects;
drop policy if exists booking_payment_proofs_update_staff on storage.objects;
drop policy if exists booking_payment_proofs_delete_staff on storage.objects;
drop policy if exists payment_proofs_insert_staff on storage.objects;
drop policy if exists payment_proofs_select_staff on storage.objects;
drop policy if exists payment_proofs_update_staff on storage.objects;
drop policy if exists payment_proofs_delete_staff on storage.objects;

create policy booking_payment_proofs_insert_staff
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'booking-payment-proofs'
  and public.has_staff_permission('edit_payments')
);

create policy booking_payment_proofs_select_staff
on storage.objects for select
to authenticated
using (
  bucket_id = 'booking-payment-proofs'
  and (
    public.has_staff_permission('view_payments')
    or public.has_staff_permission('edit_payments')
    or public.has_staff_permission('view_reports')
  )
);

create policy booking_payment_proofs_update_staff
on storage.objects for update
to authenticated
using (
  bucket_id = 'booking-payment-proofs'
  and public.has_staff_permission('edit_payments')
)
with check (
  bucket_id = 'booking-payment-proofs'
  and public.has_staff_permission('edit_payments')
);

create policy booking_payment_proofs_delete_staff
on storage.objects for delete
to authenticated
using (
  bucket_id = 'booking-payment-proofs'
  and public.has_staff_permission('edit_payments')
);

create or replace function public.attach_payment_proof(
  p_payment_id uuid,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_booking_id uuid;
  v_reference text;
  v_file_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_payments') then
    raise exception 'Payment edit permission required';
  end if;
  if nullif(trim(coalesce(p_storage_path, '')), '') is null then
    raise exception 'Proof file path is required';
  end if;

  v_file_name := regexp_replace(p_storage_path, '^.*/', '');

  update public.payments
  set proof_storage_path = p_storage_path,
      proof_file_name = v_file_name,
      proof_uploaded_by = auth.uid(),
      proof_uploaded_at = now(),
      status = case when status = 'pending' then 'proof_received' else status end,
      updated_at = now()
  where id = p_payment_id
    and payment_direction = 'customer_in'
  returning booking_id, payment_reference
  into v_booking_id, v_reference;

  if not found then
    raise exception 'Customer payment not found';
  end if;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment.proof_uploaded',
    'payment',
    p_payment_id,
    jsonb_build_object(
      'booking_id', v_booking_id,
      'payment_reference', v_reference,
      'storage_path', p_storage_path,
      'file_name', v_file_name
    )
  );

  return jsonb_build_object('ok', true, 'booking_id', v_booking_id);
end;
$function$;

create or replace function public.get_operations_booking_detail(p_booking_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
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
    and (
      public.has_staff_permission('create_bookings')
      or public.has_staff_permission('edit_bookings')
      or public.has_staff_permission('view_payments')
      or public.has_staff_permission('view_reports')
    );
$function$;

update public.business_settings
set bank_name = coalesce(bank_name, 'Wio Bank'),
    bank_account_name = 'KRIDIYA Travel and Tourism FZ-LLC',
    bank_iban = 'AE540860000009813682904',
    bank_swift = 'WIOBAEADXXX',
    invoice_footer_note = coalesce(
      nullif(invoice_footer_note, ''),
      'Payment before booking. Bank address: Etihad Airways Centre 5th Floor, Abu Dhabi, UAE.'
    )
where id = true;

revoke execute on function public.attach_payment_proof(uuid, text) from public;
revoke execute on function public.attach_payment_proof(uuid, text) from anon;
grant execute on function public.attach_payment_proof(uuid, text) to authenticated, service_role;

revoke execute on function public.get_operations_booking_detail(uuid) from public;
revoke execute on function public.get_operations_booking_detail(uuid) from anon;
grant execute on function public.get_operations_booking_detail(uuid) to authenticated, service_role;
