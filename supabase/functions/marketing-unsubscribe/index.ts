import { createClient } from "jsr:@supabase/supabase-js@2";
import { supabaseRuntimeKeys } from "../_shared/runtime.ts";

const ALLOWED_ORIGINS = new Set([
  "https://kridiyatravel.com",
  "https://www.kridiyatravel.com",
  "http://localhost:8765",
  "http://127.0.0.1:8765",
]);

function headers(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://www.kridiyatravel.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

function json(origin: string | null, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) });
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((value.length + 3) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function signature(payload: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64Url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload))));
}

async function makeToken(email: string, secret: string): Promise<string> {
  const encodedEmail = base64Url(new TextEncoder().encode(email));
  const expires = Math.floor(Date.now() / 1000) + 24 * 60 * 60;
  const payload = `${encodedEmail}.${expires}`;
  return `${payload}.${await signature(payload, secret)}`;
}

async function verifyToken(token: string, secret: string): Promise<string | null> {
  const [encodedEmail, expiresText, suppliedSignature, extra] = token.split(".");
  if (!encodedEmail || !expiresText || !suppliedSignature || extra) return null;
  const expires = Number(expiresText);
  if (!Number.isSafeInteger(expires) || expires < Math.floor(Date.now() / 1000)) return null;
  const expected = await signature(`${encodedEmail}.${expiresText}`, secret);
  if (expected.length !== suppliedSignature.length) return null;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index++) mismatch |= expected.charCodeAt(index) ^ suppliedSignature.charCodeAt(index);
  if (mismatch !== 0) return null;
  try {
    const email = new TextDecoder().decode(decodeBase64Url(encodedEmail)).trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 320 ? email : null;
  } catch {
    return null;
  }
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: headers(origin) });
  if (request.method !== "POST") return json(origin, 405, { error: "Method not allowed" });
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json(origin, 403, { error: "Origin not allowed" });

  const signingSecret = Deno.env.get("UNSUBSCRIBE_SIGNING_SECRET") || "";
  const { url, secretKey } = supabaseRuntimeKeys();
  if (!signingSecret || !url || !secretKey) {
    console.error("marketing-unsubscribe: required runtime configuration is unavailable");
    return json(origin, 503, { error: "Email preferences are temporarily unavailable" });
  }
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json(origin, 400, { error: "Invalid request" }); }

  const admin = createClient(url, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (token) {
    const email = await verifyToken(token, signingSecret);
    if (!email) return json(origin, 400, { error: "This unsubscribe link is invalid or expired" });
    const { error } = await admin.from("marketing_suppression_events").insert({
      email,
      source: "signed_unsubscribe",
      requested_at: new Date().toISOString(),
    });
    if (error && error.code !== "23505") {
      console.error("marketing-unsubscribe: suppression insert failed", error.message);
      return json(origin, 503, { error: "Email preferences are temporarily unavailable" });
    }
    return json(origin, 200, { ok: true, confirmed: true });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320) {
    return json(origin, 400, { error: "Enter a valid email address" });
  }
  const resendKey = Deno.env.get("RESEND_API_KEY") || "";
  if (!resendKey) return json(origin, 503, { error: "Confirmation email is temporarily unavailable" });
  const confirmationToken = await makeToken(email, signingSecret);
  const confirmUrl = `https://www.kridiyatravel.com/unsubscribe.html?token=${encodeURIComponent(confirmationToken)}`;
  const emailResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: Deno.env.get("UNSUBSCRIBE_FROM_EMAIL") || "Kridiya Travel <deals@kridiyatravel.com>",
      to: [email],
      subject: "Confirm your Kridiya Travel unsubscribe request",
      html: `<p>Confirm that you want to stop promotional emails from Kridiya Travel.</p><p><a href="${confirmUrl}">Confirm unsubscribe</a></p><p>This link expires in 24 hours.</p>`,
    }),
  });
  if (!emailResponse.ok) {
    console.error("marketing-unsubscribe: confirmation email failed", { status: emailResponse.status });
    return json(origin, 502, { error: "Could not send confirmation email" });
  }
  return json(origin, 202, { ok: true, pending_confirmation: true });
});
