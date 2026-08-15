import { createClient } from "jsr:@supabase/supabase-js@2";
import { supabaseRuntimeKeys } from "../_shared/runtime.ts";

const ALLOWED_ORIGINS = [
  "https://admin.kridiyatravel.com",
  "https://www.kridiyatravel.com",
  "https://kridiyatravel.com",
  "https://corporate.kridiyatravel.com",
  "http://localhost:8137",
  "http://localhost:8138",
];
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const BOOKING_SUBFOLDERS = [
  "01 Customer Documents",
  "02 Tickets and Vouchers",
  "03 Invoices and Receipts",
  "04 Payment Proofs",
  "05 Supplier Invoices",
  "06 Refunds and Cancellations",
  "07 Internal Notes",
];

type SupabaseClient = ReturnType<typeof createClient>;
type GraphItem = { id: string; name: string; webUrl?: string; size?: number; file?: { mimeType?: string } };

function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

function requiredEnv(name: string) {
  const value = (Deno.env.get(name) || "").trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function safeSegment(value: unknown, fallback: string) {
  const clean = String(value || "")
    .normalize("NFKC")
    .replace(/[~#%&*{}\\:<>?/+|"\u0000-\u001f]/g, "-")
    .replace(/\s+/g, " ")
    .replace(/[. ]+$/g, "")
    .trim()
    .slice(0, 100);
  return clean || fallback;
}

function encodedPath(path: string) {
  return path.split("/").map((part) => encodeURIComponent(part)).join("/");
}

function categoryFor(documentType: string) {
  const value = documentType.toLowerCase();
  if (/ticket|voucher|visa|itinerary|confirmation/.test(value)) return BOOKING_SUBFOLDERS[1];
  if (/invoice|receipt|quotation|quote|payment.request|statement/.test(value)) return BOOKING_SUBFOLDERS[2];
  if (/payment.proof/.test(value)) return BOOKING_SUBFOLDERS[3];
  if (/supplier/.test(value)) return BOOKING_SUBFOLDERS[4];
  if (/refund|cancel/.test(value)) return BOOKING_SUBFOLDERS[5];
  if (/internal|note/.test(value)) return BOOKING_SUBFOLDERS[6];
  return BOOKING_SUBFOLDERS[0];
}

async function graphToken() {
  const tenantId = requiredEnv("MICROSOFT_TENANT_ID");
  const response = await fetch(`https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: requiredEnv("MICROSOFT_CLIENT_ID"),
      client_secret: requiredEnv("MICROSOFT_CLIENT_SECRET"),
      scope: "https://graph.microsoft.com/.default",
      grant_type: "client_credentials",
    }),
  });
  if (!response.ok) {
    console.error("microsoft-documents: token request failed", response.status, await response.text());
    throw new Error("Microsoft storage authentication failed");
  }
  const result = await response.json();
  return String(result.access_token || "");
}

async function graph(token: string, path: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  return fetch(`https://graph.microsoft.com/v1.0${path}`, { ...init, headers });
}

async function getItemByPath(token: string, path: string): Promise<GraphItem | null> {
  const driveId = requiredEnv("MICROSOFT_DRIVE_ID");
  const response = await graph(token, `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(path)}`);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Microsoft path lookup failed (${response.status})`);
  return response.json();
}

async function ensureFolder(token: string, path: string): Promise<GraphItem> {
  const driveId = requiredEnv("MICROSOFT_DRIVE_ID");
  const parts = path.split("/").filter(Boolean);
  let currentPath = "";
  let current: GraphItem | null = null;
  for (const part of parts) {
    const nextPath = currentPath ? `${currentPath}/${part}` : part;
    current = await getItemByPath(token, nextPath);
    if (!current) {
      const parentEndpoint = currentPath
        ? `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(currentPath)}:/children`
        : `/drives/${encodeURIComponent(driveId)}/root/children`;
      const response = await graph(token, parentEndpoint, {
        method: "POST",
        body: JSON.stringify({ name: part, folder: {}, "@microsoft.graph.conflictBehavior": "fail" }),
      });
      if (response.status === 409) current = await getItemByPath(token, nextPath);
      else if (response.ok) current = await response.json();
      else throw new Error(`Microsoft folder creation failed (${response.status})`);
    }
    if (!current) throw new Error("Microsoft folder could not be resolved");
    currentPath = nextPath;
  }
  if (!current) throw new Error("Microsoft folder path is empty");
  return current;
}

async function bookingFolder(token: string, booking: Record<string, unknown>, category: string) {
  const created = new Date(String(booking.created_at || new Date().toISOString()));
  const year = String(created.getUTCFullYear());
  const month = String(created.getUTCMonth() + 1).padStart(2, "0");
  const reference = safeSegment(booking.booking_reference, "Booking");
  const root = requiredEnv("MICROSOFT_ROOT_FOLDER");
  const base = `${root}/Bookings/${year}/${month}/${reference}`;
  await ensureFolder(token, base);
  for (const folder of BOOKING_SUBFOLDERS) await ensureFolder(token, `${base}/${folder}`);
  return `${base}/${category}`;
}

async function uploadFile(token: string, folder: string, file: File) {
  if (!file.size || file.size > MAX_FILE_BYTES) throw new Error("File must be between 1 byte and 10 MB");
  const driveId = requiredEnv("MICROSOFT_DRIVE_ID");
  const fileName = safeSegment(file.name, "document.bin");
  const path = `${folder}/${fileName}`;
  const response = await graph(token, `/drives/${encodeURIComponent(driveId)}/root:/${encodedPath(path)}:/content`, {
    method: "PUT",
    headers: { "Content-Type": file.type || "application/octet-stream" },
    body: file,
  });
  if (!response.ok) {
    console.error("microsoft-documents: upload failed", response.status, await response.text());
    throw new Error(`Microsoft upload failed (${response.status})`);
  }
  return { item: await response.json() as GraphItem, path, fileName };
}

async function deleteGraphItem(token: string, driveId: string, itemId: string) {
  const response = await graph(token, `/drives/${encodeURIComponent(driveId)}/items/${encodeURIComponent(itemId)}`, { method: "DELETE" });
  if (!response.ok && response.status !== 404) throw new Error(`Microsoft delete failed (${response.status})`);
}

async function hasAnyPermission(client: SupabaseClient, names: string[]) {
  for (const name of names) {
    const { data, error } = await client.rpc("has_staff_permission", { permission_name: name });
    if (!error && data === true) return true;
  }
  return false;
}

async function authenticatedClients(req: Request) {
  const { url, publishableKey, secretKey } = supabaseRuntimeKeys();
  if (!url || !publishableKey || !secretKey) throw new Error("Supabase runtime keys unavailable");
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Authentication required");
  const caller = createClient(url, publishableKey, { global: { headers: { Authorization: authHeader } } });
  const { data, error } = await caller.auth.getUser(token);
  if (error || !data.user) throw new Error("Authentication required");
  return { caller, admin: createClient(url, secretKey), user: data.user };
}

function operationEntity(action: string, input: FormData | Record<string, unknown>) {
  const read = (key: string) => String(input instanceof FormData ? input.get(key) || "" : input[key] || "");
  if (action === "upload_booking_document" || action === "download_booking_document" || action === "delete_booking_document") {
    return { entity_type: action === "upload_booking_document" ? "booking" : "document", entity_id: read(action === "upload_booking_document" ? "booking_id" : "document_id") || null };
  }
  if (action === "upload_supplier_invoice") return { entity_type: "supplier_payment", entity_id: read("supplier_payment_id") || null };
  if (action === "upload_payment_proof") return { entity_type: "payment", entity_id: read("payment_id") || null };
  if (action === "download_staff_file") return { entity_type: read("kind") || "staff_file", entity_id: read("record_id") || null };
  return { entity_type: null, entity_id: null };
}

async function startOperation(admin: SupabaseClient, action: string, userId: string, input: FormData | Record<string, unknown>) {
  const entity = operationEntity(action, input);
  const { data, error } = await admin.from("integration_operations").insert({
    integration: "microsoft_documents", operation: action || "unknown",
    entity_type: entity.entity_type, entity_id: entity.entity_id,
    actor_user_id: userId, status: "processing",
  }).select("id").single();
  if (error) console.error("microsoft-documents: operation ledger start failed", error.code);
  return String(data?.id || "");
}

async function finishOperation(admin: SupabaseClient, operationId: string, status: "succeeded" | "failed", httpStatus: number, error?: string) {
  if (!operationId) return;
  const update = await admin.from("integration_operations").update({
    status, http_status: httpStatus, completed_at: new Date().toISOString(),
    last_error: error ? error.replace(/[\r\n]+/g, " ").slice(0, 800) : null,
  }).eq("id", operationId);
  if (update.error) console.error("microsoft-documents: operation ledger finish failed", update.error.code);
}

async function uploadBookingDocument(form: FormData, caller: SupabaseClient, admin: SupabaseClient, userId: string) {
  if (!(await hasAnyPermission(caller, ["generate_documents", "edit_bookings"]))) throw new Error("Document permission required");
  const bookingId = String(form.get("booking_id") || "");
  const documentType = safeSegment(form.get("document_type"), "document");
  const file = form.get("file");
  if (!(file instanceof File) || !bookingId) throw new Error("Booking and file are required");
  const { data: booking, error: bookingError } = await admin.from("bookings")
    .select("id, user_id, booking_reference, created_at").eq("id", bookingId).maybeSingle();
  if (bookingError) {
    console.error("Microsoft document booking lookup failed", { bookingId, code: bookingError.code, message: bookingError.message });
    throw new Error(`Booking lookup failed (${bookingError.code || "database"})`);
  }
  if (!booking) {
    console.error("Microsoft document booking was not found", { bookingId });
    throw new Error("Booking not found");
  }
  const token = await graphToken();
  const folder = await bookingFolder(token, booking, categoryFor(documentType));
  const uploaded = await uploadFile(token, folder, file);
  const visible = String(form.get("visible_to_customer") || "false") === "true";
  const externalReference = String(form.get("external_reference") || "").trim() || null;
  const recorded = await caller.rpc("record_booking_document", {
    p_booking_id: bookingId,
    p_document_type: documentType,
    p_file_name: uploaded.fileName,
    p_external_reference: externalReference,
    p_storage_path: uploaded.path,
    p_visible_to_customer: visible,
  });
  if (recorded.error || !recorded.data) {
    await deleteGraphItem(token, requiredEnv("MICROSOFT_DRIVE_ID"), uploaded.item.id).catch(() => undefined);
    throw new Error(recorded.error?.message || "Document record could not be created");
  }
  const { error: metadataError } = await admin.from("booking_documents").update({
    storage_provider: "microsoft",
    microsoft_drive_id: requiredEnv("MICROSOFT_DRIVE_ID"),
    microsoft_item_id: uploaded.item.id,
    microsoft_path: uploaded.path,
    microsoft_web_url: uploaded.item.webUrl || null,
    mime_type: file.type || uploaded.item.file?.mimeType || null,
    file_size_bytes: file.size,
  }).eq("id", recorded.data);
  if (metadataError) throw new Error("Document uploaded but metadata update failed");
  return { id: recorded.data, file_name: uploaded.fileName, path: uploaded.path, provider: "microsoft", uploaded_by: userId };
}

async function uploadSupplierInvoice(form: FormData, caller: SupabaseClient, admin: SupabaseClient) {
  if (!(await hasAnyPermission(caller, ["edit_payments"]))) throw new Error("Payment edit permission required");
  const supplierPaymentId = String(form.get("supplier_payment_id") || "");
  const file = form.get("file");
  if (!(file instanceof File) || !supplierPaymentId) throw new Error("Supplier payment and file are required");
  const { data: supplier, error } = await admin.from("supplier_payments")
    .select("id, booking_id, bookings(id, booking_reference, created_at)").eq("id", supplierPaymentId).maybeSingle();
  if (error || !supplier?.bookings) throw new Error("Supplier payment not found");
  const token = await graphToken();
  const folder = await bookingFolder(token, supplier.bookings as Record<string, unknown>, BOOKING_SUBFOLDERS[4]);
  const uploaded = await uploadFile(token, folder, file);
  const attached = await caller.rpc("attach_supplier_invoice", {
    p_supplier_payment_id: supplierPaymentId,
    p_storage_path: uploaded.path,
    p_sharepoint_invoice_url: uploaded.item.webUrl || null,
  });
  if (attached.error) {
    await deleteGraphItem(token, requiredEnv("MICROSOFT_DRIVE_ID"), uploaded.item.id).catch(() => undefined);
    throw new Error(attached.error.message);
  }
  const { error: metadataError } = await admin.from("supplier_payments").update({
    invoice_storage_provider: "microsoft",
    microsoft_invoice_drive_id: requiredEnv("MICROSOFT_DRIVE_ID"),
    microsoft_invoice_item_id: uploaded.item.id,
    microsoft_invoice_path: uploaded.path,
    microsoft_invoice_mime_type: file.type || uploaded.item.file?.mimeType || null,
    microsoft_invoice_size_bytes: file.size,
  }).eq("id", supplierPaymentId);
  if (metadataError) throw new Error("Invoice uploaded but metadata update failed");
  return { supplier_payment_id: supplierPaymentId, file_name: uploaded.fileName, path: uploaded.path, provider: "microsoft" };
}

async function uploadPaymentProof(form: FormData, caller: SupabaseClient, admin: SupabaseClient) {
  if (!(await hasAnyPermission(caller, ["edit_payments"]))) throw new Error("Payment edit permission required");
  const paymentId = String(form.get("payment_id") || "");
  const file = form.get("file");
  if (!(file instanceof File) || !paymentId) throw new Error("Payment and file are required");
  const { data: payment, error } = await admin.from("payments")
    .select("id, booking_id, bookings(id, booking_reference, created_at)").eq("id", paymentId).maybeSingle();
  if (error || !payment?.bookings) throw new Error("Payment not found");
  const token = await graphToken();
  const folder = await bookingFolder(token, payment.bookings as Record<string, unknown>, BOOKING_SUBFOLDERS[3]);
  const uploaded = await uploadFile(token, folder, file);
  const attached = await caller.rpc("attach_payment_proof", { p_payment_id: paymentId, p_storage_path: uploaded.path });
  if (attached.error) {
    await deleteGraphItem(token, requiredEnv("MICROSOFT_DRIVE_ID"), uploaded.item.id).catch(() => undefined);
    throw new Error(attached.error.message);
  }
  const { error: metadataError } = await admin.from("payments").update({
    proof_storage_provider: "microsoft",
    microsoft_proof_drive_id: requiredEnv("MICROSOFT_DRIVE_ID"),
    microsoft_proof_item_id: uploaded.item.id,
    microsoft_proof_path: uploaded.path,
    microsoft_proof_web_url: uploaded.item.webUrl || null,
    microsoft_proof_mime_type: file.type || uploaded.item.file?.mimeType || null,
    microsoft_proof_size_bytes: file.size,
  }).eq("id", paymentId);
  if (metadataError) throw new Error("Payment proof uploaded but metadata update failed");
  return { payment_id: paymentId, file_name: uploaded.fileName, path: uploaded.path, provider: "microsoft" };
}

async function mayDownload(admin: SupabaseClient, caller: SupabaseClient, userId: string, document: Record<string, unknown>) {
  if (await hasAnyPermission(caller, ["generate_documents", "edit_bookings", "view_documents"])) return true;
  if (document.visible_to_customer !== true) return false;
  const { data: booking } = await admin.from("bookings")
    .select("user_id, corporate_account_id").eq("id", document.booking_id).maybeSingle();
  if (!booking) return false;
  if (booking.user_id === userId) return true;
  if (!booking.corporate_account_id) return false;
  const { data: member } = await admin.from("corporate_portal_members")
    .select("id").eq("corporate_account_id", booking.corporate_account_id).eq("auth_user_id", userId)
    .eq("status", "active").eq("can_view_documents", true).maybeSingle();
  return Boolean(member);
}

async function downloadDocument(body: Record<string, unknown>, caller: SupabaseClient, admin: SupabaseClient, userId: string, origin: string | null) {
  const documentId = String(body.document_id || "");
  const { data: document, error } = await admin.from("booking_documents").select("*").eq("id", documentId).maybeSingle();
  if (error || !document) return json({ error: "Document not found" }, 404, origin);
  if (!(await mayDownload(admin, caller, userId, document))) return json({ error: "Document access denied" }, 403, origin);
  if (document.storage_provider !== "microsoft" || !document.microsoft_drive_id || !document.microsoft_item_id) {
    return json({ error: "Document has not been migrated to Microsoft storage" }, 409, origin);
  }
  const token = await graphToken();
  const response = await graph(token, `/drives/${encodeURIComponent(document.microsoft_drive_id)}/items/${encodeURIComponent(document.microsoft_item_id)}/content`);
  if (!response.ok || !response.body) return json({ error: "Document download failed" }, response.status === 404 ? 404 : 502, origin);
  const headers = new Headers(corsHeaders(origin));
  headers.set("Content-Type", response.headers.get("Content-Type") || document.mime_type || "application/octet-stream");
  headers.set("Content-Disposition", `attachment; filename*=UTF-8''${encodeURIComponent(document.file_name || "document")}`);
  headers.set("Cache-Control", "private, no-store");
  return new Response(response.body, { status: 200, headers });
}

async function downloadStaffFile(body: Record<string, unknown>, caller: SupabaseClient, admin: SupabaseClient, origin: string | null) {
  if (!(await hasAnyPermission(caller, ["view_payments", "view_supplier_cost", "edit_payments", "view_reports"]))) {
    return json({ error: "Finance document access denied" }, 403, origin);
  }
  const kind = String(body.kind || "");
  const recordId = String(body.record_id || "");
  let driveId = "";
  let itemId = "";
  let fileName = "document";
  let mimeType = "application/octet-stream";
  if (kind === "payment_proof") {
    const { data } = await admin.from("payments").select("proof_file_name, microsoft_proof_drive_id, microsoft_proof_item_id, microsoft_proof_mime_type").eq("id", recordId).maybeSingle();
    driveId = data?.microsoft_proof_drive_id || "";
    itemId = data?.microsoft_proof_item_id || "";
    fileName = data?.proof_file_name || fileName;
    mimeType = data?.microsoft_proof_mime_type || mimeType;
  } else if (kind === "supplier_invoice") {
    const { data } = await admin.from("supplier_payments").select("supplier_invoice_file_name, microsoft_invoice_drive_id, microsoft_invoice_item_id, microsoft_invoice_mime_type").eq("id", recordId).maybeSingle();
    driveId = data?.microsoft_invoice_drive_id || "";
    itemId = data?.microsoft_invoice_item_id || "";
    fileName = data?.supplier_invoice_file_name || fileName;
    mimeType = data?.microsoft_invoice_mime_type || mimeType;
  }
  if (!driveId || !itemId) return json({ error: "File has not been migrated to Microsoft storage" }, 409, origin);
  const token = await graphToken();
  const response = await graph(token, `/drives/${encodeURIComponent(driveId)}/items/${encodeURIComponent(itemId)}/content`);
  if (!response.ok || !response.body) return json({ error: "File download failed" }, response.status === 404 ? 404 : 502, origin);
  const headers = new Headers(corsHeaders(origin));
  headers.set("Content-Type", response.headers.get("Content-Type") || mimeType);
  headers.set("Content-Disposition", `attachment; filename*=UTF-8''${encodeURIComponent(fileName)}`);
  headers.set("Cache-Control", "private, no-store");
  return new Response(response.body, { status: 200, headers });
}

async function deleteDocument(body: Record<string, unknown>, caller: SupabaseClient, admin: SupabaseClient) {
  if (!(await hasAnyPermission(caller, ["generate_documents", "edit_bookings"]))) throw new Error("Document permission required");
  const documentId = String(body.document_id || "");
  const { data: document } = await admin.from("booking_documents")
    .select("microsoft_drive_id, microsoft_item_id").eq("id", documentId).maybeSingle();
  if (!document) throw new Error("Document not found");
  if (document.microsoft_drive_id && document.microsoft_item_id) {
    await deleteGraphItem(await graphToken(), document.microsoft_drive_id, document.microsoft_item_id);
  }
  const result = await caller.rpc("delete_booking_document", { p_document_id: documentId });
  if (result.error) throw new Error(result.error.message);
  return { deleted: result.data === true };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  let operationAdmin: SupabaseClient | null = null;
  let operationId = "";
  try {
    const { caller, admin, user } = await authenticatedClients(req);
    operationAdmin = admin;
    const contentType = req.headers.get("Content-Type") || "";
    if (contentType.includes("multipart/form-data")) {
      const form = await req.formData();
      const action = String(form.get("action") || "");
      operationId = await startOperation(admin, action, user.id, form);
      let response: Response;
      if (action === "upload_booking_document") response = json(await uploadBookingDocument(form, caller, admin, user.id), 200, origin);
      else if (action === "upload_supplier_invoice") response = json(await uploadSupplierInvoice(form, caller, admin), 200, origin);
      else if (action === "upload_payment_proof") response = json(await uploadPaymentProof(form, caller, admin), 200, origin);
      else response = json({ error: "Unknown upload action" }, 400, origin);
      await finishOperation(admin, operationId, response.ok ? "succeeded" : "failed", response.status, response.ok ? undefined : "Request rejected");
      return response;
    }
    const body = await req.json() as Record<string, unknown>;
    const action = String(body.action || "");
    operationId = await startOperation(admin, action, user.id, body);
    let response: Response;
    if (action === "download_booking_document") response = await downloadDocument(body, caller, admin, user.id, origin);
    else if (action === "download_staff_file") response = await downloadStaffFile(body, caller, admin, origin);
    else if (action === "delete_booking_document") response = json(await deleteDocument(body, caller, admin), 200, origin);
    else response = json({ error: "Unknown action" }, 400, origin);
    await finishOperation(admin, operationId, response.ok ? "succeeded" : "failed", response.status, response.ok ? undefined : "Request rejected");
    return response;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Microsoft document operation failed";
    const status = /Authentication required/.test(message) ? 401 : /permission|required|denied/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400;
    if (operationAdmin) await finishOperation(operationAdmin, operationId, "failed", status, message);
    console.error("microsoft-documents:", message);
    return json({ error: message }, status, origin);
  }
});
