# Kridiya Current System Memory

Last updated: 2026-07-25

Use this file as the handoff memory for a new Codex or Claude chat.

## Business

- Company: Kridiya Travel and Tourism FZ-LLC
- Currency: AED
- Current active services: Flights and Visa
- Prepare system for: Hotels, Holiday Packages, Umrah, Cruise, Insurance, Transfers, Corporate Bookings
- Corporate booking should be active now
- Rule: payment before booking
- Current payment methods: bank transfer, cash, payment link
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
- Corporate contact channel for now: +971 50 941 3873 and enquiry@kridiyatravel.com.
- Public customer login decision: keep visible for customer profile, enquiries, quotes, and requested uploads. Staff still controls bookings/payments.

## Repositories

Public website:

- Local path: `C:\Users\Who\kridiya1`
- GitHub: `Kridiyatravels/kridiyatravel`

Admin/staff site:

- Local path: `C:\Users\Who\kridiya-admin`
- GitHub: `Kridiyatravels/kridiya-admin`

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

- `5c5eea9` - Add corporate booking request page
- `a269f25` - Add corporate enquiry conversion RPC

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

## Pending Work Plan

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

## Next Best Action

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
- Future customer/corporate portal login should use email OTP or magic-link.
- Corporate public contact for now is `+971 50 941 3873` and `enquiry@kridiyatravel.com`.
- Customer login should remain visible on the public site.

## Next Best Action

Upgrade the admin/staff portal module by module into a precise professional operating system: dashboard command center, booking workflow, payments/refunds, accounting, backups, staff monitoring, documents, supplier controls, sales/CRM, marketing follow-up, and IT/security review.
