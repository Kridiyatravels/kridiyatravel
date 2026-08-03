grant select on table
  public.bookings,
  public.booking_documents,
  public.payments,
  public.supplier_payments,
  public.corporate_portal_members
to service_role;

grant update (
  storage_provider,
  microsoft_drive_id,
  microsoft_item_id,
  microsoft_path,
  microsoft_web_url,
  mime_type,
  file_size_bytes
) on table public.booking_documents to service_role;

grant update (
  proof_storage_provider,
  microsoft_proof_drive_id,
  microsoft_proof_item_id,
  microsoft_proof_path,
  microsoft_proof_web_url,
  microsoft_proof_mime_type,
  microsoft_proof_size_bytes
) on table public.payments to service_role;

grant update (
  invoice_storage_provider,
  microsoft_invoice_drive_id,
  microsoft_invoice_item_id,
  microsoft_invoice_path,
  microsoft_invoice_mime_type,
  microsoft_invoice_size_bytes
) on table public.supplier_payments to service_role;
