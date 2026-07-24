// Kridiya Travel — staff PIN sign-in.
// Called before the visitor has any session, so this function does its
// own authentication (verify_jwt is deliberately off here). The browser
// only ever sends the 6-digit PIN — no name or email is picked client
// side. A PIN is just that staff member's Supabase Auth password, so:
//   1. staff_email_for_pin() (a SECURITY DEFINER db function) matches the
//      PIN against every active staff member's stored bcrypt hash and
//      returns the owning email — only when the PIN is correct, so it
//      never leaks staff emails.
//   2. We then mint a real session via Supabase Auth's own token
//      endpoint. Everything uses the public publishable key.
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_ORIGINS = ["https://admin.kridiyatravel.com", "http://localhost:8138", "http://localhost:8137"];

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

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  // Use the publishable key throughout. The auto-injected legacy JWT keys
  // (SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY) are disabled on this
  // project in favour of the new key system, so any Supabase call made
  // with them is rejected — which is why the previous versions of this
  // function always returned "Incorrect PIN". The publishable key is the
  // same public value the site already ships.
  const PUBLISHABLE_KEY = Deno.env.get("KRIDIYA_PUBLISHABLE_KEY") || "sb_publishable_wiA9tSt74X-UQhW4yOXgIQ_lEUG1Q1Q";

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

  const pub = createClient(SUPABASE_URL, PUBLISHABLE_KEY);

  // Resolve whose PIN this is. staff_email_for_pin() (SECURITY DEFINER)
  // checks the PIN against each active staff member's stored bcrypt hash
  // in the database and returns the matching email — and only returns an
  // email when the PIN is correct, so it can't be used to enumerate staff.
  const { data: email, error: rpcErr } = await pub.rpc("staff_email_for_pin", { p_pin: pin });
  if (rpcErr || !email || typeof email !== "string") {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  // Mint a real session through Supabase Auth's own rate-limited token
  // endpoint (this second check is the authoritative one).
  const resp = await fetch(SUPABASE_URL + "/auth/v1/token?grant_type=password", {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: PUBLISHABLE_KEY },
    body: JSON.stringify({ email, password: pin })
  });
  const tok = await resp.json().catch(() => ({}));
  if (!resp.ok || !tok.access_token) {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  // Best-effort login audit, as the just-signed-in user. Never blocks login.
  try {
    const uid = tok.user?.id ?? null;
    const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
      global: { headers: { Authorization: "Bearer " + tok.access_token } }
    });
    await userClient.from("audit_events").insert({
      actor_user_id: uid,
      event_type: "auth.login",
      entity_type: "user",
      entity_id: uid,
      metadata: { method: "pin" }
    });
  } catch (_e) { /* audit is best-effort */ }

  return json(
    { access_token: tok.access_token, refresh_token: tok.refresh_token },
    200,
    origin
  );
});
