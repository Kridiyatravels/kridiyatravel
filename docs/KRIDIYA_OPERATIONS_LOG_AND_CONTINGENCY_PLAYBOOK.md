# Kridiya Operations Log and Contingency Playbook

Last updated: 2026-07-25

## 1. Purpose

This playbook defines how Kridiya should log work, monitor staff, recover from problems, and keep the business running under normal and difficult circumstances.

The system must be prepared for:

- Normal customer enquiries
- Corporate enquiries
- Staff mistakes
- Duplicate bookings
- Payment proof disputes
- Supplier price changes
- Missing documents
- Customer cancellation
- Refunds
- Staff access changes
- Website form/email failure
- Supabase outage
- SharePoint/manual backup needs
- Security and privacy incidents

## 2. System of Record

Supabase is the live system of record.

SharePoint/Microsoft 365 is the backup, document, and accounting export layer.

The `kridiya-admin` site is the only staff/admin interface.

The public website is only for customers, service information, enquiry capture, and light customer accounts.

## 3. Universal Logging Rule

Every important business action should create an activity log entry.

Each log should record:

- actor_user_id
- event_type
- entity_type
- entity_id
- created_at
- metadata

Metadata should include references that help the owner understand the action quickly:

- enquiry reference
- booking reference
- customer name
- company name
- amount
- currency
- payment method
- old status
- new status
- file name when relevant
- reason/note when relevant

## 4. Required Activity Events

### Authentication and Staff Access

- `staff.login`
- `staff.logout`
- `staff.created`
- `staff.pin_reset`
- `staff.permissions_updated`
- `staff.revoked`

### Enquiries

- `enquiry.created`
- `enquiry.status_updated`
- `enquiry.note_added`
- `enquiry.request_sent`
- `enquiry.quote_sent`
- `enquiry.quote_removed`
- `enquiry.converted_to_booking`
- `enquiry.converted_to_corporate_booking`
- `enquiry.closed_lost`

### Quotes

- `quote.created`
- `quote.sent_to_customer`
- `quote.accepted`
- `quote.declined`
- `quote.expired`
- `quote.revised`

### Bookings

- `booking.created`
- `booking.status_updated`
- `booking.payment_status_updated`
- `booking.document_status_updated`
- `booking.corporate_controls_updated`
- `booking.task_created`
- `booking.task_completed`
- `booking.passenger_added`
- `booking.passenger_removed`
- `booking.cancelled`

### Payments

- `payment.request_generated`
- `payment.recorded`
- `payment.proof_uploaded`
- `payment.proof_viewed`
- `payment.verified`
- `payment.receipt_generated`
- `payment.refund_requested`
- `payment.refund_approved`
- `payment.refund_completed`

### Suppliers

- `supplier.portal_created`
- `supplier.portal_updated`
- `supplier.payment_recorded`
- `supplier.invoice_uploaded`
- `supplier.invoice_viewed`
- `supplier.reference_updated`

### Documents

- `document.generated`
- `document.uploaded`
- `document.viewed`
- `document.deleted`
- `document.sent_to_customer`

### Accounting and Backups

- `accounting.report_exported`
- `backup.pack_exported`
- `backup.monthly_completed`
- `backup.sharepoint_uploaded`

### Security

- `security.permission_denied`
- `security.suspicious_access`
- `security.storage_access_denied`
- `security.rpc_denied`
- `security.audit_review_completed`

## 5. End-to-End Business Workflow

### Normal Individual Booking

1. Customer submits enquiry.
2. System saves enquiry in Supabase.
3. System emails enquiry through FormSubmit.
4. Staff sees enquiry in admin.
5. Staff checks supplier portal.
6. Staff sends quote.
7. Customer accepts quote.
8. Staff generates payment request.
9. Customer pays by bank/cash/payment link.
10. Staff records payment.
11. Staff uploads payment proof if available.
12. Staff verifies payment.
13. Staff creates or updates booking.
14. Staff records supplier cost.
15. Staff uploads supplier invoice later.
16. Staff uploads/generates documents.
17. Staff generates receipt.
18. Accounting updates reports.
19. Backup includes all records.

### Normal Corporate Booking

1. Company submits corporate enquiry.
2. Enquiry includes company, contact, service, route, traveller count, LPO, billing email, notes.
3. Staff reviews corporate chips in admin.
4. Staff converts enquiry to corporate booking.
5. System creates or reuses corporate account.
6. System creates or reuses corporate contact.
7. System creates linked booking.
8. Booking starts as payment not requested and documents not started.
9. Staff sends quote/payment request.
10. Company approves and pays or sends required LPO.
11. Staff records payment/proof.
12. Staff confirms supplier booking.
13. Staff records supplier cost and invoice.
14. Staff uploads traveller documents/tickets/visa files.
15. Accounting tracks company balance, sales, cost, profit, and pending collections.

## 6. Contingency Handling

### Website Form Fails But Email Works

Action:

- Staff manually creates enquiry in admin from the email.
- Add note: "Created manually from email because website save failed."
- Log `enquiry.created`.

Fix:

- Check Supabase insert policy, public key, and browser console.

### Website Saves But Email Fails

Action:

- Staff handles enquiry from admin.
- Add note that FormSubmit email failed if visible.

Fix:

- Check FormSubmit endpoint, inbox spam/quarantine, and contact email.

### Duplicate Enquiry

Action:

- Keep the newest complete enquiry as active.
- Add internal note linking the duplicate reference.
- Close duplicate as `closed` or `duplicate` if status exists.

Future improvement:

- Add duplicate detection by email/phone/reference/company.

### Corporate Conversion Creates Existing Booking

Action:

- Show existing booking.
- Do not create another booking.
- Open the existing booking detail page.
- Log metadata with `existing_booking: true`.

### Supplier Price Changes After Quote

Action:

- Do not book at old price.
- Add internal note.
- Send revised quote.
- Log `quote.revised`.

### Customer Pays Less Than Required

Action:

- Record payment as partial.
- Keep booking payment status as `partially_paid`.
- Do not confirm supplier booking unless owner approves exception.
- Send balance request.

### Payment Proof Uploaded But Money Not Received

Action:

- Mark status `proof_received`.
- Do not mark as paid.
- Staff verifies bank/cash/payment provider.
- Only then mark as `received` or `paid`.

### Payment Dispute

Action:

- Add payment note.
- Keep proof attached.
- Owner/admin reviews.
- Do not issue final document until resolved.

### Supplier Invoice Missing

Action:

- Record supplier payable with supplier reference and notes.
- Mark invoice missing.
- Add task to collect supplier invoice.

### Customer Cancels

Action:

- Update booking status to cancelled.
- Record cancellation reason.
- Check supplier penalty.
- Calculate refund if any.
- Generate cancellation/refund note.
- Log all actions.

### Refund Requested

Action:

- Staff records refund request.
- Mark payment status as `refund_pending`.
- Only owner/admin, or finance with `approve_refunds`, approves.
- Record refund method and amount.
- Record supplier/airline/hotel/visa authority refund rule.
- Record customer reason and internal note.
- Keep refund proof/reference after payout.
- Generate refund note.
- Update accounting report so refund pending/refunded/net collected is visible.

### Staff Enters Wrong Data

Action:

- Edit if permission allows.
- Activity log keeps record.
- Add note if financial/customer-impacting.

### Staff Leaves Company

Action:

- Revoke staff access.
- Reset shared supplier portal passwords manually if staff had access.
- Review last 30 days activity.
- Export activity log.

### Supabase Outage

Action:

- Use WhatsApp/email manually.
- Record enquiries in temporary spreadsheet.
- Enter into admin once Supabase returns.
- Keep all customer payment proof in SharePoint/email until restored.

### Admin Site Outage

Action:

- Use Supabase Dashboard only if owner/admin can safely access.
- Otherwise use manual spreadsheet and email/WhatsApp.
- Enter records later.

### SharePoint Outage

Action:

- Continue live operations in Supabase.
- Download local CSV backup.
- Upload to SharePoint when available.

### Security Incident

Action:

- Revoke affected staff access.
- Rotate staff PIN/password.
- Review audit log.
- Check storage access.
- Check public frontend for exposed keys.
- Export security evidence.
- Document incident and resolution.

## 7. Daily Owner Checklist

Every day:

- Check new enquiries.
- Check pending quotes.
- Check follow-ups due today.
- Check payment pending bookings.
- Check proof received but not verified.
- Check bookings confirmed before payment.
- Check supplier payments pending.
- Check documents not started.
- Check staff activity summary.

## 8. Weekly Owner Checklist

Every week:

- Review sales by service.
- Review open corporate enquiries.
- Review pending collections.
- Review supplier payables.
- Review staff permissions.
- Export weekly backup.
- Check failed/closed enquiries and lost reasons.
- Check templates and WhatsApp messages.

## 9. Monthly Owner Checklist

Every month:

- Export accounting report.
- Export full backup pack.
- Upload backup/report to SharePoint.
- Review gross profit.
- Review refund pending, refunded, and net collected.
- Review corporate balances.
- Review supplier payables.
- Review security permissions.
- Review staff activity.
- Review marketing/customer follow-up list.

## 10. Implementation Priorities

### Immediate

- Live-test corporate enquiry conversion.
- Confirm `kridiya-admin` is the only admin surface.
- Finish payment proof backend and audit log.

### Next

- Upgrade payments page proof visibility.
- Upgrade accounting reports.
- Upgrade backup pack.
- Add optional SharePoint invoice URL capture on supplier invoice upload until full automation is ready.

### Later

- Customer portal upgrade.
- Corporate client portal.
- Automated payment gateway webhooks.
- WhatsApp Business API.
- Email marketing automation.

## 11. Questions for Owner Before Next Build

Answered/confirmed so far:

1. Live admin URL: likely `https://admin.kridiyatravel.com/`; use this unless production check proves otherwise.
2. Official owner/admin email: `indirani@kridiyatravel.com`.
3. Staff roles: owner first; other staff roles will be appointed later.
4. Payment request bank details:
   - Account holder: KRIDIYA Travel and Tourism FZ-LLC
   - IBAN: AE540860000009813682904
   - BIC: WIOBAEADXXX
   - Bank address: Etihad Airways Centre 5th Floor, Abu Dhabi, UAE
5. Cash payments do not always require owner approval before being marked received.
6. Current suppliers: Akbar Travels and Select My Flight only; more will be added later.
7. Old public `admin.html`: not required; redirect/remove in favor of `kridiya-admin`.
8. Staff login method: PIN-only for staff login. Admin creates staff accounts with name/email/role and the system gives a PIN.
9. Payment proof upload: staff-only for now. Customer upload can come later after customer portal security is hardened.
10. Supplier invoice storage: store in Supabase private storage and also keep/copy to SharePoint when operationally needed.
11. Corporate contact channel for now: +971 50 941 3873 and enquiry@kridiyatravel.com.
12. Customer login should remain visible on the public site for profile, enquiries, quotes, and requested uploads. Staff still controls bookings/payments.

Resolved decisions from owner:

1. Staff login remains PIN-only. Admin sees the generated PIN during account creation or reset; existing PINs are not stored visibly.
2. Supplier invoice files are stored in private Supabase storage now. Staff/admin can record a SharePoint copy link now, and SharePoint upload automation should be added later.
3. Future customer/corporate portal login should use email OTP or magic-link, not shared PINs.
4. SharePoint structure is `Kridiya Travel/Operations/Bookings/YYYY/MM/BOOKING-REFERENCE/...` for booking documents and `Kridiya Travel/Finance/YYYY/MM` for monthly finance exports.

## 12. Build Readiness Decision

Proceed with coding when:

- The live admin URL is confirmed or accepted as `https://admin.kridiyatravel.com/`.
- Owner/admin email is confirmed.
- Payment request bank details are confirmed.
- Old public admin redirect decision is confirmed.
- Payment proof upload responsibility is confirmed before customer-facing upload is added.

If these are not confirmed, continue with safe backend/documentation work only.

## 13. Corporate Operating Method

### Corporate Intake

1. Company submits `corporate-booking.html`.
2. Required details:
   - company name
   - contact person
   - email
   - phone/WhatsApp
   - service needed
   - route/destination
   - traveller count
   - travel dates if known
   - payment terms
   - LPO/PO requirement
   - billing email
   - traveller details
   - approval notes
3. Enquiry appears in `kridiya-admin` Enquiries.
4. Staff reviews corporate chips before replying.

### Corporate Qualification

1. Confirm company name and contact authority.
2. Confirm whether LPO/PO is required.
3. Confirm payment-before-booking unless owner approves another arrangement.
4. Confirm billing email and accounts contact.
5. Add internal note if approval chain is unclear.

### Corporate Quote

1. Staff checks supplier portals.
2. Staff prepares quote with service details, terms, validity, and payment condition.
3. Staff sends quote by WhatsApp/email.
4. Activity log records quote sent.
5. Follow-up task is created if no response.

### Corporate Conversion

1. Staff clicks Convert in Enquiries.
2. System creates/reuses corporate account.
3. System creates/reuses corporate contact.
4. System creates linked corporate booking.
5. Enquiry status becomes confirmed.
6. Booking opens in booking detail.
7. Booking must show:
   - booking_kind = corporate
   - source = corporate
   - enquiry_id linked
   - company/contact linked
   - payment_status = not_requested
   - document_status = not_started

### Corporate Payment and Approval

1. Staff generates payment request.
2. Company pays by bank transfer/cash/payment link or sends required LPO.
3. Staff records payment.
4. Staff uploads payment proof if available.
5. Payment proof is marked proof_received until money is verified.
6. Staff updates payment status only after verification.
7. Supplier confirmation should happen only after payment/approval is safe.

### Corporate Supplier and Documents

1. Staff records supplier name/reference.
2. Staff records supplier payable/cost.
3. Staff uploads supplier invoice to Supabase private storage.
4. Staff also keeps/copies supplier invoice to SharePoint when needed.
5. Staff uploads traveller documents/tickets/visa files.
6. Staff generates receipt/invoice/confirmation.

### Corporate Accounting

1. Accounting tracks:
   - company
   - booking reference
   - selling price
   - supplier cost
   - gross profit
   - amount received
   - pending balance
   - supplier payable
   - LPO/approval status
2. Corporate balances should appear in monthly reports.
3. Corporate data must be included in backup packs.

### Future Corporate Portal

Build only after admin workflow is stable.

Future corporate users should be able to:

- log in securely
- view only their company bookings
- request new bookings
- upload payment proof
- upload traveller documents
- download invoices/receipts
- view status

They must never see:

- supplier cost
- profit
- other companies
- staff-only notes
