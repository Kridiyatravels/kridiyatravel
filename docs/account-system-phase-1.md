# Kridiya Account System - Phase 1 Build Plan

Last updated: July 19, 2026

This is the practical "real account system" plan for Kridiya Travel. It replaces the current browser-only localStorage login with Supabase Auth, Supabase Postgres, Row Level Security, and later payment-provider tokenization.

## 1. Final Architecture

Use three layers:

- Public website: the existing GitHub Pages HTML/CSS/JS site.
- Customer account backend: Supabase Auth + Postgres + RLS.
- Back office: Microsoft 365 for staff email, SharePoint/OneDrive documents, and internal records.

Payment cards are not stored by Kridiya. Razorpay or Stripe stores real card details and gives Kridiya a safe payment token or payment method ID. Kridiya may store only non-sensitive display data such as brand, last4, expiry, provider customer ID, and token/reference IDs.

## 2. What Exists Today

The current account system is in:

- `js/auth.js`: localStorage users, local password hash, session storage.
- `login.html`: login form.
- `register.html`: account creation form.
- `account.html`: profile, enquiry history, change password.
- `js/main.js`: navbar account button and local enquiry archiving.

This is fine as a prototype, but it is not a shared customer database. Accounts exist only on one browser, customers cannot reset passwords securely by email, and bookings cannot be safely linked across devices.

## 3. Build Order

### Phase 1A - Supabase foundation

1. Create a Supabase project.
2. Enable email/password Auth.
3. Turn on email confirmation.
4. Configure redirect URLs:
   - `https://www.kridiyatravel.com/`
   - `https://www.kridiyatravel.com/` if used
   - local test URL if needed
5. Run `supabase/kridiya_phase1_schema.sql` in the Supabase SQL editor.
6. Add the public Supabase URL and publishable/anon key to a small site config file.
7. Create your own staff login, then mark it as owner in SQL:

```sql
insert into public.staff_roles (user_id, role)
values ('YOUR-SUPABASE-AUTH-USER-ID', 'owner')
on conflict (user_id) do update set role = excluded.role;
```

### Phase 1B - Site wiring

1. Replace the internals of `js/auth.js` with Supabase calls while preserving the current `KridiyaAuth` public API.
2. On register, call `supabase.auth.signUp()` with `full_name` and `phone` metadata.
3. On login, call `supabase.auth.signInWithPassword()`.
4. On account load, call `supabase.auth.getUser()` for the trusted logged-in user.
5. Fetch:
   - `profiles` where `id = user.id`
   - `bookings` where `user_id = user.id`
6. On profile update, update only the user's own `profiles` row.
7. Replace manual "WhatsApp us to reset" with Supabase password reset email.

### Phase 1C - Legal and trust pages

1. Publish `privacy.html`.
2. Publish `terms.html`.
3. Link both in the footer.
4. Add a clear data deletion/contact process in the Privacy Policy.

### Phase 1D - Staff workflow

Start with the Supabase dashboard for bookings. Later, add either:

- a small internal admin page protected by staff roles, or
- a Microsoft Power App for staff.

## 4. Tables

The starter SQL creates:

- `profiles`: customer name, phone, email, preferences.
- `bookings`: customer booking/enquiry records linked by `user_id`.
- `booking_travellers`: traveller names linked to a booking.
- `booking_documents`: metadata for invoices/e-tickets/customer-visible files.
- `payment_methods`: future saved-card token references, not raw cards.
- `consents`: privacy/terms/marketing acceptance records.
- `account_deletion_requests`: customer data deletion workflow.
- `staff_roles`: staff/admin roles for future admin tooling.
- `audit_events`: staff/system audit log.

## 5. Security Rules

The core rule is:

```sql
user_id = auth.uid()
```

That is the link between a customer account and their bookings. Row Level Security means a signed-in customer can only read rows that belong to their own Supabase Auth user ID.

Customers can:

- read their own profile;
- update their own profile;
- read their own bookings;
- read their own booking travellers/documents;
- create their own consent records;
- create their own deletion request.

Customers cannot:

- read other customers;
- edit booking status or amounts;
- insert/update payment token rows directly;
- read provider secrets or raw payment tokens;
- access staff/audit data.

Staff/admin access is handled through `staff_roles` and should be used only for an internal admin screen later. Until then, use the Supabase dashboard.

## 6. Payment Card Rule

Do not store raw card numbers, CVV, card PIN, OTP, or full magnetic-stripe/chip data anywhere in Kridiya systems.

Future saved-card flow:

1. Customer chooses "save card" inside Razorpay/Stripe checkout.
2. Payment provider handles card entry, consent, authentication, and tokenization.
3. Provider returns a token/payment method ID.
4. Supabase Edge Function stores:
   - `provider`
   - `provider_customer_id`
   - `provider_payment_method_id`
   - `brand`
   - `last4`
   - `exp_month`
   - `exp_year`
   - `consent_at`
5. Customer-facing pages show only brand/last4/expiry.

This keeps Kridiya out of raw-card storage and dramatically reduces PCI risk.

## 7. Microsoft 365 Role

M365 is still useful, but not as the public customer-login database.

Use M365 for:

- `info@`, `enquiry@`, and staff email;
- internal booking spreadsheets or SharePoint Lists;
- staff-only documents;
- passport scans and sensitive back-office files;
- staff collaboration and approvals.

Use Supabase for:

- customer login;
- customer profiles;
- customer booking history;
- customer-facing account data;
- server-side payment/API functions.

## 8. Site Files To Change During Wiring

- `register.html`
  - Replace browser-only storage note.
  - Link Privacy Policy and Terms.

- `login.html`
  - Add "Forgot password?" email reset.

- `account.html`
  - Rename "My enquiries" to "My bookings and enquiries" once Supabase bookings are live.
  - Fetch live rows from Supabase.

- `js/auth.js`
  - Swap localStorage auth internals for Supabase Auth.
  - Preserve `KridiyaAuth.session()`, `register()`, `login()`, `logout()`, `updateProfile()`, `changePassword()` where possible.

- `js/main.js`
  - Read session state from Supabase.
  - Archive future enquiries to Supabase or Edge Function instead of localStorage.

## 9. Supabase Setup Clicks

1. Go to Supabase and create a new project.
2. Authentication -> Providers -> Email:
   - enable Email provider;
   - enable Confirm email;
   - set secure password requirements if available.
3. Authentication -> URL Configuration:
   - set Site URL to `https://www.kridiyatravel.com`;
   - add redirect URLs for production and local test URLs.
4. Authentication -> Sessions:
   - keep default JWT expiry around 1 hour;
   - consider inactivity timeout and single-session settings when on a paid plan.
5. SQL Editor:
   - paste and run `supabase/kridiya_phase1_schema.sql`.
6. Project Settings -> API:
   - copy Project URL;
   - copy publishable/anon key only;
   - never put the service role/secret key in browser JavaScript.
7. Edge Functions:
   - use them later for payment creation, payment webhooks, document signed URLs, and Akbar/API integrations.

## 10. Launch Checklist

- Email confirmation works.
- Password reset works.
- Register creates a profile row.
- Account page refuses unsigned users.
- Account page shows only the signed-in user's rows.
- Another user cannot fetch the first user's bookings by changing an ID in the browser.
- Privacy and Terms links are visible.
- Test account deletion request flow.
- Staff can add/update booking records.
- No API secret/service role/payment secret exists in public JS or HTML.
- Payment card saving remains disabled until Razorpay/Stripe business verification is complete.

## 11. Sources Checked

- Supabase JavaScript Auth overview: https://supabase.com/docs/reference/javascript/auth
- Supabase `signUp`: https://supabase.com/docs/reference/javascript/auth-signup
- Supabase `signInWithPassword`: https://supabase.com/docs/reference/javascript/auth-signinwithpassword
- Supabase `getUser`: https://supabase.com/docs/reference/javascript/auth-getuser
- Supabase `resetPasswordForEmail`: https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail
- Supabase sessions: https://supabase.com/docs/guides/auth/sessions
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Edge Function secrets: https://supabase.com/docs/guides/functions/secrets
- Razorpay saved cards: https://razorpay.com/docs/payments/payment-methods/cards/features/saved-cards/
- Razorpay tokenisation: https://razorpay.com/docs/payments/optimizer/tokenisation/
- Stripe Setup Intents: https://docs.stripe.com/payments/setup-intents
- UAE data protection laws: https://u.ae/en/about-the-uae/digital-uae/data/data-protection-laws.
- UAE Federal Decree-Law No. 45 of 2021: https://uaelegislation.gov.ae/en/legislations/1972
- India DPDP Act summary from MeitY/PIB: https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1947264
