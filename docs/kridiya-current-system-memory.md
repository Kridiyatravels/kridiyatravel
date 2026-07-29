# Kridiya Current System Memory

Last updated: 2026-07-29
Last reviewed: 2026-07-29

Use this file as the handoff memory for a new Codex or Claude chat.

## 2026-07-29 Resume Checkpoint

This is the canonical place to resume Kridiya work. Read this file first, then
check both repositories with `git status` and recent `git log` before editing.
The detailed operating plans and SOPs remain in the linked documents under
`docs/`; this file records the current state and the next unfinished action.

### Memory coverage

This handoff covers the complete known Kridiya scope:

- legal company facts, licence, VAT status, bank details, contacts, suppliers,
  and business rules;
- brand, domains, public website, service pages, enquiries, SEO, authentication,
  customer accounts, and customer portal;
- corporate public requests, company/contact CRM, conversion, bookings,
  LPO/approval, finance, accounting, documents, backups, and the limited
  customer-facing corporate portal;
- staff PIN login, roles, permissions, activity monitoring, security controls,
  dashboard, enquiries, customers, bookings, payments/refunds, documents,
  templates, portals, accounting, backups, and handover SOP;
- Supabase project, schema, RPCs, Edge Functions, storage, RLS/permission
  direction, migrations, and audit events;
- Microsoft 365/SharePoint folder, export, archive, and contingency strategy;
- supplier portal and supplier invoice controls;
- payment proof, receipts, customer/supplier money, refunds, profit, and
  no-VAT document rules;
- email, WhatsApp, auth-email, and document-template systems;
- digital marketing, campaign attribution, content, CRM growth, privacy, and
  the proposed 90-day growth plan;
- current repositories, recent commits, uncommitted work, validation results,
  deployment rules, remaining risks, and the exact next action.

### Exact stopping point

- Main public repository HEAD: `cf98abb` (`Add corporate application approval
  RPC`). Its `origin/main` is `8fca3e2`, so two commits are local-only:
  `0572905` (`Use corporate mailbox for corporate requests`) and `cf98abb`.
- Admin repository HEAD: `277b38e` (`Simplify dashboard focus`), matching
  `origin/main`. It has no unfinished application-code edits; its only
  untracked items are `.impeccable/` and `PRODUCT.md`.
- A separate nested corporate-site repository exists at
  `C:\Users\Who\kridiya1\kridiya-corporate-live`, with remote
  `Kridiyatravels/kridiya-corporate`. Its HEAD is `22dae81` (`Upgrade corporate
  portal dashboard`), one commit ahead of `origin/main` (`76d72d3`), with
  uncommitted changes to `css/corporate.css` and `services.html` plus an
  untracked local preview server.
- The main public repository still has an unfinished, uncommitted contextual
  travel-illustration enhancement across 19 tracked HTML/CSS/JS files. It adds
  production candidates under `assets/illustrations/`, older/alternate
  character art under `assets/characters/`, a source SVG, and generated visual
  references under `output/`.
- The main public worktree also contains untracked proposed marketing-plan
  material under `docs/marketing-system/`, an untracked linked worktree under
  `.codex-worktrees/corporate-approval/`, and the nested corporate repository.
  These are not part of the main public repository's current commit history.
- Do not discard, overwrite, or accidentally include these unrelated active
  worktrees and generated/reference assets. Review each repository separately.

### Continue from here

Visual QA completed on 2026-07-28:

- Desktop checks passed for the homepage, Flights, Visa, Corporate Booking,
  Login, and Privacy.
- The signed-out `account.html` route correctly redirected to Login, so
  authenticated account content was not changed or bypassed for this check.
- 375 px mobile checks passed for the homepage, Flights, Visa, Corporate
  Booking, Login, and Privacy.
- No horizontal overflow was found on the checked pages.
- Desktop scene and mini-object images loaded successfully.
- Large service-page scenes and inline objects are intentionally hidden at the
  small-mobile breakpoint; compact login and legal artwork remains visible.
- No checked illustration covered booking controls, authentication fields,
  mobile actions, or legal content.
- `node --check js/main.js` passed.
- The checked browser console contained no application errors or warnings.
- `git diff --check` reported only the repository's existing LF-to-CRLF
  conversion warnings and no whitespace errors.

The visual QA above predates the later corporate portal commits and the separate
corporate-site dashboard work. It must not be treated as verification of the
new corporate membership/RPC path, the corporate subdomain, or the latest
uncommitted corporate styling.

Next action:

1. Owner reviews the two local-only main-public commits and the one local-only
   corporate-site commit, and decides which release branch/repository is the
   canonical customer-facing corporate portal.
2. Before any corporate launch, apply or confirm both July 28 corporate
   migrations in the live Supabase project, confirm RLS, create one test company
   and Auth user, and test allowed access plus cross-company denial. This
   checkpoint did not mutate or verify live Supabase.
3. Add the missing admin UI for approving a corporate application and linking
   its Auth user; until then `approve_corporate_application` is backend-only.
4. Separately review the main public illustration diff and decide whether
   `output/`, alternate character art, marketing artifacts, and local worktree
   folders are production inputs. Keep required production images under
   `assets/illustrations/`.
5. Only after those owner decisions, publish the intended commits and perform
   desktop/mobile plus authenticated retail and corporate portal QA.

### Major work completed after the previous July 25 snapshot

Public/customer system:

- Customer portal now shows booking document downloads and safe payment
  updates.
- Customer account signup, cache busting, and empty-error handling were
  hardened.
- B2B portal staff/management RPC migrations were added.
- The official canonical domain is `https://www.kridiyatravel.com/`.
- The site links the business-travel subdomain.
- SEO, Supabase auth email templates, and enquiry reliability were improved.
- Homepage search tabs, Corporate entry point, local optimized imagery, and
  compact controls were completed.
- A company-membership model, portal-safe booking/request RPCs, a
  Supabase-backed corporate dashboard, and a staff approval RPC have been added
  to repository code. Live migration/deployment and isolation testing remain
  unverified.
- The corporate public form now targets `corporate@kridiyatravel.com` in local
  commit `0572905`; that commit is not yet on `origin/main`.
- The separate `kridiya-corporate` site now contains a corporate marketing
  front door, application/request forms, login, and an upgraded private portal
  shell. Documents, finance, and statement areas remain partial/placeholders.

Admin/staff system:

- B2B portal management now uses staff RPCs and supports edit controls.
- Customer rows exclude staff accounts and show document/payment visibility
  controls.
- Staff account setup and profile management use secured RPC-backed flows.
- Owner/staff launch checklist, archive structure, storage/RPC security notes,
  and document workflow automation were added.
- Branded document templates support editable shared overrides, service invoice
  presets, PDFs, and multi-option customer quotes.
- Quote/document flows support structured flight/visa and other service
  options, add-ons, itinerary fields, and separate flight quote versus issued
  ticket modes.
- Admin command search/sort, staff preset autocomplete, role-aware dashboards,
  and a simplified dashboard focus were completed.
- A signed-in visual QA pass and shared staff UI consolidation were completed.

### Durable source-of-truth map

- Business/product facts: this file and `PRODUCT.md`.
- Target system design: `docs/KRIDIYA_ADVANCED_SYSTEM_MASTER_PLAN.md`.
- Daily operations, audit, recovery, and owner controls:
  `docs/KRIDIYA_OPERATIONS_LOG_AND_CONTINGENCY_PLAYBOOK.md`.
- Microsoft 365 layout: `docs/kridiya-microsoft-365-folder-guide.md`.
- Customer/staff messaging: `docs/kridiya-email-whatsapp-templates.md`.
- Proposed positioning, CRM attribution, channel strategy, campaigns, content,
  measurement, retention, privacy, and 90-day growth rollout:
  `docs/KRIDIYA_DIGITAL_MARKETING_AND_GROWTH_SYSTEM_PLAN.md`.
- Corporate portal target architecture, access roles, rollout, and manual
  validation gates: `docs/CORPORATE_PORTAL_100_SYSTEM_PLAN.md`.
- Public implementation: `C:\Users\Who\kridiya1`.
- Separate corporate-site implementation:
  `C:\Users\Who\kridiya1\kridiya-corporate-live`.
- Admin implementation: `C:\Users\Who\kridiya-admin`.
- Database/storage changes: `C:\Users\Who\kridiya1\supabase`.
- Never treat chat-only recollection as more current than repository state,
  Supabase state, or these handoff documents.

## Business

- Company: Kridiya Travel and Tourism FZ-LLC
- Trade licence: 5033347, RAK Freezone, Free Zone Limited Liability Company FZ-LLC
- Licence address: FDRK7105, Compass Building, Al Shohada Road, Al Hamra Industrial Zone-FZ, Ras Al Khaimah, United Arab Emirates
- Licence activity: Retail sale of Travel and Entertainment Services E-trafficking
- Licence issue/expiry: issued 28-05-2025, expires 27-05-2027
- Licence manager: Indirani Alagarsamy Alagarsamy
- Currency: AED
- Current active services: Flights and Visa
- Prepare system for: Hotels, Holiday Packages, Umrah, Cruise, Insurance, Transfers, Corporate Bookings
- Corporate booking should be active now
- Rule: payment before booking
- Current payment methods: bank transfer, cash, payment link
- VAT/TRN decision: not VAT registered yet; do not show TRN, do not apply VAT, and use no-VAT wording on invoices/receipts for now.
- Future payment methods: Stripe, Tabby/Tamara, PayPal
- Current suppliers: Akbar Travels, Select My Flight
- Admin currently: one owner/admin, more staff later
- Admin requirement: monitor all staff activity and control what each staff can see/do
- Strategic decision: Supabase is the main live business system; SharePoint/Microsoft 365 is the backup, document, and accounting export layer.
- Strategic decision: `kridiya-admin` is the only staff/admin surface. Public website admin files are legacy and should be removed, hidden, or redirected after live admin confirmation.
- Customer account decision: keep customer accounts light for now; customers can see/respond to enquiries, quotes, and requested uploads. Full customer/corporate portal comes later after admin, finance, backups, and security are stable.
- Payment decision: support all options over time, but first complete manual bank/cash/payment-link proof upload and verification.
- Live admin URL assumption: `https://admin.kridiyatravel.com/`.
- Owner/admin email: `indirani@kridiyatravel.com`.
- Current bank details for payment requests:
  - Account holder: KRIDIYA Travel and Tourism FZ-LLC
  - IBAN: AE540860000009813682904
  - BIC: WIOBAEADXXX
  - Bank address: Etihad Airways Centre 5th Floor, Abu Dhabi, UAE
- Cash payment rule: cash does not always require owner approval before being marked received.
- Staff rollout: owner first; other roles/staff will be added later.
- Supplier rollout: Akbar Travels and Select My Flight only for now; more suppliers will be added later.
- Staff login decision: PIN-only for staff login. Admin creates staff accounts by name/email/role and the system generates the PIN.
- Payment proof decision: staff-only upload for now; customer upload comes later after the customer portal is hardened.
- Supplier invoice decision: store in Supabase private storage and also keep/copy to SharePoint when needed.
- Backup/storage decision: use SharePoint/Microsoft 365 as the preferred backup and document-copy layer.
- Corporate contact channel for now: +971 50 941 3873 and corporate@kridiyatravel.com.
- Public customer login decision: keep visible for customer profile, enquiries, quotes, and requested uploads. Staff still controls bookings/payments.

## Corporate Travel and B2B - Complete Current Memory

Corporate travel is part of the current Kridiya operating system, but its
implemented layers and release state must be distinguished:

- The public corporate enquiry, staff conversion, company/contact management,
  corporate booking, LPO/approval, finance, document, accounting, and backup
  workflow is implemented.
- Repository code now implements a membership-gated corporate portal base:
  company membership, role flags, portal-safe company/booking reads, and new
  request creation. The frontend uses the signed-in Supabase customer session.
- This does not yet establish a live, production-ready company portal. The two
  July 28 migrations are documented as requiring manual application and
  validation, live state was not checked in this review, and cross-company
  isolation has not been recorded as passed.
- Quote approval, released-document downloads, LPO/payment-proof upload,
  monthly statements, and broader finance views remain proposed or partial.
- Two customer-facing implementations currently coexist: the main-site
  `corporate-account.html` and the separate `kridiya-corporate` subdomain
  repository. The owner must confirm the canonical route before release.

### Corporate commercial rules

- Corporate requests can cover flights, visas, hotels, transfers, insurance,
  holiday groups, Umrah, cruises, multiple services, and repeat staff travel.
- Default rule remains payment before booking.
- A company may request bank transfer, payment link, cash, or future credit
  terms, but credit/monthly billing is not assumed.
- Credit, monthly billing, or different payment terms require explicit owner
  approval and must be recorded on the corporate account.
- LPO/PO or written approval must be collected when the company requires it.
- Every corporate request and booking should use one Kridiya reference.
- Supplier confirmation should not proceed until required payment, credit
  approval, LPO, or written approval is clear.
- Corporate contact channel:
  - WhatsApp/phone: `+971 50 941 3873`
  - Email: `corporate@kridiyatravel.com`
- Kridiya is not VAT registered at this checkpoint. Corporate documents must
  not show a Kridiya TRN or add VAT until that business decision changes.

### Public corporate request

Page: `corporate-booking.html`.

The form sends to both Kridiya's enquiry workflow and FormSubmit email. It
captures:

- company name;
- contact person and job title;
- email, phone, and WhatsApp;
- service needed;
- traveller count;
- route or destination with airport autocomplete;
- travel start and end dates;
- preferred payment terms;
- LPO/PO requirement;
- billing email;
- budget or company travel policy;
- traveller details;
- urgency, approval process, document needs, supplier preference, and notes.

The public promise is deliberately enquiry-first:

1. Request is captured with a reference.
2. Kridiya checks suppliers and sends options.
3. The company approves and completes payment/LPO requirements.
4. Kridiya confirms the booking and releases documents.

The form explicitly says no booking will be issued until Kridiya confirms the
quote and receives approval/payment.

### Staff CRM and conversion

Corporate website enquiries appear in Admin > Enquiries with a Corporate
classification and a preview of company, service, route, travellers, LPO, and
billing details.

Conversion requires both:

- `create_bookings`;
- `edit_corporates`.

The `convert_corporate_enquiry_to_booking` RPC:

- requires an authenticated user;
- performs internal permission checks;
- prevents a duplicate active booking for the same `enquiry_id`;
- uses an explicitly selected corporate account or reuses a company with the
  same name;
- otherwise creates a prospect corporate account;
- reuses or creates a linked corporate contact/customer;
- maps the requested service to the correct booking service type;
- creates a linked booking with `booking_kind = corporate`;
- sets the source to `corporate`;
- starts payment as `not_requested`;
- copies traveller, budget/policy, payment-plan, LPO, and original notes into
  staff notes;
- marks the enquiry confirmed;
- writes the `enquiry.converted_to_corporate_booking` audit event;
- returns the existing booking when the enquiry was already converted.

Execution is revoked from `public` and `anon`; it is granted to authenticated
staff and `service_role`, while the function still checks staff permissions.

### Corporate company and contact records

Admin page: `C:\Users\Who\kridiya-admin\corporate.html`.

Main records:

- `corporate_accounts`;
- `corporate_contacts`;
- linked `customers` records with customer type `corporate_contact`;
- linked `bookings`.

Corporate account fields and controls:

- company name;
- status: prospect, active, on hold, or inactive;
- payment terms: payment before booking, credit approved, or monthly billing;
- billing email;
- accounts email;
- phone;
- trade licence number;
- client TRN when applicable;
- address;
- credit allowed;
- monthly billing;
- LPO required;
- internal notes;
- booking count and booking value.

Corporate contact fields and controls:

- full name;
- job title;
- email;
- phone;
- WhatsApp;
- authorized-contact flag;
- accounts-contact flag;
- notes and active state.

The admin corporate control center calculates account readiness and warns about:

- missing billing/accounts email;
- missing authorized contact;
- missing accounts contact;
- missing identified LPO approver;
- missing client TRN when credit/monthly billing is configured;
- on-hold or inactive accounts;
- high-risk combinations of incomplete controls.

It summarizes active accounts, credit/monthly-billing accounts, missing
contacts, LPO-required accounts, booking count, and booking value.

Access:

- `view_corporates` can view corporate accounts;
- `edit_corporates` can create companies/contacts and edit booking corporate
  controls;
- owner/admin retains full access;
- all important changes should remain auditable.

### Corporate booking creation and operation

Staff can create an individual or corporate booking from Admin > Bookings.

For a corporate booking:

- a corporate account is required;
- staff chooses a saved company;
- staff may choose a saved company contact or type a new requester;
- company billing email/phone can prefill the booking;
- an LPO-required account adds an LPO reminder to notes;
- a selected contact must belong to the selected company;
- the backend links or creates the corresponding customer/contact safely;
- booking lists can search and filter Corporate records;
- company and contact names appear on booking rows.

Booking Detail corporate controls show:

- company;
- payment terms;
- whether LPO is required;
- credit allowed;
- monthly billing;
- billing email;
- accounts email;
- linked company contact;
- LPO number;
- approval person.

If an LPO-required corporate booking has no LPO number, Booking Detail shows a
workflow risk and makes "Record LPO or approval" the next action.

Corporate tasks can use the `corporate_approval` task type. Documents can use
corporate types including trade licence, TRN certificate, LPO, approval email,
invoice, payment proof, ticket/PNR, voucher, insurance policy, and other
booking files.

### Corporate finance, documents, accounting, and backups

- Corporate bookings use the same payment-before-booking, proof verification,
  refund, receipt, supplier-cost, supplier-invoice, document, task, and audit
  controls as other bookings.
- Finance search includes company names.
- Accounting groups corporate bookings by company and reports sales and gross
  profit.
- Accounting next-action logic flags corporate LPO/payment approval.
- Corporate client data is included in the monthly backup pack.
- Corporate account exports contain company billing settings and contact
  summaries.
- SharePoint/Microsoft 365 remains the document-copy, accounting-export, and
  backup layer. Corporate client folders must not replace Supabase as the live
  operational source of truth.

### Corporate portal - implemented repository scope

Page: `corporate-account.html`.

- Requires a signed-in customer account.
- Uses the public/customer Supabase session, not the staff PIN session.
- Calls `get_my_corporate_portal`, `list_my_corporate_bookings`, and
  `create_my_corporate_request`.
- Shows only companies linked through `corporate_portal_members`.
- Supports portal roles/flags for request creation, finance visibility, quote
  approval eligibility, and document visibility.
- Lists portal-safe company booking/request summaries and permits a linked
  member to create a new corporate request.
- It does not expose supplier cost, profit, staff notes, unrelated customers,
  or another company's data.
- The access migration adds `corporate_portal_members`, RLS policies, staff
  member management, membership checks, portal summary/list/detail RPCs, and
  request creation. Anonymous/public execution is revoked and authenticated
  execution is granted; the functions still rely on membership/permission
  checks.
- The approval migration adds `approve_corporate_application`, which can
  convert an application enquiry, create/reuse the corporate account/contact
  and booking, and optionally activate a linked Auth user. No admin UI invokes
  this RPC yet.
- Preferred future login remains email OTP/magic link or proper individual
  password authentication; never use a shared company password.
- Repository implementation is complete only for the secure base/request
  slice. Live migration, Auth linking, RLS behavior, and cross-company denial
  are pending verification.

### Corporate portal - remaining work

Before expanding or launching the portal:

1. Confirm/apply both July 28 migrations and verify
   `corporate_portal_members` RLS in the live project.
2. Test one approved user and a second company, proving allowed access and
   cross-company denial for every portal RPC.
3. Add an admin UI for application approval, Auth-user linking, portal roles,
   status, and permission flags.
4. Decide whether the main-site portal or the separate corporate subdomain is
   canonical, then remove or redirect duplicate/stale entry points.
5. Implement quote approval/rejection with approver and timestamp.
6. Expose only approved documents, invoices/receipts, payment due, and monthly
   statements; use private storage and signed URLs.
7. Add controlled LPO, payment-proof, and traveller-document upload.
8. Never expose supplier cost, gross profit, internal notes, other companies,
   staff/security information, or unrestricted storage paths.

### Supplier B2B portals

Admin page: `C:\Users\Who\kridiya-admin\portals.html`.

- Current suppliers are Akbar Travels and Select My Flight.
- Staff can store portal name, website URL, service scope, username/agent-code
  hint, password-location note, status, and owner notes.
- Passwords must remain in a password manager; they are not stored in the
  portal directory.
- `manage_portals` controls create, edit, activate/inactivate, and delete
  actions.
- RPCs include `list_b2b_portals`, `create_b2b_portal`,
  `update_b2b_portal`, `set_b2b_portal_status`, and `delete_b2b_portal`.
- Portal management RPC execution is revoked from `public` and `anon`, granted
  to authenticated/service roles, and internally protected by staff/permission
  checks.

## Repositories

Public website:

- Local path: `C:\Users\Who\kridiya1`
- GitHub: `Kridiyatravels/kridiyatravel`

Admin/staff site:

- Local path: `C:\Users\Who\kridiya-admin`
- GitHub: `Kridiyatravels/kridiya-admin`

Corporate public/portal site:

- Local path: `C:\Users\Who\kridiya1\kridiya-corporate-live`
- GitHub: `Kridiyatravels/kridiya-corporate`
- This is a separate nested Git repository, not tracked by the main public
  repository.

Supabase:

- Project ref/id: `jmvqqpughlzeqrcyavwz`

Important local warning:

- In `kridiya1`, these files were pre-existing/unrelated and should not be touched unless explicitly requested:
  - `js/search.js`
  - `kridiya-logo-hd-white.png`
  - `kridiya-logo-hd.png`
  - `kridiya-logo.png`

## Current Public Website System

The public website lives in `kridiya1`.

Completed:

- Customer enquiry forms save into Supabase `enquiries`
- Forms also email Kridiya using FormSubmit
- Enquiries get website references and redirect to `thanks.html`
- Corporate booking request page exists: `corporate-booking.html`
- Corporate page captures:
  - company name
  - contact person
  - job title
  - email
  - phone
  - WhatsApp
  - service needed
  - traveller count
  - route/destination
  - start/end date
  - payment plan
  - LPO/PO requirement
  - billing email
  - budget/policy
  - traveller details
  - notes/approval process
- Corporate page is linked in public navigation and footer

Recent public commits:

- `6984032` - Add corporate portal access plan and migration
- `8fca3e2` - Connect corporate portal to Supabase
- `0572905` - Use corporate mailbox for corporate requests (local-only)
- `cf98abb` - Add corporate application approval RPC (local-only)

Separate corporate-site state:

- `76d72d3` - Create private corporate portal shell (on `origin/main`)
- `22dae81` - Upgrade corporate portal dashboard (local-only)
- The local corporate site also has unfinished service-page/CSS polish.
- Portal documents, finance, and statement panels are not yet complete live
  features even where the UI presents them as roadmap/workspace areas.

## Current Admin/Staff System

The admin site lives in `kridiya-admin`.

Current pages:

- Dashboard
- Enquiries
- Bookings
- Booking Detail
- Payments
- Documents
- Portals
- Staff
- Activity
- Backups
- Accounting
- Templates
- Corporate Accounts

Current features:

- Staff PIN login
- Admin can monitor activity
- Admin permissions exist
- Enquiries list and filters
- WhatsApp/email reply links
- Enquiry notes
- Enquiry requests
- Quote records
- Booking creation
- Booking detail controls
- Booking status, payment status, document status
- Customer payment records
- Supplier payment records
- Payment request generation
- Receipt generation
- Booking document upload/tracking
- Corporate account management
- Corporate contact management
- B2B portal tracking
- Backup exports
- Accounting reports
- Template library for email/WhatsApp
- Corporate enquiry conversion button

Recent admin commit:

- `d58d476` - Add corporate enquiry conversion action

## Supabase Backend

Current backend includes:

- `enquiries`
- `enquiry_notes`
- `enquiry_requests`
- `quotes`
- `staff_profiles`
- `staff_roles`
- `staff_permissions`
- `audit_events`
- `bookings`
- booking payments
- booking payment requests
- booking receipts
- booking document storage
- booking tasks/reminders
- `corporate_accounts`
- `corporate_contacts`
- B2B portals
- private storage buckets for booking documents
- prepared local migration for payment proof storage/backend:
  - `supabase/migrations/20260725_payment_proofs_and_bank_defaults.sql`
- applied live migration for supplier invoice storage/backend:
  - `supabase/migrations/20260725_supplier_invoice_storage.sql`
- prepared local corporate portal migrations whose live application is not
  confirmed in this checkpoint:
  - `supabase/migrations/20260728_corporate_portal_access_layer.sql`
  - `supabase/migrations/20260728_corporate_application_approval_rpc.sql`

Important RPCs/functions include:

- `staff-pin-login` Edge Function
- `create-staff-account` Edge Function
- `reset-staff-pin` Edge Function
- `list_operations_bookings`
- `create_operations_booking`
- `get_operations_booking_detail`
- `update_operations_booking_status`
- `list_corporate_accounts`
- `create_corporate_account`
- `create_corporate_contact`
- `convert_corporate_enquiry_to_booking`
- `manage_corporate_portal_member`
- `get_my_corporate_portal`
- `list_my_corporate_bookings`
- `get_my_corporate_booking_detail`
- `create_my_corporate_request`
- `approve_corporate_application`

Corporate portal backend status:

- The July 28 SQL is implemented and committed locally.
- Execute is revoked from `public` and `anon` and granted to
  `authenticated`/`service_role`; staff-only functions also perform internal
  staff permission checks, while customer-facing functions enforce linked
  corporate membership.
- The migration plan explicitly requires manual application, RLS confirmation,
  Auth-user linking, and cross-company tests. None is recorded as completed in
  this review.
- `approve_corporate_application` is backend-only until the admin approval and
  Auth-linking UI is added.

Corporate conversion RPC:

- Name: `convert_corporate_enquiry_to_booking`
- Purpose:
  - takes a website corporate enquiry
  - creates or reuses corporate company
  - creates or reuses corporate contact
  - creates linked corporate booking
  - marks enquiry as confirmed
  - logs activity
- Security:
  - anon execute is revoked
  - authenticated execute is granted
  - function still checks staff permissions internally
  - requires booking creation and corporate edit permission

Verified:

- Function exists in Supabase
- anon cannot execute
- authenticated can execute
- rollback dry-run succeeded

Note:

- Supabase migration history recorded:
  - `convert_corporate_enquiry`
  - `fix_convert_corporate_enquiry_source`
- Local migration file contains the corrected final function:
  - `supabase/migrations/20260724_convert_corporate_enquiry.sql`

## Microsoft 365 / SharePoint

SharePoint/OneDrive root folder:

- `Kridiya Business`

Created folders:

- `Bookings`
- `Payments`
- `Accounting`
- `Corporate Clients`
- `Supplier Portals`
- `Company Documents`
- `Monthly Backups`
- `Templates & SOPs`

Created subfolders:

- `Accounting/Monthly Reports`
- `Accounting/Invoices & Receipts`
- `Accounting/Supplier Invoices`
- `Monthly Backups/2026-07`
- `Company Documents/License & Registration`
- `Company Documents/Bank & Payment Setup`
- `Templates & SOPs/Email Templates`
- `Templates & SOPs/Staff SOPs`

Uploaded docs:

- `Kridiya Microsoft 365 Folder Guide.md`
- `Kridiya Email and WhatsApp Templates.md`

Local docs:

- `docs/kridiya-microsoft-365-folder-guide.md`
- `docs/kridiya-email-whatsapp-templates.md`
- `docs/KRIDIYA_ADVANCED_SYSTEM_MASTER_PLAN.md`
- `docs/KRIDIYA_OPERATIONS_LOG_AND_CONTINGENCY_PLAYBOOK.md`

## Advanced System Direction

Created on 2026-07-25:

- `docs/KRIDIYA_ADVANCED_SYSTEM_MASTER_PLAN.md`
  - Defines the target connected system across public site, admin, Supabase, accounting, sales, marketing, staff, backups, IT/security, payments, suppliers, and future portals.
- `docs/KRIDIYA_OPERATIONS_LOG_AND_CONTINGENCY_PLAYBOOK.md`
  - Defines required activity logs, daily/weekly/monthly owner checklists, normal workflows, contingency handling, and owner questions before the next implementation push.

Core target workflow:

1. Customer/company enquiry
2. Staff review
3. Quote
4. Approval
5. Payment request
6. Payment proof/verification
7. Booking
8. Supplier cost/invoice
9. Documents
10. Receipt/invoice
11. Accounting
12. Backup
13. Activity log

## Correct Business Workflow

1. Customer/company sends enquiry from website, email, or WhatsApp.
2. Enquiry appears in Admin > Enquiries.
3. Staff checks supplier portal such as Akbar Travels or Select My Flight.
4. Staff sends quote.
5. Customer/company approves quote.
6. Payment is requested before booking.
7. Payment is received by bank transfer, cash, or payment link.
8. Staff creates/converts booking.
9. Supplier cost is recorded.
10. Documents/tickets/visa files are uploaded.
11. Receipt is generated.
12. Accounting tracks sale, cost, profit, received, pending.
13. Backup exports are saved monthly.
14. Activity page monitors staff work.

## Historical Work Plan (July 25 Baseline)

This section preserves the original implementation sequence for history. Many
items below have since been implemented. Use the 2026-07-29 Resume Checkpoint,
the Corporate Travel and B2B section, repository state, and recent commit logs
to determine current work; do not assume every item below is still pending.

### Step 1 - Test Corporate Enquiry Flow

Goal: confirm website to admin conversion works.

Tasks:

- Open `corporate-booking.html`
- Submit a test corporate enquiry
- Confirm it appears in Admin > Enquiries
- Expand the enquiry
- Confirm corporate chips show company/service/route/travellers/LPO/billing
- Click Convert
- Confirm corporate account/contact/booking are created
- Confirm booking opens in `booking-detail.html`
- Confirm booking has:
  - `booking_kind = corporate`
  - `enquiry_id` linked
  - company/contact linked
  - `source = corporate`
  - `payment_status = not_requested`
  - `document_status = not_started`

### Step 2 - Improve Enquiry Conversion UI

Goal: make converted enquiries clear.

Tasks:

- Show Converted badge if a booking already exists for `enquiry_id`
- Add Open Booking button for converted enquiries
- Prevent duplicate conversion confusion
- If RPC returns `existing_booking = true`, show clear message and open existing booking
- Add activity log wording if needed

### Step 3 - Staff Permission Management UI

Goal: admin can control staff properly.

Permissions:

- `view_enquiries`
- `edit_enquiries`
- `view_customers`
- `edit_customers`
- `view_corporates`
- `edit_corporates`
- `create_bookings`
- `edit_bookings`
- `view_payments`
- `edit_payments`
- `view_supplier_cost`
- `view_profit`
- `generate_documents`
- `manage_portals`
- `manage_templates`
- `view_reports`
- `export_reports`
- `approve_refunds`
- `approve_discounts`
- `manage_staff`
- `view_activity`
- `manage_settings`

Tasks:

- Add permission switches in Staff page
- Owner/admin keep full access
- Normal staff get only selected access
- Add secure RPC to update permissions
- Log every permission change
- Test restricted staff access

### Step 4 - Payment Proof Upload

Goal: attach customer payment proof to bookings.

Tasks:

- Add private storage bucket if needed: `booking-payment-proofs`
- Store:
  - booking id
  - payment id if available
  - file path
  - file name
  - uploaded by
  - uploaded at
  - notes
- Add upload proof button under Customer Payments in booking detail
- Allow PDF/image upload
- Create signed URL to view
- Show proof status in Payments page
- Activity log: `payment.proof_uploaded`

### Step 5 - Supplier Invoice Upload

Goal: attach supplier invoices/cost documents to bookings.

Tasks:

- Add private bucket: `supplier-invoices`
- Add supplier document table
- Store:
  - booking id
  - supplier name
  - supplier reference
  - file path
  - file name
  - amount
  - currency
  - uploaded by
  - uploaded at
  - notes
- Add upload/view invoice in booking detail supplier section
- Include in backups
- Activity log: `supplier.invoice_uploaded`

### Step 6 - Excel / SharePoint Accounting

Goal: Supabase is main system, Excel/SharePoint is accounting export/backup.

Workbook sheets:

- Summary
- Sales
- Customer Payments
- Supplier Costs
- Profit
- Pending Collections
- Corporate Accounts
- Supplier Payables
- Refunds/Cancellations
- Audit Notes

Tasks:

- Admin Accounting page exports this workbook
- Save reports to `Kridiya Business/Accounting/Monthly Reports`
- Monthly backup goes to `Kridiya Business/Monthly Backups/YYYY-MM`
- If SharePoint direct upload is available, use it
- If not, create downloadable Excel with instructions

### Step 7 - Better Backups

Backup exports should include:

- enquiries
- bookings
- booking payments
- supplier payments
- corporate accounts
- corporate contacts
- documents
- portals
- staff list
- staff permissions
- audit events

Tasks:

- Add Monthly Backup Pack button
- Export as ZIP or XLSX/CSV group
- Include date/time in file names
- Show last backup time if possible
- Never expose secrets

### Step 8 - Document Templates

Create/upgrade:

- Payment request
- Receipt
- Invoice
- Booking confirmation
- Corporate booking confirmation
- Corporate statement
- Supplier payment note
- Refund/cancellation note
- Visa document checklist
- Flight ticket handover note

Each should include:

- Kridiya Travel and Tourism FZ-LLC
- booking reference
- customer/company details
- service details
- amount/payment status
- terms/notes
- generated date
- staff name if available

### Step 9 - Corporate Client Portal

Build later after admin side is stable.

Features:

- Corporate login
- Company dashboard
- View own bookings only
- View payment due
- Upload payment proof
- Upload traveller documents
- Download invoice/receipt
- View booking status
- Request new booking
- Message/notes thread if possible

Security:

- Corporate users see only their own company data
- Never show supplier cost/profit
- Strict RLS
- Admin/staff still manage everything

### Step 10 - WhatsApp / Email Workflow

Templates/actions:

- enquiry received
- quote ready
- payment request
- payment received
- booking confirmed
- document request
- corporate LPO request
- supplier availability request
- refund update

Tasks:

- Add copy buttons
- Add prefilled WhatsApp links
- Add prefilled email links
- Later connect Outlook Email if available
- Later connect WhatsApp Business API only when ready

### Step 11 - Supplier Portal Management

Current suppliers:

- Akbar Travels
- Select My Flight

Tasks:

- Store supplier name
- service type
- login URL
- account/reference notes
- payment method
- support contact
- active/inactive
- Do not store passwords unless a secure vault is built
- Add supplier used field to booking
- Add supplier reference to booking
- Add supplier payable report

### Step 12 - Security Audit

Check:

- no service role key in frontend
- all staff/admin RPCs revoke anon/public execute
- only authenticated staff can call staff RPCs
- permission checks inside every `SECURITY DEFINER` function
- storage buckets private
- signed URLs only for staff
- RLS enabled on public tables
- customers/corporate clients cannot see other users data
- staff without permission cannot see supplier cost/profit
- activity logs record important changes
- staff PIN uniqueness enforced
- old duplicate PINs checked/reset if needed
- admin can remove staff access

### Step 13 - Production QA

Test:

- individual flight enquiry
- visa enquiry
- corporate enquiry
- convert corporate enquiry to booking
- manual booking creation
- corporate booking creation
- booking status update
- customer payment record
- supplier payment record
- payment request generation
- receipt generation
- document upload
- supplier invoice upload
- accounting export
- backup export
- staff activity monitoring
- permission restriction test
- SharePoint folder/document check
- mobile view check
- admin logout/login PIN test

## Deployment Rules

Always:

- Check git status first
- Do not revert unrelated user changes
- Commit only intended files
- Push to correct repo
- Verify after push
- Tell user:
  - what changed
  - what was tested
  - commit id
  - what is next

Public repo:

- path: `C:\Users\Who\kridiya1`
- push to `main`

Admin repo:

- path: `C:\Users\Who\kridiya-admin`
- push to `main`

## Recorded Owner Decisions and Completed Upgrades (July 25-27)

Current owner decisions as of 2026-07-25:

- Admin domain is likely `admin.kridiyatravel.com`.
- Owner/admin email is `indirani@kridiyatravel.com`.
- Staff login is PIN-only.
- Admin creates staff with name/email/role and sees the generated PIN at creation/reset.
- Existing staff PINs should not be stored visibly; if forgotten, reset and issue a new PIN.
- Supplier invoices are uploaded to private Supabase storage now.
- Staff/admin can record a SharePoint invoice link now; automatic SharePoint upload is a later phase.
- Chosen SharePoint structure is `Kridiya Travel/Operations/Bookings/YYYY/MM/BOOKING-REFERENCE/...` for booking documents and `Kridiya Travel/Finance/YYYY/MM` for monthly finance exports.
- Refunds must be tracked as `refund_pending` before completion, approved by owner/admin or finance with `approve_refunds`, and shown in accounting as refund pending, refunded, and net collected.
- Refund backend is now implemented with `request_payment_refund`, `approve_payment_refund`, and `complete_payment_refund` RPCs, with audit events for each step.
- Admin payments page is upgraded into Finance Control with filters, search, refund queue, approve/complete refund actions, proof/receipt chips, booking links, and net collection totals.
- Admin dashboard is upgraded into a command center with system health, open sales/cost/profit, 30-day net collection, confirmed-before-payment risk, refund queue, overdue/today tasks, document pending, and direct action links.
- Booking detail is upgraded with a command workflow panel showing workflow completion, next required action, customer/traveller/payment/supplier/invoice/document/task controls, and risk flags without adding unnecessary extra modules.
- Staff & Permissions is upgraded with top-level staff stats, grouped permission sections, high-access risk labels, PIN reset guidance, and clearer 30-day monitoring metrics.
- Accounting and Backups are upgraded with owner monthly review, finance health, export checklist, backup readiness, SharePoint finance folder guidance, and cleaner handover flow.
- Admin enquiries are being upgraded into a Sales/CRM follow-up control center with attention filters, search, conversion visibility, needs-quote queue, follow-up queue, corporate queue, stale enquiry detection, and next-action guidance.
- Admin enquiry rows are being upgraded with marketing follow-up controls: source inference, lead age, last-touch age, won/active/stale stage labels, copy-ready WhatsApp/email follow-up messages, and quick marketing outcome notes.
- Staff & Activity are being upgraded with IT/security review controls: owner security findings, sensitive permission checks, broad-access checks, stale active staff detection, monthly owner checklist, audit security summary, audit search, and security-only filtering.
- Booking detail supplier payments are being upgraded into supplier/vendor control: payable/paid/balance visibility, margin exposure, supplier reference check, invoice attachment check, SharePoint backup check, dispute flagging, and next supplier action guidance.
- Admin Customers is being upgraded into customer/corporate portal control: portal readiness, guest invite queue, booked guest detection, profile cleanup detection, customer-card portal state, and copy-ready portal invite messages without touching the public login flow yet.
- Corporate Accounts is being upgraded with deeper account control: health scoring, billing email checks, authorized/accounts contact checks, LPO approver readiness, credit/monthly billing risk, inactive/on-hold warnings, and corporate value/risk summary.
- Documents and Templates are being upgraded with control panels: business/document readiness checks, linked-enquiry audit readiness, document type coverage, template category coverage, channel mix, and next document/message guidance.
- Dashboard is being upgraded with Operations QA: module-by-module readiness, live risk/warning states, direct module links, and the full enquiry-to-accounting workflow path for final launch testing.
- Dashboard is also being upgraded with Launch Readiness: owner go-live percentage, live checklist cards for sales, bookings, finance/refunds, suppliers, documents/templates, and audit/backup, with direct links to clear each warning.
- Dashboard now includes a browser-saved Workflow Test checklist for launch QA: enquiry, quote, booking, customer payment/refund edge case, supplier cost, documents, accounting, and backup.
- Workflow Test can copy a timestamped QA report with checked/unchecked launch steps for owner handover, WhatsApp/email sharing, or internal audit notes.
- Workflow Test now stores launch-test notes in the browser and includes them in the copied QA report, so blockers and owner decisions can travel with the checklist.
- Admin now includes an admin-only SOP & Handover page covering daily opening, enquiry-to-quote, booking control, finance/refunds/suppliers, documents/templates, corporate handling, staff/security, backups, and emergency operation, with a copyable SOP for staff training and owner handover.
- Public customer account now has a Portal Overview card with live counts for bookings/enquiries, active quotes, open requests, and a next-action strip that points customers to requests, quotes, new enquiry, or WhatsApp support.
- Public customer account booking/enquiry list now renders as structured portal cards with item type badges, reference, status, details, amount, traveller count, and request/quote alert chips.
- Customer portal now shows safe booking payment/document status fields where available, and the first login-gated Corporate Portal surface exists at `corporate-account.html` with company access status, corporate operating flow, required company checklist, and support/request links. Full company-wide booking data still requires strict corporate RLS/data linking confirmation before exposing more.
- Historical-status correction as of 2026-07-29: repository code now includes a
  corporate membership/RPC access layer and live-data dashboard, but live
  migration state and cross-company isolation remain unverified; do not call
  the portal production-ready.
- Future customer/corporate portal login should use email OTP or magic-link.
- Corporate public contact for now is `+971 50 941 3873` and `corporate@kridiyatravel.com`.
- Customer login should remain visible on the public site.

### Historical direction at that time

Upgrade the admin/staff portal module by module into a precise professional operating system: dashboard command center, booking workflow, payments/refunds, accounting, backups, staff monitoring, documents, supplier controls, sales/CRM, marketing follow-up, and IT/security review.
