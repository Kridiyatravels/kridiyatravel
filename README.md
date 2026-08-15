# Kridiya Travel public website

Static website for Kridiya Travel and Tourism FZ-LLC. The production site is
served at `https://www.kridiyatravel.com/`.

## Local preview

Serve the repository root with any static HTTP server. There is no framework,
package installation, CSS library, or build step.

## Quality checks

Run with Node.js 20 or newer:

```sh
node scripts/site-check.mjs
node scripts/smoke-contracts.mjs
```

The checks validate HTML metadata and JSON-LD, local links and assets, sitemap
entries, file-size budgets, and the browser/backend contracts for registration,
staff PIN login, corporate quote responses, and unsubscribe.

## Repository boundaries

- `docs/` contains private operating and security material. It is deliberately
  ignored and must never be added to this public repository or published site.
- `kridiya-corporate-live/` is a separate repository and is ignored here.
- Supabase schema changes live under `supabase/migrations/`. Production
  migration history was reconciled against this directory on 15 August 2026.
  Before any deployment, compare local and remote migration lists, review the
  exact pending SQL, and apply only the intended timestamped migrations. Never
  use an unreviewed blanket database push.
- Never commit service-role/secret keys, staff PINs, customer data, or production
  smoke-test credentials.
