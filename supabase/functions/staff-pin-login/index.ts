// Kridiya Travel - staff PIN sign-in.
// The browser submits only a six-digit PIN. Sensitive lookup and rate-limit
// operations use the server-only Supabase secret key inside this Edge Function.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientAddress, supabaseRuntimeKeys } from "../_shared/runtime.ts";

const ALLOWED_ORIGINS = [
  "https://admin.kridiyatravel.com",
  "http://localhost:8138",
  "http://localhost:8137"
];

function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin"
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" }
  });
}

async function hashAddress(address: string, secretKey: string) {
  const bytes = new TextEncoder().encode(secretKey + "|" + address);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function strongInternalPassword() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return `Kridiya!A9-${Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("")}`;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    return json({ error: "Origin not allowed" }, 403, origin);
  }

  const { url: supabaseUrl, publishableKey, secretKey } = supabaseRuntimeKeys();
  if (!supabaseUrl || !publishableKey || !secretKey) {
    console.error("staff-pin-login: required Supabase runtime keys are unavailable");
    return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400, origin);
  }

  const pin = String(body.pin || "").trim();
  if (!/^\d{6}$/.test(pin)) {
    return json({ error: "Enter your 6-digit PIN." }, 400, origin);
  }

  const forwardedAddress = clientAddress(req);
  const ipHash = await hashAddress(forwardedAddress, secretKey);
  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const { data: admission, error: admissionError } = await admin.rpc("staff_pin_login_begin", { p_ip_hash: ipHash });
  if (admissionError) {
    console.error("staff-pin-login: rate-limit admission failed", admissionError.message);
    return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
  }
  if (admission?.allowed !== true) {
    const retryAfter = Number(admission?.retry_after_seconds || 900);
    return new Response(JSON.stringify({ error: "Too many attempts. Try again later." }), {
      status: 429,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json", "Retry-After": String(retryAfter) }
    });
  }
  const attemptId = String(admission.attempt_id || "");

  // This RPC is executable only by service_role after the matching migration.
  const { data: identity, error: rpcError } = await admin.rpc("staff_identity_for_pin", { p_pin: pin });
  const email = identity && typeof identity.email === "string" ? identity.email : "";
  const userId = identity && typeof identity.user_id === "string" ? identity.user_id : "";
  if (rpcError || !email || !userId) {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  const authPassword = strongInternalPassword();
  const { error: rotateError } = await admin.auth.admin.updateUserById(userId, { password: authPassword });
  if (rotateError) {
    console.error("staff-pin-login: internal password rotation failed", rotateError.message);
    return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
  }

  // Supabase Auth performs the authoritative password check and issues session tokens.
  async function exchangePassword(password: string) {
    const response = await fetch(supabaseUrl + "/auth/v1/token?grant_type=password", {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: publishableKey },
      body: JSON.stringify({ email, password })
    });
    return { response, token: await response.json().catch(() => ({})) };
  }
  let { response: authResponse, token } = await exchangePassword(authPassword);
  if (!authResponse.ok || !token.access_token) {
    // A concurrent login may rotate the password between update and exchange.
    const retryPassword = strongInternalPassword();
    const { error: retryRotateError } = await admin.auth.admin.updateUserById(userId, { password: retryPassword });
    if (!retryRotateError) ({ response: authResponse, token } = await exchangePassword(retryPassword));
  }
  if (!authResponse.ok || !token.access_token) {
    console.error("staff-pin-login: password exchange failed after rotation retry", { userId, status: authResponse.status });
    await admin.rpc("staff_pin_login_finish", { p_attempt_id: attemptId, p_user_id: userId, p_success: false });
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  await admin.rpc("staff_pin_login_finish", { p_attempt_id: attemptId, p_user_id: userId, p_success: true });

  // Best-effort audit as the newly signed-in user.
  try {
    const signedInUserId = token.user?.id ?? null;
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: "Bearer " + token.access_token } }
    });
    await userClient.from("audit_events").insert({
      actor_user_id: signedInUserId,
      event_type: "auth.login",
      entity_type: "user",
      entity_id: signedInUserId,
      metadata: { method: "pin" }
    });
  } catch (_error) {
    // Audit failure must never block staff access.
  }

  return json(
    { access_token: token.access_token, refresh_token: token.refresh_token },
    200,
    origin
  );
});
