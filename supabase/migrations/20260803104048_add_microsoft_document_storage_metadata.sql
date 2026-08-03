-- Keep permanent business files in Microsoft 365 while Supabase stores only
-- authorization and lookup metadata. Existing Supabase paths remain available
-- during the verified migration period.

alter table public.booking_documents
  add column if not exists storage_provider text not null default 'supabase'
    check (storage_provider in ('supabase', 'microsoft')),
  add column if not exists microsoft_drive_id text,
  add column if not exists microsoft_item_id text,
  add column if not exists microsoft_path text,
  add column if not exists microsoft_web_url text,
  add column if not exists mime_type text,
  add column if not exists file_size_bytes bigint
    check (file_size_bytes is null or file_size_bytes >= 0);

create unique index if not exists booking_documents_microsoft_item_id_idx
on public.booking_documents(microsoft_item_id)
where microsoft_item_id is not null;

alter table public.supplier_payments
  add column if not exists invoice_storage_provider text not null default 'supabase'
    check (invoice_storage_provider in ('supabase', 'microsoft')),
  add column if not exists microsoft_invoice_drive_id text,
  add column if not exists microsoft_invoice_item_id text,
  add column if not exists microsoft_invoice_path text,
  add column if not exists microsoft_invoice_mime_type text,
  add column if not exists microsoft_invoice_size_bytes bigint
    check (microsoft_invoice_size_bytes is null or microsoft_invoice_size_bytes >= 0);

create unique index if not exists supplier_payments_microsoft_invoice_item_id_idx
on public.supplier_payments(microsoft_invoice_item_id)
where microsoft_invoice_item_id is not null;

alter table public.payments
  add column if not exists proof_storage_provider text not null default 'supabase'
    check (proof_storage_provider in ('supabase', 'microsoft')),
  add column if not exists microsoft_proof_drive_id text,
  add column if not exists microsoft_proof_item_id text,
  add column if not exists microsoft_proof_path text,
  add column if not exists microsoft_proof_web_url text,
  add column if not exists microsoft_proof_mime_type text,
  add column if not exists microsoft_proof_size_bytes bigint
    check (microsoft_proof_size_bytes is null or microsoft_proof_size_bytes >= 0);

create unique index if not exists payments_microsoft_proof_item_id_idx
on public.payments(microsoft_proof_item_id)
where microsoft_proof_item_id is not null;

comment on column public.booking_documents.microsoft_item_id is
  'Microsoft Graph driveItem ID for the permanent document copy.';
comment on column public.supplier_payments.microsoft_invoice_item_id is
  'Microsoft Graph driveItem ID for the permanent supplier invoice.';
comment on column public.payments.microsoft_proof_item_id is
  'Microsoft Graph driveItem ID for the permanent payment proof.';
