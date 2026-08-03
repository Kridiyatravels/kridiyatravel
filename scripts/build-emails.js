/*
 * Builds templates/emails/*.html and the matching *.txt plain-text bodies.
 *
 * The twelve operational templates in docs/kridiya-email-whatsapp-templates.md
 * were plain text for staff to paste, so every customer email Kridiya sent was
 * unbranded. This turns them into the same table-based, inline-styled emails as
 * the Supabase auth set, plus a marketing shell carrying the signed unsubscribe
 * footer.
 *
 * Conventions, matching docs/supabase-auth-email-templates.md:
 *   - Tables and inline styles only. No <style> block, no flexbox, no grid.
 *   - No box-shadow anywhere: Outlook drops it and leaves a flat rectangle.
 *   - Placeholders are {{ token }} so a backend can fill them; the plain-text
 *     alternative carries exactly the same tokens.
 *   - A dark-mode meta pair plus explicit colours on every element, because
 *     Outlook and Gmail dark modes invert unstyled backgrounds.
 *
 * Run from the repository root:  node scripts/build-emails.js
 */
const fs = require("node:fs");
const path = require("node:path");

const OUT_DIR = path.join(__dirname, "..", "templates", "emails");

const BRAND = {
  deep: "#b6530f", soft: "#fff4e6", ink: "#2f2415", heading: "#1e1509",
  text: "#574b3b", muted: "#79694f", bg: "#fdf8f0", surface: "#ffffff",
  line: "#f1e8d8"
};

const COMPANY = "Kridiya Travel and Tourism FZ-LLC";
const CONTACT = "+971 50 941 3873 - contact@kridiyatravel.com - www.kridiyatravel.com";

function escapeHtml(value) {
  return String(value === null || value === undefined ? "" : value)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// Placeholder tokens must survive escaping intact, otherwise a backend
// looking for {{ amount }} would never find it.
function copy(value) {
  return escapeHtml(value);
}

function detailRows(fields) {
  return fields.map(function (field) {
    return '<tr>' +
      '<td style="padding:7px 14px 7px 0;font-size:13px;line-height:20px;color:' + BRAND.muted + ';vertical-align:top;white-space:nowrap;">' +
        copy(field.label) +
      '</td>' +
      '<td style="padding:7px 0;font-size:13px;line-height:20px;color:' + BRAND.ink + ';font-weight:700;vertical-align:top;">' +
        copy(field.value) +
      '</td>' +
    '</tr>';
  }).join("");
}

function button(label, href) {
  // Bulletproof-ish button: a table cell carrying the background so Outlook
  // paints it, and no box-shadow, which Outlook cannot render.
  return '<table role="presentation" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin:0 0 24px;">' +
    '<tr><td style="background:' + BRAND.soft + ';border-radius:8px;">' +
      '<a href="' + copy(href) + '" style="display:inline-block;padding:14px 22px;color:' + BRAND.deep +
      ';text-decoration:none;font-size:14px;line-height:18px;font-weight:800;border-radius:8px;background:' + BRAND.soft + ';">' +
        copy(label) +
      '</a>' +
    '</td></tr></table>';
}

function render(template) {
  const parts = [];

  parts.push('<!doctype html>');
  parts.push('<html lang="en">');
  parts.push('<head>');
  parts.push('<meta charset="utf-8">');
  parts.push('<meta name="viewport" content="width=device-width, initial-scale=1">');
  // Tells Apple Mail and Outlook the email has been designed for both schemes,
  // so they stop force-inverting the warm background to a muddy grey.
  parts.push('<meta name="color-scheme" content="light dark">');
  parts.push('<meta name="supported-color-schemes" content="light dark">');
  parts.push('<title>' + copy(template.title) + '</title>');
  parts.push('</head>');
  parts.push('<body style="margin:0;padding:0;background:' + BRAND.bg + ";font-family:'Plus Jakarta Sans','Segoe UI',Arial,Helvetica,sans-serif;color:" + BRAND.text + ';">');

  // Preheader: the grey line shown next to the subject in the inbox list.
  parts.push('<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;height:0;width:0;">' +
    copy(template.preheader) + '</div>');

  parts.push('  <div style="padding:36px 12px;background:' + BRAND.bg + ';">');
  parts.push('    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;"><tr><td align="center">');
  parts.push('      <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;border-collapse:collapse;background:' + BRAND.surface + ';border:1px solid ' + BRAND.line + ';border-radius:14px;overflow:hidden;">');
  parts.push('        <tr><td style="padding:32px 30px 30px;background:' + BRAND.surface + ';">');

  parts.push('          <div style="display:inline-block;margin:0 0 14px;padding:6px 10px;border-radius:999px;background:' + BRAND.soft + ';color:' + BRAND.deep + ';font-size:12px;line-height:16px;font-weight:800;">' + copy(template.eyebrow) + '</div>');
  parts.push('          <h1 style="margin:0 0 14px;font-family:\'Plus Jakarta Sans\',\'Segoe UI\',Arial,Helvetica,sans-serif;font-size:26px;line-height:33px;color:' + BRAND.heading + ';font-weight:800;">' + copy(template.heading) + '</h1>');

  template.body.forEach(function (paragraph) {
    parts.push('          <p style="margin:0 0 18px;font-size:15px;line-height:25px;color:' + BRAND.text + ';">' + copy(paragraph) + '</p>');
  });

  if (template.fields && template.fields.length) {
    parts.push('          <table role="presentation" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;margin:0 0 22px;padding:0;background:' + BRAND.bg + ';border-radius:9px;">');
    parts.push('            <tr><td style="padding:14px 16px;">');
    parts.push('              <table role="presentation" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;">' + detailRows(template.fields) + '</table>');
    parts.push('            </td></tr>');
    parts.push('          </table>');
  }

  if (template.cta) {
    parts.push('          ' + button(template.cta.label, template.cta.href));
  }

  if (template.note) {
    parts.push('          <p style="margin:0 0 22px;font-size:13px;line-height:21px;color:' + BRAND.muted + ';">' + copy(template.note) + '</p>');
  }

  parts.push('          <div style="padding-top:16px;border-top:1px solid ' + BRAND.line + ';">');
  parts.push('            <div style="font-size:14px;line-height:20px;font-weight:800;color:' + BRAND.ink + ';">' + COMPANY + '</div>');
  parts.push('            <div style="margin-top:4px;font-size:12px;line-height:18px;color:' + BRAND.muted + ';">' + CONTACT + '</div>');
  parts.push('          </div>');

  if (template.footer) {
    parts.push('          <p style="margin:18px 0 0;font-size:12px;line-height:19px;color:' + BRAND.muted + ';">' + copy(template.footer) + '</p>');
  }

  if (template.unsubscribe) {
    // The signed unsubscribe link is the whole point of the marketing shell —
    // a marketing send without it is the one that gets the domain blocked.
    parts.push('          <p style="margin:14px 0 0;font-size:12px;line-height:19px;color:' + BRAND.muted + ';">' +
      'You are receiving this because you asked Kridiya Travel to keep you updated. ' +
      '<a href="{{ unsubscribe_url }}" style="color:' + BRAND.deep + ';text-decoration:underline;">Unsubscribe</a>.' +
      '</p>');
  }

  parts.push('        </td></tr>');
  parts.push('      </table>');
  parts.push('    </td></tr></table>');
  parts.push('  </div>');
  parts.push('</body>');
  parts.push('</html>');

  return parts.join("\n") + "\n";
}

// Gmail and Outlook both fall back to the plain part when images and HTML are
// blocked, and a missing plain part is itself a spam signal.
function renderText(template) {
  const lines = [];
  lines.push(template.heading);
  lines.push("");
  template.body.forEach(function (paragraph) {
    lines.push(paragraph);
    lines.push("");
  });
  if (template.fields && template.fields.length) {
    template.fields.forEach(function (field) {
      lines.push("- " + field.label + ": " + field.value);
    });
    lines.push("");
  }
  if (template.cta) {
    lines.push(template.cta.label + ": " + template.cta.href);
    lines.push("");
  }
  if (template.note) {
    lines.push(template.note);
    lines.push("");
  }
  lines.push("Regards,");
  lines.push(COMPANY);
  lines.push(CONTACT);
  if (template.footer) {
    lines.push("");
    lines.push(template.footer);
  }
  if (template.unsubscribe) {
    lines.push("");
    lines.push("You are receiving this because you asked Kridiya Travel to keep you updated.");
    lines.push("Unsubscribe: {{ unsubscribe_url }}");
  }
  return lines.join("\n") + "\n";
}

/* ------------------------------------------------------------------
   The twelve operational templates, plus the marketing shell.
   Copy follows docs/kridiya-email-whatsapp-templates.md — the wording
   is the owner's, restructured into subject / heading / fields.
   ------------------------------------------------------------------ */

const TEMPLATES = [
  {
    file: "01-enquiry-reply",
    title: "Your travel enquiry with Kridiya Travel",
    subject: "Your travel enquiry with Kridiya Travel",
    preheader: "We have your enquiry and are checking the best available options.",
    eyebrow: "Enquiry received",
    heading: "Thank you for contacting Kridiya Travel",
    body: [
      "Hi {{ customer_name }}, thank you for contacting Kridiya Travel and Tourism. We have received your enquiry.",
      "We are checking the best available options and will come back to you shortly."
    ],
    fields: [
      { label: "Service", value: "{{ service }}" },
      { label: "Destination / route", value: "{{ route_or_destination }}" },
      { label: "Travel date", value: "{{ travel_date }}" },
      { label: "Passengers", value: "{{ passenger_count }}" }
    ],
    note: "If any of the details above are wrong, reply to this email and we will correct them before we quote."
  },
  {
    file: "02-quote-sent",
    title: "Travel quote from Kridiya Travel",
    subject: "Travel quote from Kridiya Travel - {{ route_or_destination }}",
    preheader: "Your quote is ready. Fares can change until payment and booking are completed.",
    eyebrow: "Quote ready",
    heading: "Your travel quote is ready",
    body: [
      "Hi {{ customer_name }}, here is the quote you asked for."
    ],
    fields: [
      { label: "Service", value: "{{ service }}" },
      { label: "Route / destination", value: "{{ route_or_destination }}" },
      { label: "Travel date", value: "{{ travel_date }}" },
      { label: "Passengers", value: "{{ passengers }}" },
      { label: "Total amount", value: "{{ currency }} {{ amount }}" },
      { label: "Airline / hotel / supplier", value: "{{ supplier_details }}" },
      { label: "Valid until", value: "{{ valid_until }}" }
    ],
    cta: { label: "Confirm this quote", href: "{{ confirm_url }}" },
    note: "Fares, availability, visa rules and supplier conditions can change until booking and payment are completed. To proceed, confirm and arrange payment."
  },
  {
    file: "03-payment-request",
    title: "Payment request",
    subject: "Payment request - Booking {{ booking_reference }}",
    preheader: "Payment is needed to proceed with your booking.",
    eyebrow: "Payment requested",
    heading: "Payment needed to proceed",
    body: [
      "Hi {{ customer_name }}, to proceed with your booking please arrange payment of the amount below."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Service", value: "{{ service }}" },
      { label: "Total booking value", value: "{{ currency }} {{ total_amount }}" },
      { label: "Amount due now", value: "{{ currency }} {{ amount_due }}" },
      { label: "Payment method", value: "{{ payment_method }}" },
      { label: "Account holder", value: "KRIDIYA Travel and Tourism FZ-LLC" },
      { label: "IBAN", value: "AE540860000009813682904" },
      { label: "BIC", value: "WIOBAEADXXX" },
      { label: "Payment reference", value: "{{ booking_reference }}" }
    ],
    note: "Please send the payment proof once completed. Ticketing, visa submission and supplier confirmation proceed only after payment is confirmed."
  },
  {
    file: "04-payment-follow-up",
    title: "Payment follow-up",
    subject: "Payment follow-up - Booking {{ booking_reference }}",
    preheader: "A gentle reminder about the pending payment on your booking.",
    eyebrow: "Payment pending",
    heading: "A gentle reminder about your payment",
    body: [
      "Hi {{ customer_name }}, this is a follow-up on the pending payment for booking {{ booking_reference }}."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Amount pending", value: "{{ currency }} {{ amount_pending }}" },
      { label: "Payment reference", value: "{{ booking_reference }}" }
    ],
    note: "Please complete the payment and share the proof so we can continue with the booking. Fares and availability are not held against an unpaid balance."
  },
  {
    file: "05-documents-request",
    title: "Documents required",
    subject: "Documents required for {{ service }}",
    preheader: "We need a few documents to continue with your booking.",
    eyebrow: "Documents needed",
    heading: "Documents required to continue",
    body: [
      "Hi {{ customer_name }}, to continue with your {{ service }} we need the documents listed below.",
      "{{ document_list }}"
    ],
    note: "Please make sure every document is clear and valid. Passport copies must show the full details page, with all four corners visible and no glare."
  },
  {
    file: "06-booking-confirmed",
    title: "Booking confirmed",
    subject: "Booking confirmed - {{ booking_reference }}",
    preheader: "Your booking is confirmed. Please check every detail against your passport.",
    eyebrow: "Booking confirmed",
    heading: "Your booking is confirmed",
    body: [
      "Hi {{ customer_name }}, your booking has been confirmed. The full confirmation document is attached."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Service", value: "{{ service }}" },
      { label: "Route / destination", value: "{{ route_or_destination }}" },
      { label: "Travel date", value: "{{ travel_date }}" },
      { label: "Passengers", value: "{{ passengers }}" },
      { label: "Airline / hotel reference", value: "{{ supplier_reference }}" }
    ],
    note: "Check every traveller name against the passport now. Name corrections after ticketing may not be possible and can incur airline charges."
  },
  {
    file: "07-corporate-request-received",
    title: "Corporate booking request received",
    subject: "Corporate booking request received - {{ company_name }}",
    preheader: "We have your corporate travel request and are checking availability.",
    eyebrow: "Corporate request",
    heading: "We have your corporate travel request",
    body: [
      "Hi {{ contact_name }}, thank you. We have received the corporate booking request for {{ company_name }}."
    ],
    fields: [
      { label: "Company", value: "{{ company_name }}" },
      { label: "Requester", value: "{{ requester_name }}" },
      { label: "Service", value: "{{ service }}" },
      { label: "Route / destination", value: "{{ route_or_destination }}" },
      { label: "Travel date", value: "{{ travel_date }}" },
      { label: "Travellers", value: "{{ travellers }}" }
    ],
    note: "We will review availability, payment and LPO requirements, and supplier conditions, then come back to you."
  },
  {
    file: "08-corporate-lpo-request",
    title: "LPO or approval required",
    subject: "LPO / approval required - Booking {{ booking_reference }}",
    preheader: "We need your LPO or written approval before supplier confirmation.",
    eyebrow: "Approval required",
    heading: "LPO or written approval needed",
    body: [
      "Hi {{ contact_name }}, for corporate booking {{ booking_reference }} we need the LPO or written approval before we confirm with the supplier."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "LPO number or approval email", value: "{{ lpo_number }}" },
      { label: "Approved amount", value: "{{ currency }} {{ amount }}" },
      { label: "Approving person", value: "{{ approval_person }}" },
      { label: "Billing / accounts contact", value: "{{ billing_email }}" }
    ],
    note: "Supplier confirmation cannot proceed until the approval is on file. Fares and availability may change in the meantime."
  },
  {
    file: "09-supplier-availability-request",
    title: "Availability request",
    subject: "Availability request - {{ service }} / {{ route_or_destination }}",
    preheader: "Please confirm availability, net rate and booking deadline.",
    eyebrow: "Supplier request",
    heading: "Availability and net rate request",
    body: [
      "Hi {{ supplier_name }}, please check availability and your best net rate for the request below."
    ],
    fields: [
      { label: "Service", value: "{{ service }}" },
      { label: "Route / destination", value: "{{ route_or_destination }}" },
      { label: "Travel date", value: "{{ travel_date }}" },
      { label: "Passengers", value: "{{ passengers }}" },
      { label: "Notes", value: "{{ notes }}" }
    ],
    note: "Please confirm net cost, availability, booking deadline, cancellation and refund rules, and the supplier reference if you are holding the booking.",
    footer: "Kridiya trade licence 5033347, RAK Freezone, United Arab Emirates."
  },
  {
    file: "10-receipt-sent",
    title: "Payment receipt",
    subject: "Payment receipt - Booking {{ booking_reference }}",
    preheader: "We have recorded your payment. Your receipt is attached.",
    eyebrow: "Payment received",
    heading: "Thank you — your payment is recorded",
    body: [
      "Hi {{ customer_name }}, we have recorded your payment. The receipt is attached to this email."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Amount received", value: "{{ currency }} {{ amount }}" },
      { label: "Payment method", value: "{{ payment_method }}" },
      { label: "Receipt number", value: "{{ receipt_number }}" }
    ],
    note: "Please keep the receipt for your records."
  },
  {
    file: "11-cancellation-refund-update",
    title: "Cancellation and refund update",
    subject: "Cancellation/refund update - Booking {{ booking_reference }}",
    preheader: "An update on the cancellation and refund for your booking.",
    eyebrow: "Booking update",
    heading: "Update on your cancellation and refund",
    body: [
      "Hi {{ customer_name }}, here is the current position on the cancellation and refund for booking {{ booking_reference }}."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Cancellation status", value: "{{ cancellation_status }}" },
      { label: "Refund amount, if applicable", value: "{{ currency }} {{ refund_amount }}" },
      { label: "Expected timeline", value: "{{ timeline }}" },
      { label: "Supplier / authority rule applied", value: "{{ rule }}" }
    ],
    note: "Refunds and cancellations follow the rules of the airline, hotel, visa authority or payment provider. Bank clearing times are outside our control."
  },
  {
    file: "12-staff-handover-note",
    title: "Staff handover note",
    subject: "Handover - Booking {{ booking_reference }}",
    preheader: "Internal handover note. Not for the customer.",
    eyebrow: "Internal note",
    heading: "Booking handover",
    body: [
      "Internal handover for booking {{ booking_reference }}. Do not forward this to the customer."
    ],
    fields: [
      { label: "Booking", value: "{{ booking_reference }}" },
      { label: "Customer / company", value: "{{ customer_name }}" },
      { label: "Service", value: "{{ service }}" },
      { label: "Current status", value: "{{ booking_status }}" },
      { label: "Payment status", value: "{{ payment_status }}" },
      { label: "Supplier status / reference", value: "{{ supplier_status }}" },
      { label: "Pending action", value: "{{ pending_action }}" },
      { label: "Deadline", value: "{{ deadline }}" },
      { label: "Important notes", value: "{{ notes }}" }
    ],
    footer: "Internal document. It contains operational detail that is not shared with customers."
  },
  {
    file: "13-eticket-issued",
    title: "Your e-ticket",
    subject: "E-ticket issued - Booking {{ booking_reference }}",
    preheader: "Your e-ticket is attached. Check every name against the passport.",
    eyebrow: "Ticket issued",
    heading: "Your e-ticket is ready",
    body: [
      "Hi {{ customer_name }}, your ticket has been issued and the e-ticket receipt is attached to this email.",
      "Carry it with the passport used to book. You can check in online or at the airport counter."
    ],
    fields: [
      { label: "Booking reference", value: "{{ booking_reference }}" },
      { label: "Airline reference", value: "{{ pnr }}" },
      { label: "Route", value: "{{ route_or_destination }}" },
      { label: "Departure", value: "{{ departure_datetime }}" },
      { label: "Passengers", value: "{{ passengers }}" },
      { label: "Baggage", value: "{{ baggage }}" }
    ],
    note: "Check every traveller name against the passport now. After ticketing, name corrections may not be possible and can incur airline charges. Arrive at least three hours before an international departure."
  },
  {
    file: "14-visa-outcome",
    title: "Visa application outcome",
    subject: "Visa application outcome - {{ booking_reference }}",
    preheader: "The issuing authority has returned a decision on your application.",
    eyebrow: "Visa update",
    heading: "There is a decision on your visa application",
    body: [
      "Hi {{ customer_name }}, the issuing authority has returned its decision on your application. The full outcome document is attached.",
      "{{ outcome_sentence }}"
    ],
    fields: [
      { label: "Kridiya reference", value: "{{ booking_reference }}" },
      { label: "Application number", value: "{{ application_number }}" },
      { label: "Country", value: "{{ country }}" },
      { label: "Visa type", value: "{{ visa_type }}" },
      { label: "Outcome", value: "{{ outcome }}" },
      { label: "Decision date", value: "{{ decided_on }}" }
    ],
    // One email covers approval and refusal, so the sentence and the note
    // are both filled by the caller. Writing a fixed congratulatory line
    // here would send it on a refusal too.
    note: "{{ next_step_note }}"
  },
  {
    file: "15-hotel-voucher-issued",
    title: "Your hotel voucher",
    subject: "Hotel voucher - Booking {{ booking_reference }}",
    preheader: "Your hotel voucher is attached. Present it at check-in.",
    eyebrow: "Voucher issued",
    heading: "Your hotel voucher is ready",
    body: [
      "Hi {{ customer_name }}, your hotel reservation is arranged and the voucher is attached.",
      "Present the voucher with the lead guest's passport at check-in."
    ],
    fields: [
      { label: "Hotel", value: "{{ hotel_name }}" },
      { label: "Address", value: "{{ hotel_address }}" },
      { label: "Check-in", value: "{{ check_in }}" },
      { label: "Check-out", value: "{{ check_out }}" },
      { label: "Room", value: "{{ room_type }}" },
      { label: "Hotel confirmation", value: "{{ hotel_confirmation }}" },
      { label: "Kridiya reference", value: "{{ booking_reference }}" }
    ],
    note: "The hotel may ask for a card at check-in to cover extras such as minibar or laundry — those are settled directly by the guest. Tourism and city fees charged at the property are payable locally unless the voucher states they are included."
  },
  {
    file: "16-monthly-statement",
    title: "Your monthly statement",
    subject: "Monthly statement {{ period }} - {{ company_name }}",
    preheader: "Your company statement for the period is attached.",
    eyebrow: "Company statement",
    heading: "Your monthly statement is ready",
    body: [
      "Hi {{ contact_name }}, the statement for {{ company_name }} covering {{ period }} is attached."
    ],
    fields: [
      { label: "Statement number", value: "{{ statement_number }}" },
      { label: "Period", value: "{{ period }}" },
      { label: "Bookings in period", value: "{{ booking_count }}" },
      { label: "Invoiced", value: "{{ currency }} {{ invoiced }}" },
      { label: "Received", value: "{{ currency }} {{ received }}" },
      { label: "Balance outstanding", value: "{{ currency }} {{ outstanding }}" },
      { label: "Payment narrative", value: "{{ statement_number }}" }
    ],
    note: "Please quote the payment narrative on any transfer so it can be matched to your account. If any line is disputed, tell us within seven days and we will hold that line while it is checked."
  },
  {
    file: "17-marketing-shell",
    title: "Kridiya Travel update",
    subject: "{{ subject }}",
    preheader: "{{ preheader }}",
    eyebrow: "Kridiya Travel",
    heading: "{{ heading }}",
    body: [
      "Hi {{ customer_name }},",
      "{{ body_paragraph_1 }}",
      "{{ body_paragraph_2 }}"
    ],
    cta: { label: "{{ cta_label }}", href: "{{ cta_url }}" },
    note: "{{ closing_note }}",
    unsubscribe: true
  }
];

function build() {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const index = [];
  TEMPLATES.forEach(function (template) {
    const htmlPath = path.join(OUT_DIR, template.file + ".html");
    const textPath = path.join(OUT_DIR, template.file + ".txt");
    fs.writeFileSync(htmlPath, render(template));
    fs.writeFileSync(textPath, renderText(template));
    index.push({ file: template.file, subject: template.subject });
    console.log("  " + template.file + ".html + .txt");
  });

  // A subject-line list, so whoever wires these up does not have to open
  // thirteen files to find out what each one is for.
  const readme = [
    "# Kridiya operational email templates",
    "",
    "Generated by `scripts/build-emails.js` — edit the script, not these files.",
    "",
    "Each template has an `.html` body and a matching `.txt` plain-text",
    "alternative carrying the same `{{ tokens }}`. Send both parts: a missing",
    "plain-text part is itself a spam signal.",
    "",
    "| File | Subject |",
    "|---|---|"
  ].concat(index.map(function (row) {
    return "| `" + row.file + "` | " + row.subject + " |";
  })).concat([
    "",
    "`17-marketing-shell` is the only one carrying the unsubscribe footer. Any",
    "marketing send must use it and must fill `{{ unsubscribe_url }}` with a",
    "signed link from the marketing-unsubscribe function.",
    "",
    "`09` is supplier-facing and `12` is internal. Neither goes to a customer.",
    ""
  ]).join("\n");

  fs.writeFileSync(path.join(OUT_DIR, "README.md"), readme);
  console.log("  README.md");
  console.log(TEMPLATES.length + " templates written to templates/emails/");
}

build();
