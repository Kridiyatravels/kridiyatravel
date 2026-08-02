import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientAddress, supabaseRuntimeKeys } from "../_shared/runtime.ts";

const META_DATASET_ID = "1584188866628210";
const META_GRAPH_API_VERSION = "v25.0";
const ALLOWED_ORIGINS = new Set([
  "https://kridiyatravel.com",
  "https://www.kridiyatravel.com",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
]);

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://www.kridiyatravel.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

function json(origin: string | null, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(origin) });
}

function cleanString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const clean = value.trim();
  return clean ? clean.slice(0, maxLength) : undefined;
}

function validTrackingCookie(value: unknown): string | undefined {
  const clean = cleanString(value, 200);
  return clean && /^[A-Za-z0-9._-]+$/.test(clean) ? clean : undefined;
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") return json(origin, 405, { error: "Method not allowed" });
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json(origin, 403, { error: "Origin not allowed" });

  // This is intentionally a public browser endpoint. A publishable key and
  // Origin are routing/CORS signals, not authentication. Abuse is constrained
  // below with server-side IP rate limiting and event-id deduplication.
  const { url: supabaseUrl, publishableKey, secretKey } = supabaseRuntimeKeys();
  if (!supabaseUrl || !publishableKey || !secretKey) {
    console.error("meta-conversions: required Supabase runtime keys are unavailable");
    return json(origin, 503, { error: "Conversion tracking is temporarily unavailable" });
  }
  const suppliedKey = request.headers.get("apikey");
  if (!suppliedKey || suppliedKey !== publishableKey) {
    return json(origin, 401, { error: "Invalid project key" });
  }

  const accessToken = Deno.env.get("META_CAPI_ACCESS_TOKEN");
  if (!accessToken) return json(origin, 503, { error: "Meta CAPI is not configured" });

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return json(origin, 400, { error: "Invalid JSON" });
  }

  if (payload.event_name !== "Lead") return json(origin, 400, { error: "Unsupported event" });
  const eventId = cleanString(payload.event_id, 128);
  if (!eventId || !/^[A-Za-z0-9._:-]{8,128}$/.test(eventId)) {
    return json(origin, 400, { error: "Invalid event ID" });
  }

  const address = clientAddress(request);
  const addressDigest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(secretKey + "|meta|" + address),
  );
  const ipHash = Array.from(new Uint8Array(addressDigest), (value) => value.toString(16).padStart(2, "0")).join("");
  const admin = createClient(supabaseUrl, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: admission, error: admissionError } = await admin.rpc("admit_meta_conversion", {
    p_ip_hash: ipHash,
    p_event_id: eventId,
  });
  if (admissionError) {
    console.error("meta-conversions: abuse-control check failed", admissionError.message);
    return json(origin, 503, { error: "Conversion tracking is temporarily unavailable" });
  }
  if (admission === "rate_limited") return json(origin, 429, { error: "Too many requests" });
  if (admission === "duplicate") return json(origin, 200, { ok: true, duplicate: true });

  const eventSourceUrl = cleanString(payload.event_source_url, 1000);
  let source: URL;
  try {
    source = new URL(eventSourceUrl || "");
  } catch {
    return json(origin, 400, { error: "Invalid event source URL" });
  }
  if (source.protocol !== "https:" ||
      (source.hostname !== "kridiyatravel.com" && source.hostname !== "www.kridiyatravel.com")) {
    return json(origin, 400, { error: "Event source is not Kridiya Travel" });
  }

  const clientIp = cleanString(address === "unknown" ? undefined : address, 64);
  const clientUserAgent = cleanString(payload.client_user_agent, 500);
  const userData: Record<string, string> = {};
  if (clientIp) userData.client_ip_address = clientIp;
  if (clientUserAgent) userData.client_user_agent = clientUserAgent;
  const fbp = validTrackingCookie(payload.fbp);
  const fbc = validTrackingCookie(payload.fbc);
  if (fbp) userData.fbp = fbp;
  if (fbc) userData.fbc = fbc;

  const incomingCustom = payload.custom_data && typeof payload.custom_data === "object"
    ? payload.custom_data as Record<string, unknown>
    : {};
  const customData: Record<string, string> = {
    content_name: cleanString(incomingCustom.content_name, 100) || "general",
    content_category: cleanString(incomingCustom.content_category, 100) || "website",
  };

  const graphPayload: Record<string, unknown> = {
    data: [{
      event_name: "Lead",
      event_time: Math.floor(Date.now() / 1000),
      event_id: eventId,
      action_source: "website",
      event_source_url: source.href,
      user_data: userData,
      custom_data: customData,
    }],
  };
  const testEventCode = Deno.env.get("META_TEST_EVENT_CODE");
  if (testEventCode) graphPayload.test_event_code = testEventCode;

  const metaResponse = await fetch(
    `https://graph.facebook.com/${META_GRAPH_API_VERSION}/${META_DATASET_ID}/events`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(graphPayload),
    },
  );
  const metaResult = await metaResponse.json().catch(() => ({}));
  if (!metaResponse.ok) {
    console.error("Meta CAPI request failed", {
      status: metaResponse.status,
      type: metaResult?.error?.type,
      code: metaResult?.error?.code,
    });
    return json(origin, 502, { error: "Meta rejected the event" });
  }

  return json(origin, 200, {
    ok: true,
    events_received: metaResult.events_received || 1,
    fbtrace_id: metaResult.fbtrace_id || null,
  });
});
