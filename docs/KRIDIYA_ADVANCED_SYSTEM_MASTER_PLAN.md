# Kridiya Advanced System Master Plan

Last updated: 2026-07-25

## 1. Executive Direction

Kridiya should become one connected business operating system, not a collection of separate pages.

The central rule:

Customer enquiry -> staff action -> quote -> approval -> payment -> booking -> supplier cost -> documents -> receipt/invoice -> accounting -> backup -> activity log.

Every action should connect through shared IDs:

- enquiry_id
- customer_id
- booking_id
- corporate_account_id
- corporate_contact_id
- payment_id
- document_id
- staff_user_id

## 2. Recommended Architecture

### Core System

Use Supabase as the main database and workflow engine.

Supabase should own:

- Public enquiries
- Customers
- Corporate accounts
- Bookings
- Payments
- Supplier costs
- Documents metadata
- Staff profiles
- Staff permissions
- Activity logs
- Accounting source data
- Backup source data

### Admin System

Use only the separate admin site:

- Repository: `C:\Users\Who\kridiya-admin`
- Purpose: staff/admin operations, finance, documents, accounting, corporate accounts, staff control, backups

The old public website `admin.html` should be treated as legacy and removed or hidden after the admin site is fully confirmed.

### Public Website

Use the public website only for:

- Service pages
- Enquiry capture
- Customer login/account area
- WhatsApp/call/email conversion
- Corporate booking request form

Repository:

- `C:\Users\Who\kridiya1`

### Microsoft 365 / SharePoint

Use SharePoint as the document and backup layer, not the main live database.

SharePoint should store:

- Monthly exports
- Accounting reports
- Supplier invoices
- Payment proofs if needed
- Company documents
- SOPs and templates
- Manual backup packs

Supplier invoices should be uploaded first to the private Supabase `supplier-invoices` bucket so the admin booking page has an immediate operational copy. A SharePoint link can be recorded against the supplier payment now. Later, automation should copy the invoice to SharePoint and write the SharePoint URL back into Supabase.

Chosen SharePoint structure:

- `Kridiya Travel/Operations/Bookings/YYYY/MM/BOOKING-REFERENCE/Supplier Invoices`
- `Kridiya Travel/Operations/Bookings/YYYY/MM/BOOKING-REFERENCE/Customer Documents`
- `Kridiya Travel/Finance/YYYY/MM`
- `Kridiya Travel/SOPs`
- `Kridiya Travel/Templates`

## 3. Customer Account Recommendation

There are two possible customer-account models.

### Option A - Light Customer Account

Best for now.

Customers can:

- Register/login
- See their enquiries
- See quotes
- Accept/decline quotes
- Upload requested files
- View booking status later

Staff still controls all real booking, payment, supplier, and document actions.

This is safer and easier because Kridiya is still building operations.

### Option B - Full Customer Portal

Better later.

Customers can:

- View bookings
- Upload payment proof
- Upload passport/documents
- Download invoices/receipts
- Track visa/ticket/hotel status
- Request new bookings

This needs stronger RLS, storage rules, signed URLs, and production QA.

### Recommendation

Use Option A now. Build Option B only after admin operations, accounting, permissions, and backups are stable.

### Login Decision

Staff/admin login should stay PIN-only for the internal admin system. Admin creates a staff account with name, email, and role; the system generates the PIN and shows it during account creation or reset. For security, the system should not store a permanently visible plain-text PIN. If staff forgets the PIN, admin resets it and gives the new PIN.

Customer and corporate portal login should use email OTP or magic-link later. This is the best choice because it avoids shared passwords, supports multiple company contacts, and can be connected to booking/payment records safely.

### Owner Decision

The first owner/admin account is Indirani. More owners, managers, finance staff, sales staff, and operations staff can be added later from the admin site.

## 4. Payment Strategy

Support all payment options, but in phases.

### Phase 1 - Manual Payment Control

Support:

- Bank transfer
- Cash
- Payment link
- Manual proof upload
- Staff verification
- Receipt generation

This should be finished first because it matches Kridiya's current business model.

Default bank details are configured for Wio:

- Account holder: KRIDIYA Travel and Tourism FZ-LLC
- IBAN: AE540860000009813682904
- BIC: WIOBAEADXXX
- Bank address: Etihad Airways Centre 5th Floor, Abu Dhabi, UAE

### Phase 2 - Payment Gateway Links

Support:

- Stripe payment links
- PayPal links
- Tabby/Tamara later
- Payment link reference tracking

No raw card data should ever be stored.

### Phase 3 - Automated Gateway Integration

Later, when ready:

- Stripe Checkout
- Payment webhooks
- Automatic paid status updates
- Provider transaction IDs
- Refund records

## 5. Master Modules

### Public Website

Purpose:

- Convert visitors into enquiries.

Must include:

- Flights
- Visa
- Hotels
- Holidays
- Umrah
- Cruise
- Corporate booking
- Contact
- WhatsApp everywhere
- Honest enquiry flow
- No fake live booking claims

### Enquiry Management

Purpose:

- Staff receives and manages every customer/company request.

Must include:

- Enquiry list
- Filters
- Status changes
- Notes
- Customer requests
- Quote options
- WhatsApp/email replies
- Corporate chips
- Convert corporate enquiry to booking
- Converted badge
- Open booking button

### Booking Operations

Purpose:

- Control the real booking lifecycle.

Must include:

- Individual booking
- Corporate booking
- Booking detail page
- Passenger/traveller records
- Supplier name
- Supplier reference
- Booking status
- Payment status
- Document status
- Tasks and reminders
- Internal notes
- Activity timeline

### Corporate Accounts

Purpose:

- Manage company clients properly.

Must include:

- Company profile
- Billing email
- Accounts email
- Phone
- Payment terms
- LPO required
- Credit allowed flag
- Monthly billing flag
- Contacts
- Authorized contacts
- Accounts contacts
- Corporate booking history
- Corporate sales and pending balances

### Payments

Purpose:

- Enforce payment before booking.

Must include:

- Customer payment records
- Supplier payment records
- Payment request document
- Receipt document
- Payment proof upload
- Proof status
- View signed proof URL
- Payment method
- Reference/payment link
- Refund request
- Refund approval
- Refund completion
- Refund note/document

### Supplier Management

Purpose:

- Track supplier portals and costs.

Must include:

- Supplier name
- Service type
- Portal URL
- Contact details
- Payment method
- Supplier reference
- Supplier invoice upload
- Supplier invoice private storage in Supabase
- Supplier invoice SharePoint copy/reference when needed
- Supplier payable report
- Active/inactive flag

Do not store supplier passwords unless a secure vault is built.

### Documents

Purpose:

- Generate and track business documents.

Must include:

- Payment request
- Receipt
- Invoice
- Flight ticket handover
- Hotel voucher
- Visa confirmation
- Corporate booking confirmation
- Corporate statement
- Supplier payment note
- Refund/cancellation note
- Visa checklist

Documents should be generated from booking/customer/company data whenever possible.

### Accounting

Purpose:

- Show sales, cost, profit, received money, and pending money.

Must include:

- Sales report
- Customer payments
- Supplier costs
- Profit report
- Pending collections
- Corporate balances
- Supplier payables
- Refund/cancellation report
- Refund pending total
- Refunded total
- Net collected after refunds
- Monthly export
- CSV/XLSX backup

Supabase should be the source of truth. Excel/SharePoint should be the export and audit copy.

Refund rule:

- Every refund starts as `refund_pending`.
- Owner/admin or finance with `approve_refunds` approves before money is returned.
- Final refunded records must include amount, method, reason, supplier rule, staff actor, and proof/reference.
- Accounting reports must show refund pending, refunded, and net collected.

### Marketing

Purpose:

- Turn enquiries and customers into repeat business.

Must include:

- Customer segments
- Service interest tags
- Last enquiry date
- Last booking date
- Quote accepted/declined tracking
- Campaign export list
- WhatsApp/email templates
- Repeat customer reminders
- Corporate follow-up reminders
- Seasonal offer templates

Future:

- Newsletter automation
- Email campaign tool
- WhatsApp Business API
- Lead scoring

### Sales Pipeline

Purpose:

- Make every enquiry trackable until it wins or closes.

Recommended sales stages:

- New enquiry
- Contacted
- Supplier checking
- Quote sent
- Follow-up needed
- Customer approved
- Payment requested
- Payment received
- Booking confirmed
- Lost/closed

Important reports:

- Enquiries today
- Quotes sent
- Follow-ups overdue
- Conversion rate
- Lost reasons
- Sales by service
- Sales by staff

### Staff and Permissions

Purpose:

- Owner controls who can see and do what.

Permissions should include:

- view_enquiries
- edit_enquiries
- view_customers
- edit_customers
- view_corporates
- edit_corporates
- create_bookings
- edit_bookings
- view_payments
- edit_payments
- view_supplier_cost
- view_profit
- generate_documents
- manage_portals
- manage_templates
- view_reports
- export_reports
- approve_refunds
- approve_discounts
- manage_staff
- view_activity
- manage_settings

Owner/admin should always have full access.

### Activity and Monitoring

Purpose:

- Owner can see what staff are doing.

Must track:

- Login
- Enquiry status changes
- Notes added
- Requests sent
- Quotes sent
- Quote accepted/declined
- Booking created
- Booking status updated
- Payment recorded
- Payment proof uploaded
- Supplier payment recorded
- Document generated/uploaded
- Staff permission changed
- Backup exported

### Backups

Purpose:

- Protect the business.

Backup pack should include:

- Enquiries
- Customers
- Bookings
- Customer payments
- Supplier payments
- Corporate accounts
- Corporate contacts
- Documents
- Supplier portals
- Staff list
- Staff permissions
- Activity events

Formats:

- CSV first
- XLSX later
- ZIP pack later
- SharePoint monthly upload later

### IT and Security

Purpose:

- Keep customer, passport, payment, and staff data safe.

Must enforce:

- No service role key in frontend
- Supabase RLS on exposed tables
- Private storage buckets
- Signed URLs only
- Staff-only RPCs
- No public execute on privileged RPCs
- Permissions checked inside RPCs
- Staff PIN security
- Activity logging
- Customer isolation
- Corporate isolation later
- No raw card data ever
- Monthly security review

## 6. Current Priority Roadmap

### Priority 1 - Confirm Corporate Flow

Goal:

- Prove public corporate enquiry -> admin conversion -> booking detail works live.

Tasks:

- Submit a test corporate enquiry
- Confirm it appears in admin enquiries
- Confirm corporate chips display
- Convert to booking
- Confirm booking opens
- Confirm company/contact/booking links
- Confirm booking_kind is corporate
- Confirm source is corporate
- Confirm payment_status is not_requested
- Confirm document_status is not_started

### Priority 2 - Retire Legacy Public Admin

Goal:

- Avoid confusion between public admin page and real admin site.

Tasks:

- Confirm `kridiya-admin` is live and fully usable
- Remove old public admin nav exposure if any
- Replace public `admin.html` with redirect or staff-site link
- Keep public site focused on customers

### Priority 3 - Finish Payment Proof Upload

Goal:

- Staff can upload/view customer payment proof securely.

Tasks:

- Create/verify private `booking-payment-proofs` bucket
- Add/verify payment proof fields on payments table
- Add/verify `attach_payment_proof` RPC
- Add signed URL view
- Log `payment.proof_uploaded`
- Show proof status in Payments
- Test PDF/image upload

### Priority 4 - Supplier Invoice Upload

Goal:

- Supplier invoices and payable documents are attached to bookings.

Tasks:

- Create private `supplier-invoices` bucket
- Use supplier payment records as the invoice attachment point
- Add upload/view in booking detail
- Link to supplier payment records
- Include in backups
- Log `supplier.invoice_uploaded`

### Priority 5 - Accounting Upgrade

Goal:

- Finance dashboard becomes owner-grade.

Tasks:

- Add monthly report view
- Add pending collections
- Add supplier payables
- Add corporate balances
- Add profit by service
- Add profit by staff if appropriate
- Add XLSX export
- Add SharePoint upload later

### Priority 6 - Backup Pack

Goal:

- One-click business backup.

Tasks:

- Export all key tables
- Add ZIP or XLSX group
- Include backup timestamp
- Show last backup time
- Add SharePoint monthly backup option later

### Priority 7 - Sales and Marketing CRM

Goal:

- Turn enquiries into revenue and repeat customers.

Tasks:

- Add sales pipeline stages
- Add follow-up reminders
- Add lost reason
- Add customer service interests
- Add campaign export
- Add repeat customer report
- Add corporate follow-up reminders

### Priority 8 - Customer Account Upgrade

Goal:

- Improve customer self-service safely.

Tasks:

- Keep current account light
- Show enquiries and quotes
- Let customers respond to quote/request
- Later show bookings, documents, payment proof upload

### Priority 9 - Corporate Client Portal

Goal:

- Let companies access their own bookings later.

Tasks:

- Corporate login
- Company dashboard
- View own bookings only
- Upload payment proof
- Upload traveller documents
- Download invoice/receipt
- Request new booking
- Strict RLS

## 7. Definition of 100% Professional

Kridiya is 100% professionally aligned when:

- Every enquiry has a clear status and owner.
- Every quote links to one enquiry.
- Every booking links to one customer or corporate company.
- Every payment links to one booking.
- Every proof/document is private and traceable.
- Every staff action is logged.
- Owner can see sales, cost, profit, pending money, supplier payables, and staff activity.
- Staff can only access what admin allows.
- Monthly backups can be exported.
- Customer-facing pages remain simple, fast, trustworthy, and mobile-friendly.
- No secret keys or sensitive documents are publicly exposed.

## 8. Immediate Next Action

Start with live corporate flow verification.

After that, implement and verify payment proof backend.

Then implement supplier invoice upload.

Then upgrade accounting and backups.

This order gives Kridiya the strongest business value fastest while reducing operational risk.

## 9. Operating Playbook

Use this companion document for logging, contingency handling, owner checklists, and build-readiness questions:

- `docs/KRIDIYA_OPERATIONS_LOG_AND_CONTINGENCY_PLAYBOOK.md`

The playbook defines:

- required activity events
- normal individual and corporate workflows
- failure and emergency handling
- daily, weekly, and monthly owner checks
- questions needed from the owner before the next build
- full corporate operating method from enquiry to accounting
