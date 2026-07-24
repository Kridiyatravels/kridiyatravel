// Kridiya Travel — staff PIN sign-in.
// Called before the visitor has any session, so this function has to
// implement its own authentication rather than relying on a caller JWT
// (verify_jwt is deliberately off for this one function). The browser
// only ever sends the 6-digit PIN — no name or email is picked client
// side. Since a PIN is really just that staff member's Supabase Auth
// password, the only way to find out *whose* PIN it is without an
// identity hint is to try it against every active staff account's
// email until Supabase Auth's own rate-limited sign-in accepts one.
// Staff lists are small (a handful of people), so this stays cheap;
// create-staff-account/reset-staff-pin already reject a freshly
// generated PIN that collides with anyone else's, so at most one
// candidate should ever match.
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
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const anonClient = createClient(SUPABASE_URL, ANON_KEY);

  const { data: profiles, error: profilesErr } = await adminClient
    .from("staff_profiles")
    .select("user_id")
    .eq("active", true);

  if (profilesErr || !profiles?.length) {
    return json({ error: "Incorrect PIN." }, 401, origin);
  }

  // Try the PIN against each active staff member's email in turn — the
  // real check is this signInWithPassword call, nothing above it does
  // any verification. Stop at the first (and, by construction, only)
  // match.
  for (const p of profiles) {
    const { data: authUser } = await adminClient.auth.admin.getUserById(p.user_id);
    const email = authUser?.user?.email;
    if (!email) continue;

    const { data: signInData, error: signInErr } = await anonClient.auth.signInWithPassword({ email, password: pin });
    if (signInErr || !signInData?.session) continue;

    await adminClient.from("audit_events").insert({
      actor_user_id: p.user_id,
      event_type: "auth.login",
      entity_type: "user",
      entity_id: p.user_id,
      metadata: { method: "pin" }
    });

    return json(
      {
        access_token: signInData.session.access_token,
        refresh_token: signInData.session.refresh_token
      },
      200,
      origin
    );
  }

  return json({ error: "Incorrect PIN." }, 401, origin);
});
