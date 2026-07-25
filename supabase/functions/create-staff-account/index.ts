// Kridiya Travel — admin creates a new staff account.
// Runs with the service role (server-side only, never exposed to the
// browser) so it can create an auth user and set their PIN as the
// password without disturbing the calling admin's own session.
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
    return json({ error: "Only admins can create staff accounts" }, 403, origin);
  }
  const { data: callerData } = await callerClient.auth.getUser();
  const callerId = callerData?.user?.id ?? null;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400, origin);
  }

  const fullName = String(body.full_name || "").trim();
  const department = String(body.department || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const role = String(body.role || "staff");
  const validRoles = ["owner", "admin", "staff", "support"];

  if (!fullName || fullName.length < 2) return json({ error: "Enter the staff member's name." }, 400, origin);
  if (!email || !email.includes("@")) return json({ error: "Enter a valid email address." }, 400, origin);
  if (!validRoles.includes(role)) return json({ error: "Invalid role." }, 400, origin);

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const anonClient = createClient(SUPABASE_URL, ANON_KEY);

  // Staff sign in with the PIN alone (no name picker), so a PIN has to
  // be unique across every active staff account — otherwise it would
  // be ambiguous whose account it logs into. Since PINs are stored only
  // as hashed Supabase Auth passwords, the sole way to check "is this
  // PIN already taken" is to try it against everyone else's email.
  const { data: existingProfiles } = await adminClient.from("staff_profiles").select("user_id").eq("active", true);
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

  const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
    email,
    password: pin,
    email_confirm: true,
    user_metadata: { full_name: fullName }
  });

  if (createErr || !created?.user) {
    return json({ error: createErr?.message || "Could not create the account." }, 400, origin);
  }
  const newUserId = created.user.id;

  const { error: profileErr } = await adminClient.from("staff_profiles").insert({
    user_id: newUserId,
    full_name: fullName,
    department: department || null,
    created_by: callerId
  });
  if (profileErr) {
    return json({ error: "Account created but profile setup failed: " + profileErr.message }, 500, origin);
  }

  const { error: roleErr } = await adminClient.from("staff_roles").insert({ user_id: newUserId, role });
  if (roleErr) {
    return json({ error: "Account created but role assignment failed: " + roleErr.message }, 500, origin);
  }

  await adminClient.from("audit_events").insert({
    actor_user_id: callerId,
    event_type: "staff.created",
    entity_type: "user",
    entity_id: newUserId,
    metadata: { full_name: fullName, department, email, role }
  });

  return json({ user_id: newUserId, pin, email }, 200, origin);
});
