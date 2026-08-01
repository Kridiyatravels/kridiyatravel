// Kridiya Travel - staff PIN sign-in.
// The browser submits only a six-digit PIN. Sensitive lookup and rate-limit
// operations use the server-only Supabase secret key inside this Edge Function.
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_ORIGINS = [
  "https://admin.kridiyatravel.com",
  "http://localhost:8138",
  "http://localhost:8137"
];
const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_MINUTES = 15;

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

function defaultKey(environmentName: string) {
  try {
    const keys = JSON.parse(Deno.env.get(environmentName) || "{}");
    return typeof keys.default === "string" ? keys.default : "";
  } catch {
    return "";
  }
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

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const publishableKey = defaultKey("SUPABASE_PUBLISHABLE_KEYS") || Deno.env.get("KRIDIYA_PUBLISHABLE_KEY") || "";
  const secretKey = defaultKey("SUPABASE_SECRET_KEYS");
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

  const forwardedAddress = (req.headers.get("x-forwarded-for") || "unknown").split(",")[0].trim();
  const ipHash = await hashAddress(forwardedAddress, secretKey);
  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const cutoff = new Date(Date.now() - RATE_LIMIT_MINUTES * 60 * 1000).toISOString();
  const { count: failedCount, error: countError } = await admin
    .from("staff_pin_login_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .eq("success", false)
    .gte("attempted_at", cutoff);
  if (countError) {
    console.error("staff-pin-login: rate-limit check failed", countError.message);
    return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
  }
  if ((failedCount || 0) >= MAX_FAILED_ATTEMPTS) {
    return json({ error: "Too many attempts. Try again in 15 minutes." }, 429, origin);
  }

  const { data: attempt, error: attemptError } = await admin
    .from("staff_pin_login_attempts")
    .insert({ ip_hash: ipHash, success: false })
    .select("id")
    .single();
  if (attemptError || !attempt) {
    console.error("staff-pin-login: could not record login attempt", attemptError?.message);
    return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
  }

  // Best-effort cleanup keeps only the last day of rate-limit records.
  await admin
    .from("staff_pin_login_attempts")
    .delete()
    .lt("attempted_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());

  // This RPC is executable only by service_role after the matching migration.
  const { data: identity, error: rpcError } = await admin.rpc("staff_identity_for_pin", { p_pin: pin });
  const email = identity && typeof identity.email === "string" ? identity.email : "";
  const userId = identity && typeof identity.user_id === "string" ? identity.user_id : "";
  const legacy = identity?.legacy === true;
  if (rpcError || !email || !userId) {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  let authPassword = pin;
  if (!legacy) {
    authPassword = strongInternalPassword();
    const { error: rotateError } = await admin.auth.admin.updateUserById(userId, { password: authPassword });
    if (rotateError) {
      console.error("staff-pin-login: internal password rotation failed", rotateError.message);
      return json({ error: "Staff login is temporarily unavailable." }, 503, origin);
    }
  }

  // Supabase Auth performs the authoritative password check and issues session tokens.
  const authResponse = await fetch(supabaseUrl + "/auth/v1/token?grant_type=password", {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: publishableKey },
    body: JSON.stringify({ email, password: authPassword })
  });
  const token = await authResponse.json().catch(() => ({}));
  if (!authResponse.ok || !token.access_token) {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  await admin
    .from("staff_pin_login_attempts")
    .update({ success: true })
    .eq("id", attempt.id);

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
