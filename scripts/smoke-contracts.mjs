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
console.log("Registration, staff PIN, quote response, and unsubscribe contracts are present.");
