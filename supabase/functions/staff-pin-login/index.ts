// Kridiya Travel — staff PIN sign-in.
// Called before the visitor has any session, so this function has to
// implement its own authentication rather than relying on a caller JWT
// (verify_jwt is deliberately off for this one function). It resolves
// the staff member's real email server-side — the browser only ever
// sees a name/department picker, never the email — signs in through
// Supabase Auth's normal rate-limited password endpoint, and hands the
// resulting session tokens back for the browser to adopt.
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

  const staffProfileId = String(body.staff_profile_id || "").trim();
  const pin = String(body.pin || "").trim();

  if (!staffProfileId || !/^\d{4,8}$/.test(pin)) {
    return json({ error: "Pick your name and enter your PIN." }, 400, origin);
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: profile, error: profileErr } = await adminClient
    .from("staff_profiles")
    .select("user_id, active")
    .eq("id", staffProfileId)
    .maybeSingle();

  if (profileErr || !profile || !profile.active) {
    return json({ error: "Incorrect name or PIN." }, 401, origin);
  }

  const { data: authUser, error: authUserErr } = await adminClient.auth.admin.getUserById(profile.user_id);
  if (authUserErr || !authUser?.user?.email) {
    return json({ error: "Incorrect name or PIN." }, 401, origin);
  }

  // The real sign-in, through Supabase's own rate-limited endpoint —
  // this call is what actually checks the PIN, nothing above it does.
  const anonClient = createClient(SUPABASE_URL, ANON_KEY);
  const { data: signInData, error: signInErr } = await anonClient.auth.signInWithPassword({
    email: authUser.user.email,
    password: pin
  });

  if (signInErr || !signInData?.session) {
    return json({ error: "Incorrect name or PIN." }, 401, origin);
  }

  await adminClient.from("audit_events").insert({
    actor_user_id: profile.user_id,
    event_type: "auth.login",
    entity_type: "user",
    entity_id: profile.user_id,
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
});
