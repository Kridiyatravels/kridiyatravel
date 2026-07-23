/* ============================================================
   Kridiya Travel — document generator (documents.html only)
   Builds invoices, e-tickets, cancellation notices and visa
   rejection notices as clean print-ready pages, and logs every
   one issued to public.documents for the account/admin history.
   Staff only — gated the same way as admin.html.
   ============================================================ */
"use strict";

(function () {
  if (document.body.dataset.page !== "documents") return;

  const DOC_KINDS = [
    { id: "invoice", label: "Invoice", docType: "invoice" },
    { id: "eticket_flight_oneway", label: "E-Ticket — Flight (one-way)", docType: "eticket", service: "flight", trip: "One-way", nameField: "passengers" },
    { id: "eticket_flight_roundtrip", label: "E-Ticket — Flight (round-trip)", docType: "eticket", service: "flight", trip: "Round-trip", nameField: "passengers" },
    { id: "eticket_flight_multicity", label: "E-Ticket — Flight (multi-city)", docType: "eticket", service: "flight", trip: "Multi-city", nameField: "passengers" },
    { id: "eticket_hotel", label: "E-Ticket — Hotel voucher", docType: "eticket", service: "hotel", nameField: "guests" },
    { id: "eticket_visa", label: "E-Ticket — Visa confirmation", docType: "eticket", service: "visa", nameField: "applicants" },
    { id: "eticket_holiday", label: "E-Ticket — Holiday package", docType: "eticket", service: "holiday", nameField: "travellers" },
    { id: "eticket_umrah", label: "E-Ticket — Umrah package", docType: "eticket", service: "umrah", nameField: "pilgrims" },
    { id: "eticket_cruise", label: "E-Ticket — Cruise package", docType: "eticket", service: "cruise", nameField: "guests" },
    { id: "cancellation", label: "Cancellation notice", docType: "cancellation" },
    { id: "visa_rejection", label: "Visa rejection notice", docType: "visa_rejection", nameField: "applicants" }
  ];

  let sb = null;
  let currentUserId = null;
  let settings = null;
  let linkedEnquiry = null;

  /* ---------- Small helpers ---------- */
  function money(amount, currency) {
    const n = Number(amount || 0);
    return (currency || "AED") + " " + n.toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function todayISO() {
    const d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function fmtDate(iso) {
    if (!iso) return "";
    const d = new Date(iso + "T00:00:00");
    return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  }
  function esc(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function nl2br(v) {
    return esc(v).replace(/\n/g, "<br>");
  }
  function findKind(id) {
    return DOC_KINDS.find(function (k) { return k.id === id; });
  }

  /* ---------- Print document shell (shared by every kind) ---------- */
  const PRINT_CSS =
    "body{font-family:Georgia,'Times New Roman',serif;color:#1a1a1a;margin:0;padding:2.4rem 2.6rem;background:#fff}" +
    ".doc-letterhead{display:flex;justify-content:space-between;align-items:flex-start;gap:1.5rem;border-bottom:3px solid #c9601c;padding-bottom:1rem;margin-bottom:1.6rem}" +
    ".doc-brand{display:flex;gap:0.9rem;align-items:flex-start}" +
    ".doc-logo{width:52px;height:52px;object-fit:contain}" +
    ".doc-brand b{font-size:1.15rem;color:#a3480f}" +
    ".doc-brand p{margin:0.2rem 0 0;font-size:0.78rem;font-family:Arial,sans-serif;color:#555;line-height:1.5}" +
    ".doc-meta{text-align:right;font-family:Arial,sans-serif}" +
    ".doc-type-label{font-size:0.72rem;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#a3480f}" +
    ".doc-number{font-size:1.3rem;font-weight:700;margin-top:0.2rem}" +
    ".doc-date{font-size:0.8rem;color:#666;margin-top:0.15rem}" +
    "h2{font-family:Arial,sans-serif;font-size:1rem;color:#a3480f;margin:1.6rem 0 0.5rem;text-transform:uppercase;letter-spacing:0.04em}" +
    "table{width:100%;border-collapse:collapse;font-family:Arial,sans-serif;font-size:0.86rem}" +
    "table th{text-align:left;background:#fdf1e4;padding:0.5rem 0.7rem;border-bottom:2px solid #e8b98a;font-size:0.72rem;text-transform:uppercase;letter-spacing:0.03em;color:#8a4210}" +
    "table td{padding:0.55rem 0.7rem;border-bottom:1px solid #eee;vertical-align:top}" +
    "table.totals td{border:none;padding:0.3rem 0.7rem}" +
    "table.totals .label{text-align:right;color:#555}" +
    "table.totals .grand td{font-weight:700;font-size:1rem;border-top:2px solid #c9601c;padding-top:0.6rem}" +
    ".kv{font-family:Arial,sans-serif;font-size:0.88rem;display:grid;grid-template-columns:170px 1fr;gap:0.35rem 1rem;margin-bottom:0.3rem}" +
    ".kv .k{color:#777}" +
    ".kv .v{color:#1a1a1a;font-weight:600}" +
    ".note{font-family:Arial,sans-serif;font-size:0.82rem;color:#555;white-space:pre-line;line-height:1.6}" +
    ".box{background:#fdf1e4;border:1px solid #f0d3ae;border-radius:8px;padding:0.9rem 1.1rem;margin-top:0.6rem}" +
    ".footer-note{margin-top:2.4rem;padding-top:1rem;border-top:1px solid #eee;font-family:Arial,sans-serif;font-size:0.74rem;color:#888}" +
    "@media print{body{padding:0.4in}}";

  function letterheadHTML(docLabel, docNumber, docDate) {
    let addr =
      "Ras Al Khaimah, United Arab Emirates<br>" +
      "+971 50 941 3873 &middot; info@kridiyatravel.com &middot; kridiyatravel.com";
    if (settings.trade_license_no) addr += "<br>Trade licence: " + esc(settings.trade_license_no);
    if (settings.vat_registered && settings.trn) addr += "<br>TRN: " + esc(settings.trn);
    return (
      '<div class="doc-letterhead">' +
        '<div class="doc-brand">' +
          '<img src="' + new URL("assets/logo.png", location.href).href + '" alt="" class="doc-logo">' +
          "<div><b>" + esc(settings.legal_name) + "</b><p>" + addr + "</p></div>" +
        "</div>" +
        '<div class="doc-meta">' +
          '<div class="doc-type-label">' + esc(docLabel) + "</div>" +
          '<div class="doc-number">' + esc(docNumber || "DRAFT") + "</div>" +
          '<div class="doc-date">' + esc(fmtDate(docDate)) + "</div>" +
        "</div>" +
      "</div>"
    );
  }

  function bankBoxHTML() {
    if (!settings.bank_iban && !settings.bank_name) return "";
    return (
      '<div class="box"><b style="font-family:Arial,sans-serif;font-size:0.8rem">Bank transfer details</b>' +
      '<div class="kv" style="margin-top:0.5rem">' +
        (settings.bank_account_name ? '<span class="k">Account name</span><span class="v">' + esc(settings.bank_account_name) + "</span>" : "") +
        (settings.bank_name ? '<span class="k">Bank</span><span class="v">' + esc(settings.bank_name) + "</span>" : "") +
        (settings.bank_iban ? '<span class="k">IBAN</span><span class="v">' + esc(settings.bank_iban) + "</span>" : "") +
        (settings.bank_swift ? '<span class="k">SWIFT/BIC</span><span class="v">' + esc(settings.bank_swift) + "</span>" : "") +
      "</div></div>"
    );
  }

  function standaloneDocHTML(title, bodyHTML) {
    return (
      "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>" + esc(title) + "</title><style>" + PRINT_CSS + "</style></head><body>" +
      bodyHTML +
      '<div class="footer-note">Kridiya Travel and Tourism &mdash; issued via kridiyatravel.com/admin. This document is confidential and intended for the named recipient only.</div>' +
      "</body></html>"
    );
  }

  function openPrintWindow(title, bodyHTML) {
    const win = window.open("", "_blank");
    if (!win) { toast("Please allow pop-ups to view/print the document."); return; }
    win.document.open();
    win.document.write(standaloneDocHTML(title, bodyHTML));
    win.document.close();
    win.focus();
  }

  function showInlinePreview(title, bodyHTML) {
    const mount = document.getElementById("doc-preview");
    mount.innerHTML = "";
    const iframe = document.createElement("iframe");
    iframe.className = "doc-preview-frame";
    mount.appendChild(iframe);
    const doc = iframe.contentWindow.document;
    doc.open();
    doc.write(standaloneDocHTML(title, bodyHTML));
    doc.close();
  }

  /* ---------- Repeatable rows widget ---------- */
  function renderRepeatable(containerId, addBtnId, rowHTMLFn, initial) {
    const container = document.getElementById(containerId);
    const addBtn = document.getElementById(addBtnId);
    let count = 0;
    function addRow() {
      const div = document.createElement("div");
      div.className = "repeat-row";
      div.dataset.index = String(count);
      div.innerHTML = rowHTMLFn(count) + '<button type="button" class="btn btn-outline repeat-remove">Remove</button>';
      container.appendChild(div);
      count++;
    }
    container.innerHTML = "";
    count = 0;
    for (let i = 0; i < initial; i++) addRow();
    if (addBtn) addBtn.addEventListener("click", addRow);
    container.addEventListener("click", function (e) {
      const btn = e.target.closest(".repeat-remove");
      if (!btn) return;
      if (container.children.length <= 1) return;
      btn.closest(".repeat-row").remove();
    });
  }
  function rowsOf(containerId) {
    return Array.from(document.getElementById(containerId).children);
  }
  function fieldVal(row, name) {
    const el = row.querySelector('[name="' + name + '"]');
    return el ? el.value.trim() : "";
  }

  /* ================= FORM BUILDERS + RENDERERS PER KIND ================= */

  function prefillName() { return linkedEnquiry ? linkedEnquiry.full_name : ""; }
  function deriveCustomerName(kind, data) {
    if (data.customer_name) return data.customer_name;
    if (kind.nameField && data[kind.nameField]) {
      const first = String(data[kind.nameField]).split("\n")[0].trim();
      if (first) return first;
    }
    return prefillName();
  }
  function prefillEmail() { return linkedEnquiry ? linkedEnquiry.email : ""; }
  function prefillPhone() { return linkedEnquiry ? linkedEnquiry.phone : ""; }
  function prefillRef() { return linkedEnquiry ? linkedEnquiry.reference : ""; }

  /* ---- Invoice ---- */
  function buildFormInvoice(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>BILL TO</label><input name="customer_name" required value="' + esc(prefillName()) + '"></div>' +
        '<div class="field col-6"><label>EMAIL</label><input name="customer_email" type="email" value="' + esc(prefillEmail()) + '"></div>' +
        '<div class="field col-6"><label>INVOICE DATE</label><input name="invoice_date" type="date" value="' + todayISO() + '"></div>' +
        '<div class="field col-6"><label>CURRENCY</label><input name="currency" value="AED" maxlength="3" style="text-transform:uppercase"></div>' +
      "</div>" +
      '<h3 style="margin-top:1rem">Line items</h3>' +
      '<div id="rep-items"></div>' +
      '<button type="button" id="add-item" class="btn btn-outline" style="margin-top:0.5rem">+ Add line item</button>' +
      '<div class="field" style="margin-top:1rem"><label>NOTES / TERMS</label><textarea name="notes">' + esc(settings.invoice_footer_note || "") + "</textarea></div>" +
      '<div class="field"><label>STRIPE PAYMENT LINK (OPTIONAL)</label><input name="payment_link" placeholder="https://buy.stripe.com/..."></div>';
    renderRepeatable("rep-items", "add-item", function (i) {
      return (
        '<div class="field-row" style="flex:1">' +
        '<div class="field col-6"><label>DESCRIPTION</label><input name="desc_' + i + '" placeholder="e.g. Flight ticket, Dubai to Kochi"></div>' +
        '<div class="field col-2"><label>QTY</label><input name="qty_' + i + '" type="number" min="1" value="1"></div>' +
        '<div class="field col-4"><label>UNIT PRICE</label><input name="price_' + i + '" type="number" min="0" step="0.01" value="0"></div>' +
        "</div>"
      );
    }, 1);
  }
  function gatherInvoice(form) {
    const items = rowsOf("rep-items").map(function (row) {
      const idx = row.dataset.index;
      return {
        description: fieldVal(row, "desc_" + idx),
        qty: parseFloat(fieldVal(row, "qty_" + idx)) || 1,
        unit_price: parseFloat(fieldVal(row, "price_" + idx)) || 0
      };
    }).filter(function (it) { return it.description; });
    const currency = (form.currency.value || "AED").toUpperCase();
    const total = items.reduce(function (s, it) { return s + it.qty * it.unit_price; }, 0);
    return {
      customer_name: form.customer_name.value.trim(),
      customer_email: form.customer_email.value.trim(),
      invoice_date: form.invoice_date.value || todayISO(),
      currency: currency,
      items: items,
      total: total,
      notes: form.notes.value.trim(),
      payment_link: form.payment_link.value.trim()
    };
  }
  function renderInvoice(data, docNumber) {
    const rows = data.items.map(function (it) {
      return "<tr><td>" + esc(it.description) + "</td><td>" + it.qty + "</td><td>" + money(it.unit_price, data.currency) + "</td><td>" + money(it.qty * it.unit_price, data.currency) + "</td></tr>";
    }).join("");
    return (
      letterheadHTML("Invoice", docNumber, data.invoice_date) +
      '<div class="kv"><span class="k">Bill to</span><span class="v">' + esc(data.customer_name) + "</span>" +
        (data.customer_email ? '<span class="k">Email</span><span class="v">' + esc(data.customer_email) + "</span>" : "") +
        (linkedEnquiry ? '<span class="k">Reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>" +
      "<h2>Charges</h2>" +
      "<table><thead><tr><th>Description</th><th>Qty</th><th>Unit price</th><th>Amount</th></tr></thead><tbody>" + rows + "</tbody></table>" +
      '<table class="totals" style="max-width:340px;margin-left:auto;margin-top:0.4rem">' +
        '<tr class="grand"><td class="label">Total due</td><td>' + money(data.total, data.currency) + "</td></tr>" +
      "</table>" +
      (data.payment_link ? '<div class="box"><b style="font-family:Arial,sans-serif;font-size:0.8rem">Pay online</b><p class="note" style="margin:0.4rem 0 0">' + esc(data.payment_link) + "</p></div>" : "") +
      bankBoxHTML() +
      (data.notes ? "<h2>Notes</h2><p class='note'>" + nl2br(data.notes) + "</p>" : "")
    );
  }

  /* ---- Flight e-ticket (one-way / round-trip / multi-city share the same builder, leg count differs) ---- */
  function buildFormFlight(mount, legCount) {
    mount.innerHTML =
      '<div id="rep-legs"></div>' +
      (legCount === "multi" ? '<button type="button" id="add-item" class="btn btn-outline" style="margin-top:0.5rem">+ Add flight leg</button>' : "") +
      '<div class="field-row" style="margin-top:1rem">' +
        '<div class="field col-6"><label>PASSENGER NAME(S), ONE PER LINE</label><textarea name="passengers">' + esc(prefillName()) + "</textarea></div>" +
        '<div class="field col-3"><label>CLASS</label><input name="cabin" value="Economy"></div>' +
        '<div class="field col-3"><label>BAGGAGE</label><input name="baggage" placeholder="e.g. 20kg checked + 7kg cabin"></div>' +
        '<div class="field col-6"><label>AIRLINE PNR / BOOKING REF</label><input name="pnr"></div>' +
      "</div>";
    const initial = legCount === "round" ? 2 : 1;
    renderRepeatable("rep-legs", "add-item", function (i) {
      return (
        '<div class="field-row" style="flex:1">' +
        '<div class="field col-3"><label>AIRLINE</label><input name="airline_' + i + '"></div>' +
        '<div class="field col-3"><label>FLIGHT NO.</label><input name="flightno_' + i + '"></div>' +
        '<div class="field col-3"><label>FROM</label><input name="from_' + i + '" placeholder="Dubai (DXB)"></div>' +
        '<div class="field col-3"><label>TO</label><input name="to_' + i + '" placeholder="Kochi (COK)"></div>' +
        '<div class="field col-4"><label>DATE</label><input name="date_' + i + '" type="date"></div>' +
        '<div class="field col-4"><label>DEPART</label><input name="deptime_' + i + '" type="time"></div>' +
        '<div class="field col-4"><label>ARRIVE</label><input name="arrtime_' + i + '" type="time"></div>' +
        "</div>"
      );
    }, legCount === "multi" ? 2 : initial);
  }
  function gatherFlight(form) {
    const legs = rowsOf("rep-legs").map(function (row) {
      const idx = row.dataset.index;
      return {
        airline: fieldVal(row, "airline_" + idx),
        flightno: fieldVal(row, "flightno_" + idx),
        from: fieldVal(row, "from_" + idx),
        to: fieldVal(row, "to_" + idx),
        date: fieldVal(row, "date_" + idx),
        deptime: fieldVal(row, "deptime_" + idx),
        arrtime: fieldVal(row, "arrtime_" + idx)
      };
    }).filter(function (l) { return l.from || l.to; });
    return {
      legs: legs,
      passengers: form.passengers.value.trim(),
      cabin: form.cabin.value.trim(),
      baggage: form.baggage.value.trim(),
      pnr: form.pnr.value.trim()
    };
  }
  function renderFlight(data, docNumber, tripLabel) {
    const legRows = data.legs.map(function (l, i) {
      return (
        "<tr><td>" + (i + 1) + "</td><td>" + esc(l.airline) + " " + esc(l.flightno) + "</td><td>" + esc(l.from) + " &rarr; " + esc(l.to) +
        "</td><td>" + fmtDate(l.date) + "</td><td>" + esc(l.deptime) + " &ndash; " + esc(l.arrtime) + "</td></tr>"
      );
    }).join("");
    return (
      letterheadHTML("E-Ticket — " + tripLabel + " Flight", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Passenger(s)</span><span class="v">' + nl2br(data.passengers) + "</span>" +
        '<span class="k">Class</span><span class="v">' + esc(data.cabin) + "</span>" +
        (data.baggage ? '<span class="k">Baggage</span><span class="v">' + esc(data.baggage) + "</span>" : "") +
        (data.pnr ? '<span class="k">Airline PNR</span><span class="v">' + esc(data.pnr) + "</span>" : "") +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>" +
      "<h2>Flight details</h2>" +
      "<table><thead><tr><th>Leg</th><th>Flight</th><th>Route</th><th>Date</th><th>Time</th></tr></thead><tbody>" + legRows + "</tbody></table>" +
      '<div class="box"><p class="note" style="margin:0">Please arrive at the airport at least 3 hours before departure for international flights. Carry a valid passport/visa as required for your destination. Contact Kridiya Travel immediately if any flight time changes.</p></div>'
    );
  }

  /* ---- Hotel e-ticket ---- */
  function buildFormHotel(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>HOTEL NAME</label><input name="hotel_name"></div>' +
        '<div class="field col-6"><label>HOTEL ADDRESS / CITY</label><input name="hotel_address"></div>' +
        '<div class="field col-3"><label>CHECK-IN</label><input name="checkin" type="date"></div>' +
        '<div class="field col-3"><label>CHECK-OUT</label><input name="checkout" type="date"></div>' +
        '<div class="field col-3"><label>ROOM TYPE</label><input name="room_type"></div>' +
        '<div class="field col-3"><label>MEAL PLAN</label><input name="meal_plan" placeholder="e.g. Breakfast included"></div>' +
        '<div class="field col-6"><label>GUEST NAME(S), ONE PER LINE</label><textarea name="guests">' + esc(prefillName()) + "</textarea></div>" +
        '<div class="field col-6"><label>HOTEL CONFIRMATION NUMBER</label><input name="confirmation_no"></div>' +
      "</div>";
  }
  function gatherHotel(form) {
    return {
      hotel_name: form.hotel_name.value.trim(),
      hotel_address: form.hotel_address.value.trim(),
      checkin: form.checkin.value,
      checkout: form.checkout.value,
      room_type: form.room_type.value.trim(),
      meal_plan: form.meal_plan.value.trim(),
      guests: form.guests.value.trim(),
      confirmation_no: form.confirmation_no.value.trim()
    };
  }
  function renderHotel(data, docNumber) {
    const nights = (data.checkin && data.checkout)
      ? Math.max(1, Math.round((new Date(data.checkout) - new Date(data.checkin)) / 86400000))
      : "";
    return (
      letterheadHTML("E-Ticket — Hotel Voucher", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Hotel</span><span class="v">' + esc(data.hotel_name) + "</span>" +
        (data.hotel_address ? '<span class="k">Address</span><span class="v">' + esc(data.hotel_address) + "</span>" : "") +
        '<span class="k">Check-in</span><span class="v">' + fmtDate(data.checkin) + "</span>" +
        '<span class="k">Check-out</span><span class="v">' + fmtDate(data.checkout) + (nights ? " (" + nights + " night" + (nights === 1 ? "" : "s") + ")" : "") + "</span>" +
        (data.room_type ? '<span class="k">Room type</span><span class="v">' + esc(data.room_type) + "</span>" : "") +
        (data.meal_plan ? '<span class="k">Meal plan</span><span class="v">' + esc(data.meal_plan) + "</span>" : "") +
        '<span class="k">Guest(s)</span><span class="v">' + nl2br(data.guests) + "</span>" +
        (data.confirmation_no ? '<span class="k">Confirmation no.</span><span class="v">' + esc(data.confirmation_no) + "</span>" : "") +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>" +
      '<div class="box"><p class="note" style="margin:0">Please present this voucher along with a valid ID/passport at check-in. Contact Kridiya Travel for any changes to this reservation.</p></div>'
    );
  }

  /* ---- Visa e-ticket (confirmation) ---- */
  function buildFormVisa(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>VISA TYPE</label><input name="visa_type" placeholder="e.g. Tourist Visa, 30 days"></div>' +
        '<div class="field col-6"><label>DESTINATION COUNTRY</label><input name="country"></div>' +
        '<div class="field col-6"><label>APPLICANT NAME(S), ONE PER LINE</label><textarea name="applicants">' + esc(prefillName()) + "</textarea></div>" +
        '<div class="field col-6"><label>PASSPORT NUMBER(S)</label><textarea name="passport_nos"></textarea></div>' +
        '<div class="field col-3"><label>VALID FROM</label><input name="valid_from" type="date"></div>' +
        '<div class="field col-3"><label>VALID TO</label><input name="valid_to" type="date"></div>' +
        '<div class="field col-3"><label>ENTRY TYPE</label><input name="entry_type" placeholder="Single / Multiple"></div>' +
        '<div class="field col-3"><label>VISA FILE / REFERENCE NO.</label><input name="visa_ref"></div>' +
      "</div>";
  }
  function gatherVisa(form) {
    return {
      visa_type: form.visa_type.value.trim(),
      country: form.country.value.trim(),
      applicants: form.applicants.value.trim(),
      passport_nos: form.passport_nos.value.trim(),
      valid_from: form.valid_from.value,
      valid_to: form.valid_to.value,
      entry_type: form.entry_type.value.trim(),
      visa_ref: form.visa_ref.value.trim()
    };
  }
  function renderVisa(data, docNumber) {
    return (
      letterheadHTML("E-Ticket — Visa Confirmation", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Visa type</span><span class="v">' + esc(data.visa_type) + "</span>" +
        '<span class="k">Destination</span><span class="v">' + esc(data.country) + "</span>" +
        '<span class="k">Applicant(s)</span><span class="v">' + nl2br(data.applicants) + "</span>" +
        (data.passport_nos ? '<span class="k">Passport no.</span><span class="v">' + nl2br(data.passport_nos) + "</span>" : "") +
        '<span class="k">Valid</span><span class="v">' + fmtDate(data.valid_from) + " &ndash; " + fmtDate(data.valid_to) + "</span>" +
        (data.entry_type ? '<span class="k">Entry type</span><span class="v">' + esc(data.entry_type) + "</span>" : "") +
        (data.visa_ref ? '<span class="k">Visa reference</span><span class="v">' + esc(data.visa_ref) + "</span>" : "") +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>" +
      '<div class="box"><p class="note" style="margin:0">Please check all details against your passport before travel. Visa conditions are set by the destination country\'s authorities, not Kridiya Travel.</p></div>'
    );
  }

  /* ---- Holiday / Umrah / Cruise e-tickets ---- */
  function buildFormHoliday(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>DESTINATION</label><input name="destination"></div>' +
        '<div class="field col-3"><label>TRAVEL START</label><input name="date_from" type="date"></div>' +
        '<div class="field col-3"><label>TRAVEL END</label><input name="date_to" type="date"></div>' +
        '<div class="field col-6"><label>HOTEL(S)</label><input name="hotels"></div>' +
        '<div class="field col-6"><label>INCLUSIONS</label><input name="inclusions" placeholder="Flights, transfers, breakfast, tours…"></div>' +
        '<div class="field col-12"><label>TRAVELLER NAME(S), ONE PER LINE</label><textarea name="travellers">' + esc(prefillName()) + "</textarea></div>" +
      "</div>";
  }
  function gatherHoliday(form) {
    return {
      destination: form.destination.value.trim(),
      date_from: form.date_from.value,
      date_to: form.date_to.value,
      hotels: form.hotels.value.trim(),
      inclusions: form.inclusions.value.trim(),
      travellers: form.travellers.value.trim()
    };
  }
  function renderHoliday(data, docNumber) {
    return (
      letterheadHTML("E-Ticket — Holiday Package", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Destination</span><span class="v">' + esc(data.destination) + "</span>" +
        '<span class="k">Dates</span><span class="v">' + fmtDate(data.date_from) + " &ndash; " + fmtDate(data.date_to) + "</span>" +
        (data.hotels ? '<span class="k">Hotel(s)</span><span class="v">' + esc(data.hotels) + "</span>" : "") +
        (data.inclusions ? '<span class="k">Inclusions</span><span class="v">' + esc(data.inclusions) + "</span>" : "") +
        '<span class="k">Traveller(s)</span><span class="v">' + nl2br(data.travellers) + "</span>" +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>"
    );
  }

  function buildFormUmrah(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>DEPARTURE CITY</label><input name="departure_city"></div>' +
        '<div class="field col-6"><label>TRANSPORT</label><input name="transport" placeholder="Bus / Flight"></div>' +
        '<div class="field col-3"><label>TRAVEL START</label><input name="date_from" type="date"></div>' +
        '<div class="field col-3"><label>TRAVEL END</label><input name="date_to" type="date"></div>' +
        '<div class="field col-3"><label>HOTEL — MAKKAH</label><input name="hotel_makkah"></div>' +
        '<div class="field col-3"><label>HOTEL — MADINAH</label><input name="hotel_madinah"></div>' +
        '<div class="field col-6"><label>ROOM TYPE</label><input name="room_type" placeholder="Quad / Triple / Double"></div>' +
        '<div class="field col-12"><label>PILGRIM NAME(S), ONE PER LINE</label><textarea name="pilgrims">' + esc(prefillName()) + "</textarea></div>" +
      "</div>";
  }
  function gatherUmrah(form) {
    return {
      departure_city: form.departure_city.value.trim(),
      transport: form.transport.value.trim(),
      date_from: form.date_from.value,
      date_to: form.date_to.value,
      hotel_makkah: form.hotel_makkah.value.trim(),
      hotel_madinah: form.hotel_madinah.value.trim(),
      room_type: form.room_type.value.trim(),
      pilgrims: form.pilgrims.value.trim()
    };
  }
  function renderUmrah(data, docNumber) {
    return (
      letterheadHTML("E-Ticket — Umrah Package", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Departure city</span><span class="v">' + esc(data.departure_city) + "</span>" +
        (data.transport ? '<span class="k">Transport</span><span class="v">' + esc(data.transport) + "</span>" : "") +
        '<span class="k">Dates</span><span class="v">' + fmtDate(data.date_from) + " &ndash; " + fmtDate(data.date_to) + "</span>" +
        (data.hotel_makkah ? '<span class="k">Hotel — Makkah</span><span class="v">' + esc(data.hotel_makkah) + "</span>" : "") +
        (data.hotel_madinah ? '<span class="k">Hotel — Madinah</span><span class="v">' + esc(data.hotel_madinah) + "</span>" : "") +
        (data.room_type ? '<span class="k">Room type</span><span class="v">' + esc(data.room_type) + "</span>" : "") +
        '<span class="k">Pilgrim(s)</span><span class="v">' + nl2br(data.pilgrims) + "</span>" +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>"
    );
  }

  function buildFormCruise(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>CRUISE LINE</label><input name="cruise_line"></div>' +
        '<div class="field col-6"><label>SHIP NAME</label><input name="ship_name"></div>' +
        '<div class="field col-3"><label>SAILING DATE</label><input name="sail_date" type="date"></div>' +
        '<div class="field col-3"><label>CABIN TYPE</label><input name="cabin_type"></div>' +
        '<div class="field col-12"><label>ITINERARY / PORTS</label><input name="itinerary"></div>' +
        '<div class="field col-12"><label>GUEST NAME(S), ONE PER LINE</label><textarea name="guests">' + esc(prefillName()) + "</textarea></div>" +
      "</div>";
  }
  function gatherCruise(form) {
    return {
      cruise_line: form.cruise_line.value.trim(),
      ship_name: form.ship_name.value.trim(),
      sail_date: form.sail_date.value,
      cabin_type: form.cabin_type.value.trim(),
      itinerary: form.itinerary.value.trim(),
      guests: form.guests.value.trim()
    };
  }
  function renderCruise(data, docNumber) {
    return (
      letterheadHTML("E-Ticket — Cruise Package", docNumber, todayISO()) +
      '<div class="kv"><span class="k">Cruise line</span><span class="v">' + esc(data.cruise_line) + "</span>" +
        (data.ship_name ? '<span class="k">Ship</span><span class="v">' + esc(data.ship_name) + "</span>" : "") +
        '<span class="k">Sailing date</span><span class="v">' + fmtDate(data.sail_date) + "</span>" +
        (data.cabin_type ? '<span class="k">Cabin type</span><span class="v">' + esc(data.cabin_type) + "</span>" : "") +
        (data.itinerary ? '<span class="k">Itinerary</span><span class="v">' + esc(data.itinerary) + "</span>" : "") +
        '<span class="k">Guest(s)</span><span class="v">' + nl2br(data.guests) + "</span>" +
        (linkedEnquiry ? '<span class="k">Kridiya reference</span><span class="v">' + esc(linkedEnquiry.reference) + "</span>" : "") +
      "</div>"
    );
  }

  /* ---- Cancellation notice ---- */
  function buildFormCancellation(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>CUSTOMER NAME</label><input name="customer_name" required value="' + esc(prefillName()) + '"></div>' +
        '<div class="field col-6"><label>ORIGINAL BOOKING / INVOICE REFERENCE</label><input name="original_ref" value="' + esc(prefillRef()) + '"></div>' +
        '<div class="field col-12"><label>WHAT IS BEING CANCELLED</label><textarea name="what_cancelled" placeholder="e.g. Flight ticket DXB-COK-DXB, 2 adults"></textarea></div>' +
        '<div class="field col-4"><label>CANCELLATION DATE</label><input name="cancel_date" type="date" value="' + todayISO() + '"></div>' +
        '<div class="field col-4"><label>REFUND AMOUNT</label><input name="refund_amount" type="number" min="0" step="0.01"></div>' +
        '<div class="field col-4"><label>CURRENCY</label><input name="currency" value="AED" maxlength="3" style="text-transform:uppercase"></div>' +
        '<div class="field col-6"><label>REFUND METHOD</label><input name="refund_method" placeholder="e.g. Original payment method, bank transfer"></div>' +
        '<div class="field col-6"><label>EXPECTED REFUND TIMEFRAME</label><input name="refund_timeframe" placeholder="e.g. 7-14 business days"></div>' +
        '<div class="field col-6"><label>CANCELLATION FEE (IF ANY)</label><input name="cancel_fee" type="number" min="0" step="0.01"></div>' +
        '<div class="field col-12"><label>NOTES</label><textarea name="notes"></textarea></div>' +
      "</div>";
  }
  function gatherCancellation(form) {
    return {
      customer_name: form.customer_name.value.trim(),
      original_ref: form.original_ref.value.trim(),
      what_cancelled: form.what_cancelled.value.trim(),
      cancel_date: form.cancel_date.value || todayISO(),
      refund_amount: form.refund_amount.value ? parseFloat(form.refund_amount.value) : null,
      currency: (form.currency.value || "AED").toUpperCase(),
      refund_method: form.refund_method.value.trim(),
      refund_timeframe: form.refund_timeframe.value.trim(),
      cancel_fee: form.cancel_fee.value ? parseFloat(form.cancel_fee.value) : null,
      notes: form.notes.value.trim()
    };
  }
  function renderCancellation(data, docNumber) {
    return (
      letterheadHTML("Cancellation Notice", docNumber, data.cancel_date) +
      '<div class="kv"><span class="k">Customer</span><span class="v">' + esc(data.customer_name) + "</span>" +
        (data.original_ref ? '<span class="k">Original reference</span><span class="v">' + esc(data.original_ref) + "</span>" : "") +
      "</div>" +
      "<h2>Cancelled</h2><p class='note'>" + nl2br(data.what_cancelled) + "</p>" +
      "<h2>Refund</h2>" +
      '<div class="kv">' +
        (data.refund_amount != null
          ? '<span class="k">Refund amount</span><span class="v">' + money(data.refund_amount, data.currency) + "</span>"
          : '<span class="k">Refund amount</span><span class="v">Non-refundable</span>') +
        (data.refund_method ? '<span class="k">Refund method</span><span class="v">' + esc(data.refund_method) + "</span>" : "") +
        (data.refund_timeframe ? '<span class="k">Expected timeframe</span><span class="v">' + esc(data.refund_timeframe) + "</span>" : "") +
        (data.cancel_fee ? '<span class="k">Cancellation fee</span><span class="v">' + money(data.cancel_fee, data.currency) + "</span>" : "") +
      "</div>" +
      (data.notes ? "<h2>Notes</h2><p class='note'>" + nl2br(data.notes) + "</p>" : "")
    );
  }

  /* ---- Visa rejection notice ---- */
  function buildFormRejection(mount) {
    mount.innerHTML =
      '<div class="field-row">' +
        '<div class="field col-6"><label>APPLICANT NAME(S)</label><textarea name="applicants">' + esc(prefillName()) + "</textarea></div>" +
        '<div class="field col-6"><label>VISA TYPE / DESTINATION</label><input name="visa_type"></div>' +
        '<div class="field col-6"><label>APPLICATION REFERENCE</label><input name="application_ref" value="' + esc(prefillRef()) + '"></div>' +
        '<div class="field col-6"><label>REJECTION DATE</label><input name="rejection_date" type="date" value="' + todayISO() + '"></div>' +
        '<div class="field col-12"><label>REASON GIVEN BY EMBASSY/AUTHORITY</label><textarea name="reason" placeholder="As communicated to us — paste it as given"></textarea></div>' +
        '<div class="field col-12"><label>NEXT STEPS FOR THE CUSTOMER</label><textarea name="next_steps">We can help you reapply with a stronger file, or advise on alternative visa options. Please contact us to discuss the best next step for your situation.</textarea></div>' +
        '<div class="field col-12"><label>FEE / REFUND NOTE</label><textarea name="fee_note">Embassy/government fees are set and collected by the relevant authority and are non-refundable once submitted. Our service fee is handled per our standard terms.</textarea></div>' +
      "</div>";
  }
  function gatherRejection(form) {
    return {
      applicants: form.applicants.value.trim(),
      visa_type: form.visa_type.value.trim(),
      application_ref: form.application_ref.value.trim(),
      rejection_date: form.rejection_date.value || todayISO(),
      reason: form.reason.value.trim(),
      next_steps: form.next_steps.value.trim(),
      fee_note: form.fee_note.value.trim()
    };
  }
  function renderRejection(data, docNumber) {
    return (
      letterheadHTML("Visa Application Update", docNumber, data.rejection_date) +
      '<div class="kv"><span class="k">Applicant(s)</span><span class="v">' + nl2br(data.applicants) + "</span>" +
        (data.visa_type ? '<span class="k">Visa type</span><span class="v">' + esc(data.visa_type) + "</span>" : "") +
        (data.application_ref ? '<span class="k">Application reference</span><span class="v">' + esc(data.application_ref) + "</span>" : "") +
      "</div>" +
      '<p class="note">We\'re sorry to let you know that this visa application was not approved.</p>' +
      (data.reason ? "<h2>Reason provided</h2><p class='note'>" + nl2br(data.reason) + "</p>" : "") +
      "<h2>What happens next</h2><p class='note'>" + nl2br(data.next_steps) + "</p>" +
      "<h2>Fees</h2><p class='note'>" + nl2br(data.fee_note) + "</p>"
    );
  }

  /* ================= Kind registry: form builder + gather + render ================= */
  const HANDLERS = {
    invoice: { build: buildFormInvoice, gather: gatherInvoice, render: function (d, n) { return renderInvoice(d, n); } },
    eticket_flight_oneway: { build: function (m) { buildFormFlight(m, "one"); }, gather: gatherFlight, render: function (d, n) { return renderFlight(d, n, "One-way"); } },
    eticket_flight_roundtrip: { build: function (m) { buildFormFlight(m, "round"); }, gather: gatherFlight, render: function (d, n) { return renderFlight(d, n, "Round-trip"); } },
    eticket_flight_multicity: { build: function (m) { buildFormFlight(m, "multi"); }, gather: gatherFlight, render: function (d, n) { return renderFlight(d, n, "Multi-city"); } },
    eticket_hotel: { build: buildFormHotel, gather: gatherHotel, render: renderHotel },
    eticket_visa: { build: buildFormVisa, gather: gatherVisa, render: renderVisa },
    eticket_holiday: { build: buildFormHoliday, gather: gatherHoliday, render: renderHoliday },
    eticket_umrah: { build: buildFormUmrah, gather: gatherUmrah, render: renderUmrah },
    eticket_cruise: { build: buildFormCruise, gather: gatherCruise, render: renderCruise },
    cancellation: { build: buildFormCancellation, gather: gatherCancellation, render: renderCancellation },
    visa_rejection: { build: buildFormRejection, gather: gatherRejection, render: renderRejection }
  };

  /* ================= Page wiring ================= */
  async function loadSettings() {
    const result = await sb.from("business_settings").select("*").eq("id", true).single();
    if (result.error) throw result.error;
    settings = result.data;
  }

  function populateSettingsForm() {
    const form = document.getElementById("settings-form");
    form.legal_name.value = settings.legal_name || "";
    form.trade_license_no.value = settings.trade_license_no || "";
    form.vat_registered.value = settings.vat_registered ? "true" : "false";
    form.trn.value = settings.trn || "";
    form.bank_name.value = settings.bank_name || "";
    form.bank_account_name.value = settings.bank_account_name || "";
    form.bank_iban.value = settings.bank_iban || "";
    form.bank_swift.value = settings.bank_swift || "";
    form.cancellation_policy.value = settings.cancellation_policy || "";
    form.invoice_footer_note.value = settings.invoice_footer_note || "";
  }

  async function saveSettings() {
    const form = document.getElementById("settings-form");
    const btn = document.getElementById("settings-save");
    btn.disabled = true;
    const update = {
      legal_name: form.legal_name.value.trim() || "Kridiya Travel and Tourism FZ-LLC",
      trade_license_no: form.trade_license_no.value.trim() || null,
      vat_registered: form.vat_registered.value === "true",
      trn: form.trn.value.trim() || null,
      bank_name: form.bank_name.value.trim() || null,
      bank_account_name: form.bank_account_name.value.trim() || null,
      bank_iban: form.bank_iban.value.trim() || null,
      bank_swift: form.bank_swift.value.trim() || null,
      cancellation_policy: form.cancellation_policy.value.trim() || null,
      invoice_footer_note: form.invoice_footer_note.value.trim() || null
    };
    const result = await sb.from("business_settings").update(update).eq("id", true).select("*").single();
    btn.disabled = false;
    if (result.error) { toast("Could not save settings: " + result.error.message); return; }
    settings = result.data;
    toast("Business settings saved.");
  }

  async function searchEnquiries(query) {
    let q = sb.from("enquiries").select("id, reference, full_name, email, phone, service_type, summary").order("created_at", { ascending: false }).limit(15);
    if (query) q = q.or("reference.ilike.%" + query + "%,full_name.ilike.%" + query + "%");
    const result = await q;
    if (result.error) throw result.error;
    return result.data || [];
  }

  function renderKindOptions() {
    const sel = document.getElementById("doc-kind");
    sel.innerHTML = DOC_KINDS.map(function (k) { return '<option value="' + k.id + '">' + esc(k.label) + "</option>"; }).join("");
  }

  function rebuildForm() {
    const kindId = document.getElementById("doc-kind").value;
    const handler = HANDLERS[kindId];
    const mount = document.getElementById("doc-fields");
    handler.build(mount);
    document.getElementById("doc-preview").innerHTML = "";
    document.getElementById("save-print-btn").disabled = false;
  }

  async function handleGenerate() {
    const kindId = document.getElementById("doc-kind").value;
    const kind = findKind(kindId);
    const handler = HANDLERS[kindId];
    const form = document.getElementById("doc-fields");
    const data = handler.gather(form);

    const customerName = deriveCustomerName(kind, data);
    if (!customerName) {
      toast("Enter the customer's name first.");
      return;
    }

    const btn = document.getElementById("save-print-btn");
    btn.disabled = true;
    btn.textContent = "Saving…";
    try {
      const insertResult = await sb
        .from("documents")
        .insert({
          document_type: kind.docType,
          enquiry_id: linkedEnquiry ? linkedEnquiry.id : null,
          customer_name: customerName,
          customer_email: data.customer_email || prefillEmail() || null,
          amount_total: data.total != null ? data.total : null,
          currency: data.currency || "AED",
          payload: Object.assign({}, data, { kind: kindId, service: kind.service || null }),
          created_by: currentUserId
        })
        .select("*")
        .single();
      if (insertResult.error) throw insertResult.error;

      const doc = insertResult.data;
      const bodyHTML = handler.render(data, doc.document_number);
      const title = kind.label + " " + doc.document_number;
      showInlinePreview(title, bodyHTML);
      document.getElementById("doc-preview-number").textContent = doc.document_number;
      openPrintWindow(title, bodyHTML);
      toast(title + " saved.");
    } catch (err) {
      toast("Could not save document: " + err.message);
    }
    btn.disabled = false;
    btn.textContent = "Save & Print";
  }

  function buildSignatureHTML(name, title) {
    const logo = new URL("assets/logo.png", location.href).href;
    return (
      '<table cellpadding="0" cellspacing="0" border="0" style="font-family:Arial,Helvetica,sans-serif;color:#2b2b2b;border-collapse:collapse">' +
        "<tr>" +
          '<td style="padding-right:14px;border-right:2px solid #c9601c;vertical-align:middle">' +
            '<img src="' + logo + '" width="54" height="54" alt="Kridiya Travel" style="display:block;border:0">' +
          "</td>" +
          '<td style="padding-left:14px;vertical-align:middle">' +
            '<div style="font-size:15px;font-weight:700;color:#1a1a1a">' + esc(name) + "</div>" +
            '<div style="font-size:12.5px;color:#a3480f;font-weight:600;margin-top:1px">' + esc(title) + " · " + esc(settings.legal_name) + "</div>" +
            '<div style="font-size:12px;color:#555;margin-top:6px;line-height:1.6">' +
              '<a href="tel:+971509413873" style="color:#555;text-decoration:none">+971 50 941 3873</a> &nbsp;&middot;&nbsp; ' +
              '<a href="mailto:info@kridiyatravel.com" style="color:#555;text-decoration:none">info@kridiyatravel.com</a> &nbsp;&middot;&nbsp; ' +
              '<a href="https://kridiyatravel.com" style="color:#555;text-decoration:none">kridiyatravel.com</a>' +
              "<br>Ras Al Khaimah, United Arab Emirates" +
            "</div>" +
            '<div style="font-size:11px;color:#999;margin-top:6px">' +
              '<a href="https://www.instagram.com/kridiyatravel" style="color:#999;text-decoration:none">Instagram</a> &nbsp;&middot;&nbsp; ' +
              '<a href="https://www.facebook.com/profile.php?id=61592086520680" style="color:#999;text-decoration:none">Facebook</a>' +
            "</div>" +
          "</td>" +
        "</tr>" +
      "</table>"
    );
  }

  document.addEventListener("DOMContentLoaded", async function () {
    const gate = document.getElementById("doc-gate");
    const app = document.getElementById("doc-app");

    const user = await KridiyaAuth.currentUser();
    if (!user) { location.replace("login.html?next=documents.html"); return; }
    currentUserId = user.id;

    sb = await KridiyaAuth.client();
    let staff = false;
    try {
      const check = await sb.rpc("is_staff");
      staff = !check.error && check.data === true;
    } catch (e) { staff = false; }

    if (!staff) {
      gate.innerHTML = '<div class="account-main empty-state"><p><b>You do not have access to this page.</b><br>Documents are for Kridiya Travel staff only.</p><a class="btn btn-primary" href="account.html">Back to my account</a></div>';
      return;
    }

    try {
      await loadSettings();
    } catch (err) {
      gate.innerHTML = '<div class="account-main empty-state"><p>Could not load business settings: ' + esc(err.message) + "</p></div>";
      return;
    }

    gate.hidden = true;
    app.hidden = false;
    renderKindOptions();

    document.getElementById("settings-toggle").addEventListener("click", function () {
      const form = document.getElementById("settings-form");
      const opening = form.hidden;
      if (opening) populateSettingsForm();
      form.hidden = !opening;
      this.textContent = opening ? "Hide" : "Edit";
    });
    document.getElementById("settings-save").addEventListener("click", saveSettings);

    document.getElementById("sig-build").addEventListener("click", function () {
      const name = document.getElementById("sig-name").value.trim() || "Kridiya Travel";
      const title = document.getElementById("sig-title").value.trim() || "Travel Consultant";
      const html = buildSignatureHTML(name, title);
      document.getElementById("sig-preview").innerHTML = html;
      document.getElementById("sig-preview-wrap").hidden = false;
    });
    document.getElementById("sig-copy").addEventListener("click", async function () {
      const html = document.getElementById("sig-preview").innerHTML;
      try {
        const item = new ClipboardItem({ "text/html": new Blob([html], { type: "text/html" }) });
        await navigator.clipboard.write([item]);
        toast("Signature copied — paste it into Outlook.");
      } catch (e) {
        try {
          await navigator.clipboard.writeText(html);
          toast("Copied as HTML source — paste into an HTML editor if formatting is lost.");
        } catch (e2) {
          toast("Could not copy automatically — select the signature above and copy manually.");
        }
      }
    });

    const p = new URLSearchParams(location.search);
    const enquiryId = p.get("enquiry");
    if (enquiryId) {
      const result = await sb.from("enquiries").select("id, reference, full_name, email, phone, service_type, summary").eq("id", enquiryId).maybeSingle();
      if (result.data) {
        linkedEnquiry = result.data;
        document.getElementById("linked-enquiry-box").innerHTML =
          "Linked to <b>" + esc(linkedEnquiry.reference) + "</b> — " + esc(linkedEnquiry.full_name) + " (" + esc(linkedEnquiry.summary || linkedEnquiry.service_type) + ")";
        document.getElementById("linked-enquiry-box").hidden = false;
      }
    }

    rebuildForm();
    document.getElementById("doc-kind").addEventListener("change", rebuildForm);
    document.getElementById("save-print-btn").addEventListener("click", handleGenerate);

    const searchInput = document.getElementById("enquiry-search");
    const searchResults = document.getElementById("enquiry-search-results");
    let searchTimer = null;
    searchInput.addEventListener("input", function () {
      clearTimeout(searchTimer);
      const q = searchInput.value.trim();
      searchTimer = setTimeout(async function () {
        const rows = await searchEnquiries(q);
        searchResults.innerHTML = rows.map(function (r) {
          return '<button type="button" class="search-hit" data-id="' + r.id + '">' + esc(r.reference) + " — " + esc(r.full_name) + '<span class="form-note">' + esc(r.summary || r.service_type) + "</span></button>";
        }).join("") || '<p class="form-note">No matches.</p>';
      }, 250);
    });
    searchResults.addEventListener("click", function (e) {
      const btn = e.target.closest(".search-hit");
      if (!btn) return;
      searchEnquiries("").then(function () {});
      sb.from("enquiries").select("id, reference, full_name, email, phone, service_type, summary").eq("id", btn.dataset.id).maybeSingle().then(function (result) {
        if (!result.data) return;
        linkedEnquiry = result.data;
        document.getElementById("linked-enquiry-box").innerHTML =
          "Linked to <b>" + esc(linkedEnquiry.reference) + "</b> — " + esc(linkedEnquiry.full_name) + " (" + esc(linkedEnquiry.summary || linkedEnquiry.service_type) + ")";
        document.getElementById("linked-enquiry-box").hidden = false;
        searchResults.innerHTML = "";
        searchInput.value = "";
        rebuildForm();
      });
    });
    document.getElementById("unlink-enquiry").addEventListener("click", function () {
      linkedEnquiry = null;
      document.getElementById("linked-enquiry-box").hidden = true;
      rebuildForm();
    });
  });
})();
