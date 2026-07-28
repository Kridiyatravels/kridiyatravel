# Kridiya Business Travel Corporate Portal Plan

Last updated: 2026-07-28

## Objective

Make `corporate.kridiyatravel.com` a professional corporate front office connected to `admin.kridiyatravel.com`, with Supabase as the shared system of record.

The public corporate site should sell trust and collect requests. The private corporate portal should let approved companies see and submit their own records. The admin system remains the operational control center.

## Target Architecture

- `kridiyatravel.com`: public retail travel site.
- `corporate.kridiyatravel.com`: corporate marketing site plus approved company portal.
- `admin.kridiyatravel.com`: staff/admin operations system.
- Supabase: shared database, auth, private storage, audit log.
- SharePoint/Microsoft 365: backup/export/accounting document layer.

## Roles

### Staff/Admin

- Approves companies.
- Creates corporate accounts and contacts.
- Creates/invites corporate portal users.
- Converts enquiries to corporate bookings.
- Sends quotes/payment requests.
- Uploads tickets, vouchers, invoices, receipts, and statements.
- Sees supplier cost, profit, staff notes, and all companies.

### Corporate Owner

- Sees own company bookings.
- Submits requests.
- Can approve quotes.
- Can view finance/monthly statement.
- Can download visible documents.

### Travel Coordinator

- Sees own company bookings.
- Submits requests.
- Can view/download operational documents.
- Usually cannot view finance unless allowed.

### Finance User

- Sees own company bookings.
- Views payment status, invoices, receipts, monthly statements.
- Uploads payment proof or LPO if enabled.

### Requester/Employee

- Submits travel requests.
- Sees only allowed own/company request status depending on company policy.

## Recommended Workflow

1. Company visits `corporate.kridiyatravel.com`.
2. Company applies for corporate account or sends a travel request.
3. Request is saved in Supabase and visible in `admin.kridiyatravel.com`.
4. Staff reviews company details.
5. Staff creates/reuses corporate account.
6. Staff creates/reuses corporate contact.
7. Staff approves portal access.
8. Staff creates/invites Supabase Auth user.
9. Staff links user to company using `manage_corporate_portal_member`.
10. Company user logs in to corporate portal.
11. Company submits new requests using `create_my_corporate_request`.
12. Admin handles quote, payment, booking, documents, and reporting.
13. Corporate user sees only portal-safe booking details.

## My Side

### Already Prepared

- Local migration: `supabase/migrations/20260728_corporate_portal_access_layer.sql`

It adds:

- `corporate_portal_members`
- company membership checks
- staff-managed portal user linking
- corporate user portal summary
- corporate user booking list
- corporate user booking detail
- corporate user request creation
- audit logging for member creation and request creation

### Next Build Tasks

1. Connect `corporate.kridiyatravel.com` login to Supabase Auth.
2. Create a real `portal.html` dashboard using:
   - `get_my_corporate_portal`
   - `list_my_corporate_bookings`
   - `get_my_corporate_booking_detail`
   - `create_my_corporate_request`
3. Replace demo portal data with live Supabase data.
4. Add role-aware UI:
   - finance cards only when `can_view_finance`
   - request button only when `can_request`
   - approval controls only when `can_approve_quotes`
5. Add clear locked/approval states.
6. Add corporate portal manual for staff.

## Your Manual Side

### Supabase

1. Open Supabase dashboard for project `jmvqqpughlzeqrcyavwz`.
2. Confirm these tables exist:
   - `corporate_accounts`
   - `corporate_contacts`
   - `bookings`
   - `booking_documents`
   - `payments`
   - `audit_events`
3. Apply the migration:
   - `supabase/migrations/20260728_corporate_portal_access_layer.sql`
4. Check there are no SQL errors.
5. Confirm RLS is enabled on `corporate_portal_members`.

### Admin

1. Open `https://admin.kridiyatravel.com`.
2. Confirm staff login works.
3. Confirm you can see corporate accounts.
4. Confirm you can see operations bookings.
5. Confirm you can convert corporate enquiries.

### Corporate User Test

1. Create one test company in admin, for example `Kridiya Test Corporate`.
2. Create one test corporate contact.
3. Create/invite one Supabase Auth user for that contact.
4. Link that user to the company with:

```sql
select public.manage_corporate_portal_member(
  '<corporate_account_id>',
  '<auth_user_id>',
  '<corporate_contact_id>',
  'travel_coordinator',
  'active',
  true,
  false,
  false,
  true,
  'Test portal user'
);
```

5. Send me the result:
   - success
   - SQL error
   - screenshot

## Security Rules

- Corporate users must never see supplier cost.
- Corporate users must never see gross profit.
- Corporate users must never see staff notes.
- Corporate users must never see other companies.
- Staff/admin remains the only place for supplier, profit, and sensitive operations.
- Use email OTP/magic link or proper password auth for corporate users.
- Do not use shared passwords for companies.
- Do not put service role keys in frontend code.

## 100/100 Feature Roadmap

### Phase 1: Secure Portal Base

- Company membership table.
- Corporate-safe RPCs.
- Corporate login.
- Dashboard with company name, permissions, open bookings.
- New request form connected to bookings.

### Phase 2: Request Tracking

- Status timeline.
- Booking detail drawer/page.
- Visible documents.
- Payment status.
- Staff/admin uploads documents, corporate sees approved files.

### Phase 3: Quote Approval

- Quote options visible to corporate.
- Approve/reject quote from portal.
- Approval person and timestamp.
- Admin notification/status update.

### Phase 4: Finance

- LPO upload.
- Payment proof upload.
- Invoice/receipt download.
- Monthly statement view.
- Outstanding balance view.

### Phase 5: Enterprise Controls

- Multiple company branches.
- Multiple approvers.
- Approval limit by amount.
- Travel policy rules.
- SLA monitoring.
- WhatsApp/email notifications.
- Monthly PDF export.

## Current Best Next Step

Apply the portal access migration in Supabase after confirming the existing corporate tables. Then I can connect the corporate portal UI to live data.
