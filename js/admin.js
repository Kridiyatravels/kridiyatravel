/* ============================================================
   Kridiya Travel — staff enquiry admin (admin.html only)
   Read/write access is enforced server-side by RLS (public.is_staff());
   this page just renders what Supabase allows the signed-in user to see.
   ============================================================ */
"use strict";

(function () {
  if (document.body.dataset.page !== "admin") return;

  const STATUS_OPTIONS = [
    "received", "checking_availability", "quote_sent", "confirmed",
    "payment_pending", "booked", "documents_sent", "closed"
  ];
  const SERVICE_OPTIONS = ["flight", "hotel", "holiday", "visa", "umrah", "cruise", "other"];

  let sb = null;
  let currentStaffId = null;
  let allEnquiries = [];
  let notesByEnquiry = {};
  let requestsByEnquiry = {};
  let quotesByEnquiry = {};

  function fmtMoney(amount, currency) {
    return currency + " " + Number(amount).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  function fmtWhen(iso) {
    if (!iso) return "";
    return new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  }

  function waReplyLink(enq) {
    const phone = String(enq.phone || "").replace(/[^0-9]/g, "");
    if (!phone) return "";
    const firstName = enq.full_name ? enq.full_name.split(" ")[0] : "there";
    const text = "Hello " + firstName + ", this is Kridiya Travel. Following up on your enquiry " +
      enq.reference + " (" + enq.summary + ").";
    return "https://wa.me/" + phone + "?text=" + encodeURIComponent(text);
  }

  function mailReplyLink(enq) {
    const firstName = enq.full_name ? enq.full_name.split(" ")[0] : "";
    const subject = "Re: " + enq.reference + " — your Kridiya Travel enquiry";
    const body = "Hi " + firstName + ",\n\nThanks for your enquiry (" + enq.summary + ").\n\n";
    return "mailto:" + encodeURIComponent(enq.email) + "?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(body);
  }

  function matchesFilters(enq) {
    const statusF = document.getElementById("flt-status").value;
    const serviceF = document.getElementById("flt-service").value;
    const todayOnly = document.getElementById("flt-today").checked;
    if (statusF && enq.status !== statusF) return false;
    if (serviceF && enq.service_type !== serviceF) return false;
    if (todayOnly && new Date(enq.created_at).toDateString() !== new Date().toDateString()) return false;
    return true;
  }

  function renderList() {
    const listEl = document.getElementById("admin-list");
    const visible = allEnquiries.filter(matchesFilters);
    document.getElementById("admin-count").textContent = visible.length + " of " + allEnquiries.length + " enquiries";

    if (!visible.length) {
      listEl.innerHTML = '<div class="account-main empty-state"><p>No enquiries match these filters.</p></div>';
      return;
    }

    listEl.innerHTML = visible.map(function (enq) {
      const created = new Date(enq.created_at);
      const notes = notesByEnquiry[enq.id] || [];
      const requests = requestsByEnquiry[enq.id] || [];
      const quotes = quotesByEnquiry[enq.id] || [];
      const wa = waReplyLink(enq);
      return (
        '<div class="account-main admin-enq">' +
          '<div class="enq-top">' +
            '<div><b>' + KridiyaAuth.escapeHTML(enq.reference) + "</b> " +
              '<span class="admin-badge">' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(enq.service_type)) + "</span></div>" +
            '<time datetime="' + KridiyaAuth.escapeHTML(enq.created_at) + '">' +
              created.toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) +
            "</time>" +
          "</div>" +
          '<p style="margin:0.4rem 0 0.2rem"><b>' + KridiyaAuth.escapeHTML(enq.full_name) + "</b> · " +
            (enq.phone ? '<a href="tel:' + KridiyaAuth.escapeHTML(enq.phone) + '">' + KridiyaAuth.escapeHTML(enq.phone) + "</a> · " : "") +
            '<a href="mailto:' + KridiyaAuth.escapeHTML(enq.email) + '">' + KridiyaAuth.escapeHTML(enq.email) + "</a></p>" +
          '<p class="form-note" style="margin:0 0 0.8rem">' + KridiyaAuth.escapeHTML(enq.summary) + "</p>" +
          '<div class="admin-enq-actions">' +
            '<select class="status-select" data-id="' + enq.id + '">' +
              STATUS_OPTIONS.map(function (s) {
                return '<option value="' + s + '"' + (s === enq.status ? " selected" : "") + ">" + KridiyaAuth.statusLabel(s) + "</option>";
              }).join("") +
            "</select>" +
            (wa ? '<a class="btn btn-wa" target="_blank" rel="noopener" href="' + wa + '">' + icon("whatsapp") + " WhatsApp</a>" : "") +
            '<a class="btn btn-outline" href="' + mailReplyLink(enq) + '">' + icon("mail") + " Email</a>" +
            '<button type="button" class="btn btn-outline notes-toggle" data-id="' + enq.id + '">Notes (' + notes.length + ")</button>" +
            '<button type="button" class="btn btn-outline requests-toggle" data-id="' + enq.id + '">Requests (' + requests.length + ")</button>" +
            '<button type="button" class="btn btn-outline quotes-toggle" data-id="' + enq.id + '">Quote (' + quotes.length + ")</button>" +
            '<a class="btn btn-outline" href="documents.html?enquiry=' + enq.id + '">Document</a>' +
          "</div>" +
          '<div class="admin-notes" data-notes-for="' + enq.id + '" hidden>' +
            '<div class="admin-notes-list">' +
              (notes.length
                ? notes.map(function (n) {
                    return '<div class="admin-note"><p>' + KridiyaAuth.escapeHTML(n.note) + "</p><time>" +
                      new Date(n.created_at).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) +
                      "</time></div>";
                  }).join("")
                : '<p class="form-note">No internal notes yet.</p>') +
            "</div>" +
            '<form class="admin-note-form" data-id="' + enq.id + '">' +
              '<textarea placeholder="Add an internal note (staff only, customer never sees this)…" required></textarea>' +
              '<button class="btn btn-primary" type="submit">Add note</button>' +
            "</form>" +
          "</div>" +
          '<div class="admin-notes" data-requests-for="' + enq.id + '" hidden>' +
            '<div class="admin-notes-list">' +
              (requests.length
                ? requests.map(function (r) {
                    const answered = r.responded_at
                      ? (r.kind === "file"
                          ? (r.response_file_path
                              ? '<button type="button" class="btn btn-outline view-file-btn" data-path="' + KridiyaAuth.escapeHTML(r.response_file_path) + '">View file: ' + KridiyaAuth.escapeHTML(r.response_file_name || "uploaded file") + "</button>"
                              : '<span class="form-note">No file uploaded.</span>')
                          : '<p style="margin:0.3rem 0 0">' + KridiyaAuth.escapeHTML(r.response_text || "") + "</p>")
                      : '<span class="form-note">Waiting on customer.</span>';
                    return '<div class="admin-note"><p><b>' + KridiyaAuth.escapeHTML(r.label) + '</b> <span class="admin-badge">' + (r.kind === "file" ? "File" : "Text") + "</span></p>" + answered + "</div>";
                  }).join("")
                : '<p class="form-note">No requests sent yet.</p>') +
            "</div>" +
            '<form class="admin-request-form" data-id="' + enq.id + '">' +
              '<select name="kind"><option value="text">Text answer</option><option value="file">File upload</option></select>' +
              '<input name="label" type="text" placeholder="e.g. Passport number and expiry date" required style="flex:1 1 260px;min-height:44px;border:1px solid var(--line);border-radius:var(--r-sm);padding:0 0.7rem">' +
              '<button class="btn btn-primary" type="submit">Ask</button>' +
            "</form>" +
          "</div>" +
          '<div class="admin-notes" data-quotes-for="' + enq.id + '" hidden>' +
            '<div class="admin-notes-list">' +
              (quotes.length
                ? quotes.map(function (q) {
                    return '<div class="admin-note"><p><b>' + KridiyaAuth.escapeHTML(q.title) + "</b> — " + fmtMoney(q.price_amount, q.currency) +
                      ' <span class="admin-badge">' + KridiyaAuth.statusLabel(q.status) + "</span></p>" +
                      (q.valid_until ? '<p class="form-note" style="margin:0.2rem 0 0">Valid until ' + fmtWhen(q.valid_until) + "</p>" : "") +
                      "</div>";
                  }).join("")
                : '<p class="form-note">No quote sent yet.</p>') +
            "</div>" +
            '<form class="admin-quote-form" data-id="' + enq.id + '">' +
              '<input name="title" type="text" placeholder="e.g. Air India Express, 20kg baggage" required style="flex:1 1 220px;min-height:44px;border:1px solid var(--line);border-radius:var(--r-sm);padding:0 0.7rem">' +
              '<input name="price_amount" type="number" min="0" step="0.01" placeholder="Price" required style="width:120px;min-height:44px;border:1px solid var(--line);border-radius:var(--r-sm);padding:0 0.7rem">' +
              '<input name="currency" type="text" value="AED" maxlength="3" style="width:70px;min-height:44px;border:1px solid var(--line);border-radius:var(--r-sm);padding:0 0.7rem;text-transform:uppercase">' +
              '<input name="valid_until" type="datetime-local" style="min-height:44px;border:1px solid var(--line);border-radius:var(--r-sm);padding:0 0.5rem">' +
              '<textarea name="terms" placeholder="Terms (optional) — e.g. subject to seat availability until ticketed"></textarea>' +
              '<button class="btn btn-primary" type="submit">Send quote</button>' +
            "</form>" +
          "</div>" +
        "</div>"
      );
    }).join("");
  }

  async function loadEnquiries() {
    const result = await sb.from("enquiries").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    allEnquiries = result.data || [];
  }

  async function loadNotes() {
    const result = await sb.from("enquiry_notes").select("id, enquiry_id, note, created_at").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    notesByEnquiry = {};
    (result.data || []).forEach(function (n) {
      if (!notesByEnquiry[n.enquiry_id]) notesByEnquiry[n.enquiry_id] = [];
      notesByEnquiry[n.enquiry_id].push(n);
    });
  }

  async function loadRequests() {
    const result = await sb.from("enquiry_requests").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    requestsByEnquiry = {};
    (result.data || []).forEach(function (r) {
      if (!requestsByEnquiry[r.enquiry_id]) requestsByEnquiry[r.enquiry_id] = [];
      requestsByEnquiry[r.enquiry_id].push(r);
    });
  }

  async function loadQuotes() {
    const result = await sb.from("quotes").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    quotesByEnquiry = {};
    (result.data || []).forEach(function (q) {
      if (!quotesByEnquiry[q.enquiry_id]) quotesByEnquiry[q.enquiry_id] = [];
      quotesByEnquiry[q.enquiry_id].push(q);
    });
  }

  function populateFilterOptions() {
    const statusSel = document.getElementById("flt-status");
    STATUS_OPTIONS.forEach(function (s) {
      const opt = document.createElement("option");
      opt.value = s;
      opt.textContent = KridiyaAuth.statusLabel(s);
      statusSel.appendChild(opt);
    });
    const serviceSel = document.getElementById("flt-service");
    SERVICE_OPTIONS.forEach(function (s) {
      const opt = document.createElement("option");
      opt.value = s;
      opt.textContent = KridiyaAuth.statusLabel(s);
      serviceSel.appendChild(opt);
    });
  }

  function wireEvents() {
    ["flt-status", "flt-service", "flt-today"].forEach(function (id) {
      document.getElementById(id).addEventListener("change", renderList);
    });

    const listEl = document.getElementById("admin-list");

    listEl.addEventListener("change", async function (e) {
      if (!e.target.classList.contains("status-select")) return;
      const select = e.target;
      const id = select.dataset.id;
      const newStatus = select.value;
      select.disabled = true;
      const result = await sb.from("enquiries").update({ status: newStatus }).eq("id", id);
      select.disabled = false;
      if (result.error) {
        toast("Could not update status: " + result.error.message);
        return;
      }
      const row = allEnquiries.find(function (r) { return r.id === id; });
      if (row) row.status = newStatus;
      toast("Status updated.");
    });

    listEl.addEventListener("click", async function (e) {
      const notesBtn = e.target.closest(".notes-toggle");
      if (notesBtn) {
        const panel = listEl.querySelector('.admin-notes[data-notes-for="' + notesBtn.dataset.id + '"]');
        if (panel) panel.hidden = !panel.hidden;
        return;
      }
      const reqBtn = e.target.closest(".requests-toggle");
      if (reqBtn) {
        const panel = listEl.querySelector('.admin-notes[data-requests-for="' + reqBtn.dataset.id + '"]');
        if (panel) panel.hidden = !panel.hidden;
        return;
      }
      const quoteBtn = e.target.closest(".quotes-toggle");
      if (quoteBtn) {
        const panel = listEl.querySelector('.admin-notes[data-quotes-for="' + quoteBtn.dataset.id + '"]');
        if (panel) panel.hidden = !panel.hidden;
        return;
      }
      const viewBtn = e.target.closest(".view-file-btn");
      if (viewBtn) {
        viewBtn.disabled = true;
        const result = await sb.storage.from("enquiry-uploads").createSignedUrl(viewBtn.dataset.path, 120);
        viewBtn.disabled = false;
        if (result.error || !result.data) {
          toast("Could not open file: " + (result.error ? result.error.message : "unknown error"));
          return;
        }
        window.open(result.data.signedUrl, "_blank", "noopener");
      }
    });

    listEl.addEventListener("submit", async function (e) {
      const form = e.target.closest(".admin-note-form");
      if (!form) return;
      e.preventDefault();
      const textarea = form.querySelector("textarea");
      const note = textarea.value.trim();
      if (!note) return;
      const id = form.dataset.id;
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      const result = await sb
        .from("enquiry_notes")
        .insert({ enquiry_id: id, note: note, created_by: currentStaffId })
        .select("id, enquiry_id, note, created_at")
        .single();
      btn.disabled = false;
      if (result.error) {
        toast("Could not save note: " + result.error.message);
        return;
      }
      if (!notesByEnquiry[id]) notesByEnquiry[id] = [];
      notesByEnquiry[id].unshift(result.data);
      renderList();
      const panel = listEl.querySelector('.admin-notes[data-notes-for="' + id + '"]');
      if (panel) panel.hidden = false;
    });

    listEl.addEventListener("submit", async function (e) {
      const form = e.target.closest(".admin-request-form");
      if (!form) return;
      e.preventDefault();
      const id = form.dataset.id;
      const label = form.label.value.trim();
      if (!label) return;
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      const result = await sb
        .from("enquiry_requests")
        .insert({ enquiry_id: id, kind: form.kind.value, label: label, created_by: currentStaffId })
        .select("*")
        .single();
      btn.disabled = false;
      if (result.error) {
        toast("Could not send request: " + result.error.message);
        return;
      }
      if (!requestsByEnquiry[id]) requestsByEnquiry[id] = [];
      requestsByEnquiry[id].unshift(result.data);
      renderList();
      const panel = listEl.querySelector('.admin-notes[data-requests-for="' + id + '"]');
      if (panel) panel.hidden = false;
      toast("Request sent to customer.");
    });

    listEl.addEventListener("submit", async function (e) {
      const form = e.target.closest(".admin-quote-form");
      if (!form) return;
      e.preventDefault();
      const id = form.dataset.id;
      const title = form.title.value.trim();
      const price = parseFloat(form.price_amount.value);
      if (!title || !(price >= 0)) return;
      const currency = (form.currency.value || "AED").trim().toUpperCase();
      const validUntil = form.valid_until.value ? new Date(form.valid_until.value).toISOString() : null;
      const terms = form.terms.value.trim();
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      const result = await sb
        .from("quotes")
        .insert({
          enquiry_id: id,
          title: title,
          price_amount: price,
          currency: currency,
          valid_until: validUntil,
          terms: terms || null,
          created_by: currentStaffId
        })
        .select("*")
        .single();
      btn.disabled = false;
      if (result.error) {
        toast("Could not send quote: " + result.error.message);
        return;
      }
      if (!quotesByEnquiry[id]) quotesByEnquiry[id] = [];
      quotesByEnquiry[id].unshift(result.data);
      renderList();
      const panel = listEl.querySelector('.admin-notes[data-quotes-for="' + id + '"]');
      if (panel) panel.hidden = false;
      toast("Quote sent to customer.");
    });
  }

  document.addEventListener("DOMContentLoaded", async function () {
    const gate = document.getElementById("admin-gate");
    const app = document.getElementById("admin-app");

    const user = await KridiyaAuth.currentUser();
    if (!user) {
      location.replace("login.html?next=admin.html");
      return;
    }
    currentStaffId = user.id;

    sb = await KridiyaAuth.client();
    let staff = false;
    try {
      const check = await sb.rpc("is_staff");
      staff = !check.error && check.data === true;
    } catch (e) {
      staff = false;
    }

    if (!staff) {
      gate.innerHTML =
        '<div class="account-main empty-state">' +
          "<p><b>You do not have admin access.</b><br>This page is for Kridiya Travel staff only.</p>" +
          '<a class="btn btn-primary" href="account.html">Back to my account</a>' +
        "</div>";
      return;
    }

    try {
      await Promise.all([loadEnquiries(), loadNotes(), loadRequests(), loadQuotes()]);
    } catch (err) {
      gate.innerHTML = '<div class="account-main empty-state"><p>Could not load enquiries: ' + KridiyaAuth.escapeHTML(err.message) + "</p></div>";
      return;
    }

    populateFilterOptions();
    gate.hidden = true;
    app.hidden = false;
    renderList();
    wireEvents();
  });
})();
