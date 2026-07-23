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

  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const pin = String(buf[0] % 1000000).padStart(6, "0");

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

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
