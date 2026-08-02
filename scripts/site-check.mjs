import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const failures = [];
const htmlFiles = fs.readdirSync(root).filter((name) => name.endsWith(".html"));
const publicPages = new Set([
  "index.html", "about.html", "contact.html", "cruise.html", "flights.html",
  "holidays.html", "hotels.html", "privacy.html", "terms.html", "umrah.html", "visa.html",
]);

function fail(file, message) { failures.push(`${file}: ${message}`); }
function localTarget(value) {
  if (!value || /^(?:[a-z]+:|#|\/\/)/i.test(value)) return null;
  return decodeURIComponent(value.split(/[?#]/, 1)[0]);
}

for (const file of htmlFiles) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  if (!/^<!doctype html>/i.test(text.trimStart())) fail(file, "missing HTML5 doctype");
  if (!/<html\b[^>]*\blang=/i.test(text)) fail(file, "missing html lang attribute");
  if (!/<title>[^<]+<\/title>/i.test(text)) fail(file, "missing title");
  if (publicPages.has(file) && !/<meta\s+name=["']description["']/i.test(text)) fail(file, "missing description");
  if (publicPages.has(file) && !/<link\s+rel=["']canonical["']/i.test(text)) fail(file, "missing canonical URL");

  const ids = [...text.matchAll(/\sid=["']([^"']+)["']/gi)].map((match) => match[1]);
  const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index);
  if (duplicateIds.length) fail(file, `duplicate ids: ${[...new Set(duplicateIds)].join(", ")}`);

  for (const match of text.matchAll(/\b(?:href|src)=["']([^"']+)["']/gi)) {
    const target = localTarget(match[1]);
    if (!target || target.startsWith("mailto:") || target.startsWith("tel:")) continue;
    const resolved = path.resolve(root, target);
    if (!resolved.startsWith(root + path.sep) || !fs.existsSync(resolved)) fail(file, `broken local reference: ${match[1]}`);
  }

  for (const match of text.matchAll(/<script\s+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { JSON.parse(match[1]); } catch (error) { fail(file, `invalid JSON-LD: ${error.message}`); }
  }
}

const sitemap = fs.readFileSync(path.join(root, "sitemap.xml"), "utf8");
for (const page of publicPages) {
  const url = page === "index.html" ? "https://www.kridiyatravel.com/" : `https://www.kridiyatravel.com/${page}`;
  if (!sitemap.includes(`<loc>${url}</loc>`)) fail("sitemap.xml", `missing ${url}`);
}
for (const privatePage of ["account.html", "admin.html", "login.html", "register.html", "forgot-password.html", "reset-password.html", "corporate-account.html", "corporate-booking.html", "thanks.html", "unsubscribe.html"]) {
  if (sitemap.includes(`/${privatePage}</loc>`)) fail("sitemap.xml", `non-index page included: ${privatePage}`);
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}
for (const file of walk(path.join(root, "assets"))) {
  const bytes = fs.statSync(file).size;
  if (bytes > 2_500_000) fail(path.relative(root, file), `asset exceeds 2.5 MB limit (${bytes} bytes)`);
}
for (const file of [...htmlFiles, ...walk(path.join(root, "css")), ...walk(path.join(root, "js"))]) {
  const full = path.isAbsolute(file) ? file : path.join(root, file);
  const bytes = fs.statSync(full).size;
  if (bytes > 320_000) fail(path.relative(root, full), `page resource exceeds 320 KB limit (${bytes} bytes)`);
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log(`Validated ${htmlFiles.length} HTML files, local links, JSON-LD, sitemap, and asset budgets.`);
