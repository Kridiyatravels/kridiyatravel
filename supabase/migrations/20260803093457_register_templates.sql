-- Register every Kridiya template in public.templates.
--
-- public.templates is the registry the admin UI lists, and it was empty:
-- nothing pointed at any of the 45 templates that exist on disk, so staff
-- had no way to find them.
--
-- NOT YET APPLIED. Review, then apply with the backend session's tooling.

-- template_type had no value for a printable document. Widen the check
-- rather than filing thirteen documents under 'other'.
alter table public.templates
  drop constraint if exists templates_template_type_check;

alter table public.templates
  add constraint templates_template_type_check
  check (template_type = any (array[
    'admin_tool', 'sharepoint_file', 'canva', 'email', 'whatsapp',
    'sop', 'link', 'document', 'other'
  ]));

-- Re-runnable: a second run must not create a second copy of every row.
-- Deliberately not a partial index: ON CONFLICT (url) cannot infer a partial
-- index unless the statement repeats its predicate, and a plain unique index
-- already permits many NULL urls.
create unique index if not exists templates_url_key
  on public.templates (url);

insert into public.templates (template_name, category, template_type, url, status, notes)
values
  ('Document — Booking confirmation', 'customer_document', 'document', 'templates/documents/booking-confirmation.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Cancellation notice', 'customer_document', 'document', 'templates/documents/cancellation.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — E-ticket receipt', 'customer_document', 'document', 'templates/documents/eticket.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Hotel voucher', 'customer_document', 'document', 'templates/documents/hotel-voucher.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Invoice', 'customer_document', 'document', 'templates/documents/invoice.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Monthly company statement', 'customer_document', 'document', 'templates/documents/monthly-statement.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Payment request', 'customer_document', 'document', 'templates/documents/payment-request.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Quotation', 'customer_document', 'document', 'templates/documents/quotation.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Payment receipt', 'customer_document', 'document', 'templates/documents/receipt.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Refund note', 'customer_document', 'document', 'templates/documents/refund-note.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Supplier payment note', 'internal_document', 'document', 'templates/documents/supplier-payment-note.html', 'active', 'Internal and supplier-facing. Shows supplier cost. Never send to a customer.'),
  ('Document — Visa confirmation', 'customer_document', 'document', 'templates/documents/visa-confirmation.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Document — Visa application outcome', 'customer_document', 'document', 'templates/documents/visa-rejection.html', 'active', 'Customer-facing. Prints to A4. Never renders supplier cost, margin, or staff notes.'),
  ('Email — Your travel enquiry with Kridiya Travel', 'customer_email', 'email', 'templates/emails/01-enquiry-reply.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Travel quote from Kridiya Travel', 'customer_email', 'email', 'templates/emails/02-quote-sent.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Payment request', 'customer_email', 'email', 'templates/emails/03-payment-request.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Payment follow-up', 'customer_email', 'email', 'templates/emails/04-payment-follow-up.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Documents required', 'customer_email', 'email', 'templates/emails/05-documents-request.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Booking confirmed', 'customer_email', 'email', 'templates/emails/06-booking-confirmed.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Corporate booking request received', 'customer_email', 'email', 'templates/emails/07-corporate-request-received.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — LPO or approval required', 'customer_email', 'email', 'templates/emails/08-corporate-lpo-request.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Availability request', 'supplier_email', 'email', 'templates/emails/09-supplier-availability-request.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens. Supplier-facing.'),
  ('Email — Payment receipt', 'customer_email', 'email', 'templates/emails/10-receipt-sent.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Cancellation and refund update', 'customer_email', 'email', 'templates/emails/11-cancellation-refund-update.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Staff handover note', 'internal_email', 'email', 'templates/emails/12-staff-handover-note.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens. Internal only.'),
  ('Email — Your e-ticket', 'customer_email', 'email', 'templates/emails/13-eticket-issued.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Visa application outcome', 'customer_email', 'email', 'templates/emails/14-visa-outcome.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Your hotel voucher', 'customer_email', 'email', 'templates/emails/15-hotel-voucher-issued.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Your monthly statement', 'customer_email', 'email', 'templates/emails/16-monthly-statement.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens.'),
  ('Email — Kridiya Travel update', 'marketing_email', 'email', 'templates/emails/17-marketing-shell.html', 'active', 'Has a matching .txt plain-text alternative with the same tokens. Requires a signed {{ unsubscribe_url }} from the marketing-unsubscribe function.'),
  ('Auth email — Change email', 'auth_email', 'email', 'docs/email-template-preview-change-email.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Confirm signup', 'auth_email', 'email', 'docs/email-template-preview-confirm-signup.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Invite user', 'auth_email', 'email', 'docs/email-template-preview-invite-user.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Magic link', 'auth_email', 'email', 'docs/email-template-preview-magic-link.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Reauthentication', 'auth_email', 'email', 'docs/email-template-preview-reauthentication.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Reset password', 'auth_email', 'email', 'docs/email-template-preview-reset-password.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security alert', 'security_notification', 'email', 'docs/email-template-preview-security-alert.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security email changed', 'security_notification', 'email', 'docs/email-template-preview-security-email-changed.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security mfa added', 'security_notification', 'email', 'docs/email-template-preview-security-mfa-added.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security mfa removed', 'security_notification', 'email', 'docs/email-template-preview-security-mfa-removed.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security notifications', 'security_notification', 'email', 'docs/email-template-preview-security-notifications.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security password changed', 'security_notification', 'email', 'docs/email-template-preview-security-password-changed.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security phone changed', 'security_notification', 'email', 'docs/email-template-preview-security-phone-changed.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security signin linked', 'security_notification', 'email', 'docs/email-template-preview-security-signin-linked.html', 'active', 'Supabase auth template. Needs a plain-text alternative.'),
  ('Auth email — Security signin removed', 'security_notification', 'email', 'docs/email-template-preview-security-signin-removed.html', 'active', 'Supabase auth template. Needs a plain-text alternative.')
on conflict (url) do update
  set template_name = excluded.template_name,
      category      = excluded.category,
      template_type = excluded.template_type,
      status        = excluded.status,
      notes         = excluded.notes,
      updated_at    = now();
