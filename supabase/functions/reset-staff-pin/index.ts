import { createClient } from "jsr:@supabase/supabase-js@2";
import { generateSixDigitPin, supabaseRuntimeKeys } from "../_shared/runtime.ts";

const ALLOWED_ORIGINS = ["https://admin.kridiyatravel.com", "http://localhost:8138", "http://localhost:8137"];
function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return { "Access-Control-Allow-Origin": allow, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", Vary: "Origin" };
}
function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } });
}
function strongInternalPassword() {
  const bytes = new Uint8Array(24); crypto.getRandomValues(bytes);
  return `Kridiya!A9-${Array.from(bytes, (v) => v.toString(16).padStart(2, "0")).join("")}`;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  const { url, publishableKey: anonKey, secretKey: serviceKey } = supabaseRuntimeKeys();
  if (!url || !anonKey || !serviceKey) {
    console.error("reset-staff-pin: required Supabase runtime keys are unavailable");
    return json({ error: "PIN reset is temporarily unavailable." }, 503, origin);
  }
  const authHeader = req.headers.get("Authorization") || "";
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: isAdmin, error: adminErr } = await caller.rpc("is_admin");
  if (adminErr || !isAdmin) return json({ error: "Only admins can reset a staff PIN" }, 403, origin);
  const { error: recentAuthError } = await caller.rpc("require_recent_auth", { max_age_seconds: 1800 });
  if (recentAuthError) return json({ error: "Recent authentication required. Sign in again to continue." }, 401, origin);
  const { data: callerData } = await caller.auth.getUser();
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid request body" }, 400, origin); }
  const targetUserId = String(body.user_id || "").trim();
  if (!targetUserId) return json({ error: "Missing user_id" }, 400, origin);
  const admin = createClient(url, serviceKey);
  let pin = "";
  for (let attempt = 0; attempt < 10; attempt++) {
    const candidate = generateSixDigitPin();
    const { data: used, error } = await admin.rpc("staff_pin_in_use", { p_pin: candidate, p_exclude_user_id: targetUserId });
    if (error) return json({ error: "Could not check PIN availability." }, 503, origin);
    if (!used) { pin = candidate; break; }
  }
  if (!pin) return json({ error: "Could not generate a unique PIN - try again." }, 500, origin);
  const { error: pinError } = await admin.rpc("staff_set_pin", { p_user_id: targetUserId, p_pin: pin });
  if (pinError) return json({ error: "The PIN could not be saved." }, 500, origin);
  const { error: updateError } = await admin.auth.admin.updateUserById(targetUserId, { password: strongInternalPassword() });
  if (updateError) {
    console.error("reset-staff-pin: PIN stored but auth password rotation failed", updateError.message);
    return json({ error: "The PIN was stored but account security could not be finalized. Please reset again." }, 500, origin);
  }
  await admin.from("audit_events").insert({ actor_user_id: callerData?.user?.id ?? null, event_type: "staff.pin_reset", entity_type: "user", entity_id: targetUserId, metadata: {} });
  // Sensitive: the plaintext PIN is returned once for the administrator to deliver securely.
  // Do not add request/response body logging on this path.
  return json({ pin }, 200, origin);
});
