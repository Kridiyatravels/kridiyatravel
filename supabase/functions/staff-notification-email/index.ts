import { createClient } from "jsr:@supabase/supabase-js@2";
import { supabaseRuntimeKeys } from "../_shared/runtime.ts";

const ALLOWED_ORIGINS = new Set([
  "https://kridiyatravel.com",
  "https://www.kridiyatravel.com",
  "https://admin.kridiyatravel.com",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
]);

function headers(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://www.kridiyatravel.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

function reply(origin: string | null, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) });
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character] || character));
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: headers(origin) });
  if (request.method !== "POST") return reply(origin, 405, { error: "Method not allowed" });
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(origin, 403, { error: "Origin not allowed" });

  const resendKey = Deno.env.get("RESEND_API_KEY") || "";
  const fromEmail = Deno.env.get("UNSUBSCRIBE_FROM_EMAIL") || "Kridiya Travel <deals@kridiyatravel.com>";
  const { url, secretKey } = supabaseRuntimeKeys();
  if (!resendKey || !url || !secretKey) return reply(origin, 503, { error: "Notification delivery is not configured" });

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return reply(origin, 400, { error: "Invalid request" }); }
  const enquiryId = typeof body.enquiry_id === "string" ? body.enquiry_id.trim() : "";
  if (!/^[0-9a-f-]{36}$/i.test(enquiryId)) return reply(origin, 400, { error: "Invalid enquiry" });

  const admin = createClient(url, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: enquiry, error: enquiryError } = await admin.from("enquiries")
    .select("id,reference,full_name,email,phone,service_type,summary,created_at,assigned_staff_id")
    .eq("id", enquiryId).single();
  if (enquiryError || !enquiry) return reply(origin, 404, { error: "Enquiry not found" });
  if (Date.now() - new Date(enquiry.created_at).getTime() > 15 * 60 * 1000) {
    return reply(origin, 409, { error: "Notification window expired" });
  }

  const { data: notification, error: notificationError } = await admin.from("staff_notifications")
    .select("id,title")
    .eq("dedupe_key", `new-enquiry:${enquiryId}`).single();
  if (notificationError || !notification) return reply(origin, 409, { error: "Notification is not ready" });

  const claim = await admin.from("staff_notification_email_deliveries").insert({ notification_id: notification.id }).select("id").single();
  if (claim.error) {
    if (claim.error.code === "23505") return reply(origin, 200, { ok: true, already_delivered: true });
    return reply(origin, 503, { error: "Could not reserve notification delivery" });
  }

  try {
    const [{ data: profiles }, { data: preferences }, usersResult] = await Promise.all([
      admin.from("staff_profiles").select("user_id,full_name").eq("active", true),
      admin.from("staff_notification_preferences").select("user_id,email_new_enquiry"),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    ]);
    const preferenceMap = new Map((preferences || []).map((row) => [row.user_id, row.email_new_enquiry]));
    const allowedIds = new Set((profiles || []).filter((row) => {
      return (!enquiry.assigned_staff_id || row.user_id === enquiry.assigned_staff_id) && preferenceMap.get(row.user_id) !== false;
    }).map((row) => row.user_id));
    const recipients = (usersResult.data?.users || []).filter((user) => allowedIds.has(user.id) && user.email).map((user) => user.email as string);
    if (!recipients.length) throw new Error("No staff recipients have new-enquiry email enabled");

    const adminUrl = `https://admin.kridiyatravel.com/admin.html?focus=${encodeURIComponent(enquiry.id)}`;
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: fromEmail,
        to: recipients,
        subject: `[New enquiry] ${enquiry.reference} - ${enquiry.full_name}`,
        html: `<div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#1d2430"><h2>New ${escapeHtml(enquiry.service_type)} enquiry</h2><p><b>${escapeHtml(enquiry.reference)}</b> was received from ${escapeHtml(enquiry.full_name)}.</p><p>${escapeHtml(enquiry.summary)}</p><p><b>Phone:</b> ${escapeHtml(enquiry.phone || "Not supplied")}<br><b>Email:</b> ${escapeHtml(enquiry.email || "Not supplied")}</p><p><a href="${adminUrl}" style="display:inline-block;background:#bd5108;color:white;text-decoration:none;padding:12px 18px;border-radius:8px">Open and assign enquiry</a></p><p style="color:#68707a;font-size:12px">Operational notification from Kridiya Staff Tools.</p></div>`,
      }),
    });
    const provider = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(typeof provider.message === "string" ? provider.message : `Resend returned ${response.status}`);
    await admin.from("staff_notification_email_deliveries").update({
      status: "sent", recipient_count: recipients.length,
      provider_message_ids: provider.id ? [provider.id] : [], sent_at: new Date().toISOString(), last_error: null,
    }).eq("id", claim.data.id);
    return reply(origin, 200, { ok: true, recipient_count: recipients.length });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown delivery error";
    await admin.from("staff_notification_email_deliveries").update({ status: "failed", last_error: message.slice(0, 1000) }).eq("id", claim.data.id);
    console.error("staff-notification-email:", message);
    return reply(origin, 503, { error: "Staff email could not be delivered" });
  }
});
