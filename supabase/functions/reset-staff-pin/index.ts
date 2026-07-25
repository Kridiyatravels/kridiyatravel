// Kridiya Travel — admin regenerates a staff member's PIN.
// Same admin-only pattern as create-staff-account: service role used
// server-side only, admin's own session is untouched.
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

  const authHeader = req.headers.get("Authorization") || "";
  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } }
  });

  const { data: isAdmin, error: adminErr } = await callerClient.rpc("is_admin");
  if (adminErr || !isAdmin) {
    return json({ error: "Only admins can reset a staff PIN" }, 403, origin);
  }
  const { data: callerData } = await callerClient.auth.getUser();
  const callerId = callerData?.user?.id ?? null;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400, origin);
  }

  const targetUserId = String(body.user_id || "").trim();
  if (!targetUserId) return json({ error: "Missing user_id" }, 400, origin);

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const anonClient = createClient(SUPABASE_URL, ANON_KEY);

  // Same PIN-uniqueness requirement as create-staff-account: staff sign
  // in with the PIN alone, so no one else active can share it. Exclude
  // the target themselves — colliding with their own current PIN is
  // fine, that's just "reset landed on the same number".
  const { data: existingProfiles } = await adminClient.from("staff_profiles").select("user_id").eq("active", true).neq("user_id", targetUserId);
  const existingEmails: string[] = [];
  for (const p of existingProfiles || []) {
    const { data: u } = await adminClient.auth.admin.getUserById(p.user_id);
    if (u?.user?.email) existingEmails.push(u.user.email);
  }

  let pin = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    const buf = new Uint32Array(1);
    crypto.getRandomValues(buf);
    // Range 100000-999999: always a true 6-digit PIN, never a leading
    // zero (a leading zero gets dropped when read aloud/copied and looks
    // like a 5-digit PIN).
    const candidate = String(100000 + (buf[0] % 900000));
    let collision = false;
    for (const existingEmail of existingEmails) {
      const { data: probe, error: probeErr } = await anonClient.auth.signInWithPassword({ email: existingEmail, password: candidate });
      if (!probeErr && probe?.session) { collision = true; break; }
    }
    if (!collision) { pin = candidate; break; }
  }
  if (!pin) {
    return json({ error: "Could not generate a unique PIN — try again." }, 500, origin);
  }

  const { error: updateErr } = await adminClient.auth.admin.updateUserById(targetUserId, { password: pin });
  if (updateErr) {
    return json({ error: updateErr.message }, 400, origin);
  }

  await adminClient.from("audit_events").insert({
    actor_user_id: callerId,
    event_type: "staff.pin_reset",
    entity_type: "user",
    entity_id: targetUserId,
    metadata: {}
  });

  return json({ pin }, 200, origin);
});
