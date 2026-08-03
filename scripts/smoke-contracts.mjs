import fs from "node:fs";

const failures = [];
function requireText(file, patterns) {
  const text = fs.readFileSync(file, "utf8");
  for (const [label, pattern] of patterns) if (!pattern.test(text)) failures.push(`${file}: missing ${label}`);
}

requireText("register.html", [
  ["registration form", /id=["']register-form["']/],
  ["email input", /type=["']email["']/],
]);
requireText("js/auth.js", [
  ["customer sign-up call", /\.signUp\s*\(/],
  ["session restoration", /function\s+session\s*\([\s\S]*localStorage\.getItem/],
]);
requireText("supabase/functions/staff-pin-login/index.ts", [
  ["six-digit PIN validation", /\^\\d\{6\}\$/],
  ["atomic login admission", /staff_pin_login_begin/],
  ["login completion", /staff_pin_login_finish/],
]);
requireText("supabase/migrations/20260803093548_fix_booking_linked_quote_responses.sql", [
  ["corporate quote response RPC", /respond_my_corporate_quote/],
  ["corporate membership authorization", /corporate_portal_members/],
]);
requireText("supabase/functions/microsoft-documents/index.ts", [
  ["Microsoft application token flow", /client_credentials/],
  ["staff permission checks", /has_staff_permission/],
  ["booking document upload", /upload_booking_document/],
  ["payment proof upload", /upload_payment_proof/],
  ["supplier invoice upload", /upload_supplier_invoice/],
  ["authorized document download", /download_booking_document/],
]);
requireText("js/auth.js", [
  ["Microsoft-backed customer download", /microsoft-documents/],
  ["legacy Supabase download fallback", /createSignedUrl\(storagePath/],
]);
if (fs.existsSync("supabase/functions/marketing-unsubscribe/index.ts")) {
  requireText("js/unsubscribe.js", [
    ["unsubscribe function invocation", /marketing-unsubscribe/],
    ["signed token handling", /URLSearchParams[\s\S]*token/],
  ]);
  requireText("supabase/functions/marketing-unsubscribe/index.ts", [
    ["token verification", /verifyToken/],
    ["pending confirmation response", /pending_confirmation/],
  ]);
} else {
  requireText("js/unsubscribe.js", [
    ["legacy suppression insert", /marketing_suppression_events[\s\S]*\.insert/],
    ["website unsubscribe source", /website_unsubscribe/],
  ]);
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("Registration, staff PIN, quote response, unsubscribe, and Microsoft document contracts are present.");
