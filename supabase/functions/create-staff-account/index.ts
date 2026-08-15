// Kridiya Travel — admin creates a new staff account.
// Runs with the service role (server-side only, never exposed to the
// browser) so it can create an auth user and set their PIN as the
// password without disturbing the calling admin's own session.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { generateSixDigitPin, supabaseRuntimeKeys } from "../_shared/runtime.ts";

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

function strongInternalPassword() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return `Kridiya!A9-${Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("")}`;
}

async function findAuthUserByEmail(adminClient: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 10; page++) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    const found = data.users.find((u) => (u.email || "").toLowerCase() === email);
    if (found) return found;
    if (data.users.length < 100) break;
  }
  return null;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  const { url: SUPABASE_URL, publishableKey: ANON_KEY, secretKey: SERVICE_ROLE_KEY } = supabaseRuntimeKeys();
  if (!SUPABASE_URL || !ANON_KEY || !SERVICE_ROLE_KEY) {
    console.error("create-staff-account: required Supabase runtime keys are unavailable");
    return json({ error: "Staff account creation is temporarily unavailable." }, 503, origin);
  }

  const authHeader = req.headers.get("Authorization") || "";
  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } }
  });

  const { data: isAdmin, error: adminErr } = await callerClient.rpc("is_admin");
  if (adminErr || !isAdmin) {
    return json({ error: "Only admins can create staff accounts" }, 403, origin);
  }
  const { error: recentAuthError } = await callerClient.rpc("require_recent_auth", { max_age_seconds: 1800 });
  if (recentAuthError) {
    return json({ error: "Recent authentication required. Sign in again to continue." }, 401, origin);
  }
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
  const allowExistingUser = body.allow_existing_user === true;
  const validRoles = ["owner", "admin", "staff", "support"];

  if (!fullName || fullName.length < 2) return json({ error: "Enter the staff member's name." }, 400, origin);
  if (!email || !email.includes("@")) return json({ error: "Enter a valid email address." }, 400, origin);
  if (!validRoles.includes(role)) return json({ error: "Invalid role." }, 400, origin);

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  // Staff sign in with the PIN alone (no name picker), so a PIN has to
  // be unique across every active staff account — otherwise it would
  // be ambiguous whose account it logs into. staff_pin_in_use compares the
  // submitted candidate against the separate bcrypt credential hashes.
  let pin = "";
  for (let attempt = 0; attempt < 10; attempt++) {
    // Range 100000-999999: always a true 6-digit PIN, never a leading
    // zero (a leading zero gets dropped when read aloud/copied and looks
    // like a 5-digit PIN).
    const candidate = generateSixDigitPin();
    const { data: collision, error: collisionError } = await adminClient.rpc("staff_pin_in_use", { p_pin: candidate, p_exclude_user_id: null });
    if (collisionError) return json({ error: "Could not check PIN availability." }, 503, origin);
    if (!collision) { pin = candidate; break; }
  }
  if (!pin) {
    return json({ error: "Could not generate a unique PIN — try again." }, 500, origin);
  }

  const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
    email,
    password: strongInternalPassword(),
    email_confirm: true,
    user_metadata: { full_name: fullName }
  });

  let newUserId = created?.user?.id || "";
  let reusedExisting = false;
  if (createErr || !newUserId) {
    const existing = await findAuthUserByEmail(adminClient, email).catch(() => null);
    if (!existing?.id) {
      return json({ error: createErr?.message || "Could not create the account." }, 400, origin);
    }
    if (!allowExistingUser) {
      return json({ error: "An account already uses this email.", existing_user: true }, 409, origin);
    }
    reusedExisting = true;
    newUserId = existing.id;
    const { error: passwordErr } = await adminClient.auth.admin.updateUserById(newUserId, {
      password: strongInternalPassword(),
      email_confirm: true,
      user_metadata: { full_name: fullName }
    });
    if (passwordErr) return json({ error: passwordErr.message }, 400, origin);
  }

  const setup = await callerClient.rpc("setup_staff_account_record", {
    target_user_id: newUserId,
    full_name: fullName,
    department: department || null,
    role
  });
  if (setup.error) {
    if (!reusedExisting) await adminClient.auth.admin.deleteUser(newUserId).catch(() => null);
    return json({ error: "Account auth was ready but staff setup failed: " + setup.error.message }, 500, origin);
  }

  const { error: pinError } = await adminClient.rpc("staff_set_pin", { p_user_id: newUserId, p_pin: pin });
  if (pinError) {
    if (!reusedExisting) await adminClient.auth.admin.deleteUser(newUserId).catch(() => null);
    return json({ error: "Staff record was created but the PIN could not be saved." }, 500, origin);
  }

  // Sensitive: the plaintext PIN is returned once for the administrator to deliver securely.
  // Do not add request/response body logging on this path.
  return json({ user_id: newUserId, pin, email, reused_existing: reusedExisting }, 200, origin);
});
