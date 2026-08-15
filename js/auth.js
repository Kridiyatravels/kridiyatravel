/* ============================================================
   Kridiya Travel - customer accounts
   Supabase Auth + Postgres profiles/bookings.
   Browser-safe config only: never place secret/service_role keys here.
   ============================================================ */
"use strict";

window.KridiyaAuth = (function () {
  const SUPABASE_URL = "https://jmvqqpughlzeqrcyavwz.supabase.co";
  const SUPABASE_KEY = "sb_publishable_wiA9tSt74X-UQhW4yOXgIQ_lEUG1Q1Q";
  const SUPABASE_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
  const SESSION_KEY = "kridiya_session";
  const PUBLIC_SITE_URL = "https://www.kridiyatravel.com/";

  let clientPromise = null;
  let cachedClient = null;

  function cleanEmail(email) {
    return String(email || "").trim().toLowerCase();
  }

  function publicURL(path) {
    return new URL(path, PUBLIC_SITE_URL).href;
  }

  function nameFromProfile(profile, authUser) {
    return (
      (profile && profile.full_name) ||
      (authUser && authUser.user_metadata && (authUser.user_metadata.full_name || authUser.user_metadata.name)) ||
      (authUser && authUser.email && authUser.email.split("@")[0]) ||
      "Traveller"
    );
  }

  function session() {
    try {
      const raw = localStorage.getItem(SESSION_KEY) || sessionStorage.getItem(SESSION_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }

  function setSession(user) {
    const payload = JSON.stringify({
      id: user.id || "",
      email: user.email || "",
      name: user.name || "Traveller",
      phone: user.phone || "",
      createdAt: user.createdAt || new Date().toISOString(),
      at: Date.now()
    });
    localStorage.setItem(SESSION_KEY, payload);
    sessionStorage.removeItem(SESSION_KEY);
  }

  function clearSession() {
    localStorage.removeItem(SESSION_KEY);
    sessionStorage.removeItem(SESSION_KEY);
  }

  function loadSupabaseScript() {
    return new Promise(function (resolve, reject) {
      if (window.supabase && window.supabase.createClient) {
        resolve();
        return;
      }
      const existing = document.querySelector('script[data-supabase-js="true"]');
      if (existing) {
        existing.addEventListener("load", resolve, { once: true });
        existing.addEventListener("error", reject, { once: true });
        return;
      }
      const script = document.createElement("script");
      script.src = SUPABASE_CDN;
      script.async = true;
      script.dataset.supabaseJs = "true";
      script.onload = resolve;
      script.onerror = function () {
        reject(new Error("Could not load the secure account service. Please check your connection and try again."));
      };
      document.head.appendChild(script);
    });
  }

  async function client() {
    if (cachedClient) return cachedClient;
    if (!clientPromise) {
      clientPromise = loadSupabaseScript().then(function () {
        cachedClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true
          }
        });
        return cachedClient;
      });
    }
    return clientPromise;
  }

  async function profileFor(authUser) {
    if (!authUser) return null;
    const sb = await client();
    const result = await sb
      .from("profiles")
      .select("id, full_name, preferred_email, phone, whatsapp, preferred_currency, newsletter_opt_in, created_at")
      .eq("id", authUser.id)
      .maybeSingle();

    if (result.error) throw result.error;

    const profile = result.data || null;
    return {
      id: authUser.id,
      email: authUser.email || (profile && profile.preferred_email) || "",
      name: nameFromProfile(profile, authUser),
      phone: (profile && (profile.whatsapp || profile.phone)) || "",
      createdAt: (profile && profile.created_at) || authUser.created_at || new Date().toISOString()
    };
  }

  async function currentUser() {
    const sb = await client();
    const authResult = await sb.auth.getUser();
    if (authResult.error || !authResult.data || !authResult.data.user) {
      clearSession();
      return null;
    }
    const user = await profileFor(authResult.data.user);
    setSession(user);
    return user;
  }

  async function register(opts) {
    const sb = await client();
    const email = cleanEmail(opts.email);
    const name = String(opts.name || "").trim();
    const phone = String(opts.phone || "").trim();
    const result = await sb.auth.signUp({
      email: email,
      password: opts.password,
      options: {
        emailRedirectTo: publicURL("account.html"),
        data: {
          full_name: name,
          phone: phone,
          whatsapp: phone
        }
      }
    });

    if (result.error) throw result.error;

    const authUser = result.data && result.data.user;
    if (!result.data || !result.data.session) {
      clearSession();
      return {
        email: email,
        name: name,
        phone: phone,
        needsEmailConfirmation: true
      };
    }

    const user = await profileFor(authUser);
    setSession(user);
    return user;
  }

  async function login(email, password) {
    const sb = await client();
    const result = await sb.auth.signInWithPassword({
      email: cleanEmail(email),
      password: password
    });
    if (result.error) throw result.error;

    const user = await profileFor(result.data.user);
    setSession(user);
    return user;
  }

  async function logout() {
    try {
      const sb = await client();
      await sb.auth.signOut();
    } finally {
      clearSession();
    }
  }

  async function resetPassword(email) {
    const sb = await client();
    const result = await sb.auth.resetPasswordForEmail(cleanEmail(email), {
      redirectTo: publicURL("reset-password.html")
    });
    if (result.error) throw result.error;
  }

  async function completePasswordReset(nextPassword) {
    const sb = await client();
    const result = await sb.auth.updateUser({ password: nextPassword });
    if (result.error) throw result.error;
    await currentUser();
  }

  async function changePassword(email, current, next) {
    const sb = await client();
    const signIn = await sb.auth.signInWithPassword({
      email: cleanEmail(email),
      password: current
    });
    if (signIn.error) throw new Error("Your current password is incorrect.");

    const result = await sb.auth.updateUser({ password: next });
    if (result.error) throw result.error;
    await currentUser();
  }

  async function updateProfile(email, fields) {
    const user = await currentUser();
    if (!user) throw new Error("Please log in again.");

    const name = String(fields.name || "").trim();
    const phone = String(fields.phone || "").trim();
    const sb = await client();

    const result = await sb
      .from("profiles")
      .update({
        full_name: name,
        phone: phone,
        whatsapp: phone,
        preferred_email: cleanEmail(email || user.email)
      })
      .eq("id", user.id)
      .select("id, full_name, preferred_email, phone, whatsapp, created_at")
      .single();

    if (result.error) throw result.error;

    const updated = {
      id: user.id,
      email: user.email,
      name: result.data.full_name,
      phone: result.data.whatsapp || result.data.phone || "",
      createdAt: result.data.created_at || user.createdAt
    };
    setSession(updated);
    return updated;
  }

  async function listBookings() {
    const user = await currentUser();
    if (!user) return [];

    const sb = await client();
    const result = await sb
      .from("bookings")
      .select("id, booking_reference, service_type, title, route_or_destination, travel_start, travel_end, adults, children, infants, amount, currency, status, payment_status, document_status, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false });

    if (result.error) throw result.error;
    return result.data || [];
  }
  async function listBookingDocuments() {
    const user = await currentUser();
    if (!user) return [];
    const sb = await client();
    const result = await sb
      .from("booking_documents")
      .select("id, booking_id, document_type, file_name, storage_path, storage_provider, external_reference, visible_to_customer, created_at")
      .eq("user_id", user.id)
      .eq("visible_to_customer", true)
      .order("created_at", { ascending: false });
    if (result.error) return [];
    return result.data || [];
  }
  async function listCustomerPayments(bookingIds, enquiryIds) {
    const user = await currentUser();
    if (!user) return [];
    const ids = [];
    (bookingIds || []).forEach(function (id) { ids.push("booking_id.eq." + id); });
    (enquiryIds || []).forEach(function (id) { ids.push("enquiry_id.eq." + id); });
    if (!ids.length) return [];
    const sb = await client();
    const result = await sb
      .from("payments")
      .select("id, booking_id, enquiry_id, payment_reference, payment_direction, amount, currency, method, status, proof_file_name, proof_uploaded_at, proof_source, refund_amount, refund_reason, refund_method, refund_reference, refund_requested_at, refund_approved_at, refund_completed_at, created_at")
      .or(ids.join(","))
      .order("created_at", { ascending: false });
    if (result.error) return [];
    return result.data || [];
  }
  async function openBookingDocument(documentId, storagePath, storageProvider) {
    const user = await currentUser();
    if (!user) throw new Error("Please log in again.");
    if (!documentId || !storagePath) throw new Error("This document does not have a downloadable file yet.");
    const sb = await client();
    const check = await sb
      .from("booking_documents")
      .select("id, storage_path")
      .eq("id", documentId)
      .eq("user_id", user.id)
      .eq("visible_to_customer", true)
      .maybeSingle();
    if (check.error || !check.data || check.data.storage_path !== storagePath) {
      throw new Error("This document is not available for your account.");
    }
    if (storageProvider === "microsoft") {
      const sessionResult = await sb.auth.getSession();
      const token = sessionResult.data && sessionResult.data.session && sessionResult.data.session.access_token;
      if (!token) throw new Error("Please log in again.");
      const response = await fetch(SUPABASE_URL + "/functions/v1/microsoft-documents", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          apikey: SUPABASE_KEY,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ action: "download_booking_document", document_id: documentId })
      });
      if (!response.ok) {
        const failure = await response.json().catch(function () { return {}; });
        throw new Error(failure.error || "Could not prepare document download.");
      }
      const blob = await response.blob();
      const downloadUrl = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = downloadUrl;
      anchor.download = "";
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(function () { URL.revokeObjectURL(downloadUrl); }, 30000);
      return;
    }
    const result = await sb.storage.from("booking-documents").createSignedUrl(storagePath, 300, { download: true });
    if (result.error || !result.data || !result.data.signedUrl) {
      throw new Error(result.error ? result.error.message : "Could not prepare document download.");
    }
    window.open(result.data.signedUrl, "_blank", "noopener");
  }

  async function uploadMyPaymentProof(paymentId, file) {
    const user = await currentUser();
    if (!user) throw new Error("Please log in again.");
    if (!file || file.size < 1 || file.size > 10485760) throw new Error("Choose a proof file up to 10 MB.");
    if (["application/pdf", "image/jpeg", "image/png", "image/webp"].indexOf(file.type) === -1) throw new Error("Use a PDF, JPG, PNG, or WebP file.");
    const safeName = String(file.name || "proof").replace(/[^A-Za-z0-9._-]+/g, "-").slice(-120) || "proof";
    const path = user.id + "/" + paymentId + "/" + Date.now() + "-" + safeName;
    const sb = await client();
    const upload = await sb.storage.from("booking-payment-proofs").upload(path, file, { upsert: false, contentType: file.type });
    if (upload.error) throw upload.error;
    const attach = await sb.rpc("attach_my_payment_proof", { p_payment_id: paymentId, p_storage_path: path, p_file_name: String(file.name || safeName).slice(0, 180), p_mime_type: file.type, p_size_bytes: file.size });
    if (attach.error) {
      await sb.storage.from("booking-payment-proofs").remove([path]);
      throw attach.error;
    }
    return attach.data === true;
  }

  async function listMyBookingTimeline(bookingId) {
    const sb = await client();
    const result = await sb.rpc("list_my_booking_timeline", { p_booking_id: bookingId });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listMyTravellers() {
    const sb = await client();
    const result = await sb.rpc("list_my_travellers");
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function saveMyTraveller(payload) {
    const sb = await client();
    const result = await sb.rpc("save_my_traveller", {
      p_traveller_id: payload.id || null,
      p_full_name: payload.fullName,
      p_date_of_birth: payload.dateOfBirth || null,
      p_nationality: payload.nationality || null,
      p_passport_number: payload.passportNumber || null,
      p_passport_expiry: payload.passportExpiry || null,
      p_expected_updated_at: payload.expectedUpdatedAt || null
    });
    if (result.error) throw result.error;
    return result.data;
  }

  async function archiveMyTraveller(id, expectedUpdatedAt) {
    const sb = await client();
    const result = await sb.rpc("archive_my_traveller", {
      p_traveller_id: id,
      p_expected_updated_at: expectedUpdatedAt
    });
    if (result.error) throw result.error;
    return result.data === true;
  }

  async function listMySupportRequests() {
    const sb = await client();
    const result = await sb.rpc("list_my_support_requests");
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function createMySupportRequest(payload) {
    const sb = await client();
    const result = await sb.rpc("create_my_support_request", {
      p_category: payload.category,
      p_subject: payload.subject,
      p_description: payload.description,
      p_urgency: payload.urgency,
      p_booking_id: payload.bookingId || null,
      p_enquiry_id: payload.enquiryId || null
    });
    if (result.error) throw result.error;
    return result.data;
  }

  async function cancelMySupportRequest(id, expectedUpdatedAt) {
    const sb = await client();
    const result = await sb.rpc("cancel_my_support_request", { p_request_id: id, p_expected_updated_at: expectedUpdatedAt });
    if (result.error) throw result.error;
    return result.data === true;
  }

  async function listEnquiries() {
    const user = await currentUser();
    if (!user) return [];

    const sb = await client();
    const result = await sb
      .from("enquiries")
      .select("id, reference, service_type, status, summary, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false });

    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listRequests() {
    const user = await currentUser();
    if (!user) return [];
    const sb = await client();
    const result = await sb.from("enquiry_requests").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listQuotes() {
    const user = await currentUser();
    if (!user) return [];
    const sb = await client();
    const result = await sb.from("quotes").select("*").order("created_at", { ascending: false });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function respondToTextRequest(requestId, text) {
    const sb = await client();
    const result = await sb
      .from("enquiry_requests")
      .update({ response_text: text, responded_at: new Date().toISOString() })
      .eq("id", requestId)
      .select("*")
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function respondToFileRequest(requestId, file) {
    const user = await currentUser();
    if (!user) throw new Error("Please log in again.");
    const sb = await client();
    const path = user.id + "/" + requestId + "/" + file.name;
    const upload = await sb.storage.from("enquiry-uploads").upload(path, file, { upsert: true });
    if (upload.error) throw upload.error;
    const result = await sb
      .from("enquiry_requests")
      .update({ response_file_path: path, response_file_name: file.name, responded_at: new Date().toISOString() })
      .eq("id", requestId)
      .select("*")
      .single();
    if (result.error) throw result.error;
    return result.data;
  }

  async function respondToQuote(quoteId, status, expectedUpdatedAt, termsConfirmed) {
    const sb = await client();
    const result = await sb.rpc("respond_to_my_quote", { p_quote_id: quoteId, p_decision: status, p_expected_updated_at: expectedUpdatedAt, p_terms_confirmed: termsConfirmed === true });
    if (result.error) throw result.error;
    return result.data;
  }

  async function requestQuoteRevision(quoteId, message, expectedUpdatedAt) {
    const sb = await client();
    const result = await sb.rpc("request_my_quote_revision", { p_quote_id: quoteId, p_message: message, p_expected_updated_at: expectedUpdatedAt });
    if (result.error) throw result.error;
    return result.data;
  }

  async function getMyCorporatePortal() {
    const user = await currentUser();
    if (!user) return [];
    const sb = await client();
    const result = await sb.rpc("get_my_corporate_portal");
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function listMyCorporateBookings(corporateAccountId) {
    const user = await currentUser();
    if (!user) return [];
    const sb = await client();
    const result = await sb.rpc("list_my_corporate_bookings", {
      p_corporate_account_id: corporateAccountId || null,
      p_limit: 100
    });
    if (result.error) throw result.error;
    return result.data || [];
  }

  async function createMyCorporateRequest(payload) {
    const user = await currentUser();
    if (!user) throw new Error("Please log in again.");
    const sb = await client();
    const result = await sb.rpc("create_my_corporate_request", {
      p_corporate_account_id: payload.corporateAccountId,
      p_title: payload.title,
      p_service_type: payload.serviceType,
      p_route_or_destination: payload.route || null,
      p_travel_start: payload.travelStart || null,
      p_travel_end: payload.travelEnd || null,
      p_customer_notes: payload.notes || null
    });
    if (result.error) throw result.error;
    return result.data;
  }

  function getUser(email) {
    const cached = session();
    if (!cached) return null;
    return !email || cleanEmail(email) === cleanEmail(cached.email) ? cached : null;
  }

  function passwordIssue(pw) {
    if (pw.length < 8) return "Password must be at least 8 characters.";
    if (!/[a-zA-Z]/.test(pw) || !/[0-9]/.test(pw)) return "Use at least one letter and one number.";
    return "";
  }

  function passwordStrength(pw) {
    let score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score++;
    if (/[0-9]/.test(pw)) score++;
    if (/[^a-zA-Z0-9]/.test(pw)) score++;
    return score;
  }

  function escapeHTML(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function statusLabel(value) {
    return String(value || "enquiry").replace(/_/g, " ").replace(/\b\w/g, function (c) {
      return c.toUpperCase();
    });
  }

  return {
    client: client,
    session: session,
    currentUser: currentUser,
    register: register,
    login: login,
    logout: logout,
    resetPassword: resetPassword,
    completePasswordReset: completePasswordReset,
    changePassword: changePassword,
    updateProfile: updateProfile,
    getUser: getUser,
    listBookings: listBookings,
    listEnquiries: listEnquiries,
    listBookingDocuments: listBookingDocuments,
    openBookingDocument: openBookingDocument,
    listCustomerPayments: listCustomerPayments,
    uploadMyPaymentProof: uploadMyPaymentProof,
    listMyBookingTimeline: listMyBookingTimeline,
    listMyTravellers: listMyTravellers,
    saveMyTraveller: saveMyTraveller,
    archiveMyTraveller: archiveMyTraveller,
    listMySupportRequests: listMySupportRequests,
    createMySupportRequest: createMySupportRequest,
    cancelMySupportRequest: cancelMySupportRequest,
    listRequests: listRequests,
    listQuotes: listQuotes,
    respondToTextRequest: respondToTextRequest,
    respondToFileRequest: respondToFileRequest,
    respondToQuote: respondToQuote,
    requestQuoteRevision: requestQuoteRevision,
    getMyCorporatePortal: getMyCorporatePortal,
    listMyCorporateBookings: listMyCorporateBookings,
    createMyCorporateRequest: createMyCorporateRequest,
    passwordIssue: passwordIssue,
    passwordStrength: passwordStrength,
    escapeHTML: escapeHTML,
    statusLabel: statusLabel
  };
})();

/* ============================================================
   Page wiring (login / register / account / reset password)
   ============================================================ */
(function () {
  const page = document.body.dataset.page;

  function banner(form, msg, kind) {
    const el = form.querySelector(".form-banner");
    if (!el) return;
    el.hidden = !msg;
    el.textContent = msg || "";
    el.className = "form-banner " + (kind || "error");
  }

  function readableErrorValue(value, depth) {
    if (!value || depth > 2) return "";
    if (typeof value === "string") return value.trim();
    if (value instanceof Error && value.message) return value.message.trim();

    const keys = ["message", "error_description", "description", "details", "hint", "msg"];
    for (let i = 0; i < keys.length; i++) {
      const text = readableErrorValue(value[keys[i]], depth + 1);
      if (text) return text;
    }

    const nested = readableErrorValue(value.error, depth + 1);
    if (nested) return nested;

    try {
      const text = JSON.stringify(value);
      return text && text !== "{}" ? text : "";
    } catch (e) {
      return "";
    }
  }

  function errorMessage(err, fallback) {
    const text = readableErrorValue(err, 0);
    if (!text || text === "{}") return fallback;
    if (/already registered|user already exists|already been registered/i.test(text)) {
      return "An account already exists for this email. Please log in or use password reset.";
    }
    if (/database error saving new user|error saving new user/i.test(text)) {
      return "We could not finish account setup right now. Please try again, or contact Kridiya Travel on WhatsApp so we can create it for you.";
    }
    if (/failed to fetch|network|load failed/i.test(text)) {
      return "Could not reach the secure account service. Please check your internet connection and try again.";
    }
    return text;
  }

  function busy(form, on, label) {
    const btn = form.querySelector('button[type="submit"]');
    if (!btn) return;
    btn.disabled = on;
    btn.innerHTML = on ? '<span class="spinner" aria-hidden="true"></span> ' + label : btn.dataset.label;
  }

  function initPwToggles(scope) {
    (scope || document).querySelectorAll(".pw-toggle").forEach(function (t) {
      t.addEventListener("click", function () {
        const input = t.parentElement.querySelector("input");
        const show = input.type === "password";
        input.type = show ? "text" : "password";
        t.textContent = show ? "HIDE" : "SHOW";
        t.setAttribute("aria-label", show ? "Hide password" : "Show password");
      });
    });
  }

  function refreshHeaderName(user) {
    const btn = document.getElementById("account-btn");
    if (btn && user && user.name) {
      btn.textContent = "Hi, " + user.name.split(" ")[0];
      btn.href = "account.html";
    }
  }

  async function existingUserOrNull() {
    try {
      return await KridiyaAuth.currentUser();
    } catch (e) {
      return null;
    }
  }

  function loginRedirectTarget() {
    const dest = new URLSearchParams(location.search).get("next");
    return dest && /^[a-z-]+\.html$/.test(dest) ? dest : "account.html";
  }

  if (page === "login") {
    document.addEventListener("DOMContentLoaded", async function () {
      if (await existingUserOrNull()) {
        location.replace(loginRedirectTarget());
        return;
      }

      const form = document.getElementById("login-form");
      initPwToggles(form);
      form.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(form)) return;
        banner(form, "");
        busy(form, true, "Signing in...");
        try {
          const user = await KridiyaAuth.login(form.email.value, form.password.value);
          if (typeof trackEvent === "function") trackEvent("login", { method: "email" });
          toast("Welcome back, " + user.name.split(" ")[0] + "!");
          location.href = loginRedirectTarget();
        } catch (err) {
          banner(form, errorMessage(err, "Could not sign in. Please check your email and password."), "error");
          busy(form, false);
        }
      });

      const resetBtn = document.getElementById("reset-password-btn");
      if (resetBtn) {
        resetBtn.addEventListener("click", async function () {
          const email = form.email.value.trim();
          if (!email) {
            setFieldError(form.email, "Enter your email first, then click reset.");
            form.email.focus();
            return;
          }
          banner(form, "");
          resetBtn.disabled = true;
          resetBtn.textContent = "Sending reset link...";
          try {
            await KridiyaAuth.resetPassword(email);
            banner(form, "Password reset email sent. Check your inbox.", "success");
          } catch (err) {
            banner(form, errorMessage(err, "Could not send the password reset email. Please try again."), "error");
          }
          resetBtn.disabled = false;
          resetBtn.textContent = "Send password reset email";
        });
      }
    });
  }

  if (page === "register") {
    document.addEventListener("DOMContentLoaded", async function () {
      if (await existingUserOrNull()) {
        location.replace("account.html");
        return;
      }

      const form = document.getElementById("register-form");
      initPwToggles(form);

      const pwInput = form.password;
      const meter = form.querySelector(".pw-meter i");
      pwInput.addEventListener("input", function () {
        const s = KridiyaAuth.passwordStrength(pwInput.value);
        meter.style.width = (s / 5) * 100 + "%";
        meter.className = s >= 4 ? "strong" : s >= 2 ? "ok" : "";
      });

      form.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(form)) return;
        const issue = KridiyaAuth.passwordIssue(form.password.value);
        if (issue) {
          setFieldError(form.password, issue);
          form.password.focus();
          return;
        }
        if (form.password.value !== form.confirm.value) {
          setFieldError(form.confirm, "Passwords do not match.");
          form.confirm.focus();
          return;
        }
        banner(form, "");
        busy(form, true, "Creating account...");
        try {
          const user = await KridiyaAuth.register({
            name: form.name.value,
            email: form.email.value,
            phone: form.phone.value,
            password: form.password.value
          });

          if (user.needsEmailConfirmation) {
            if (typeof trackEvent === "function") trackEvent("register_account", { method: "email", confirmation_required: true });
            banner(form, "Account created. Check your email and click the confirmation link before logging in.", "success");
            form.reset();
            meter.style.width = "0";
            busy(form, false);
            return;
          }

          if (typeof trackEvent === "function") trackEvent("register_account", { method: "email", confirmation_required: false });
          toast("Welcome to Kridiya Travel, " + user.name.split(" ")[0] + "!");
          location.href = "account.html";
        } catch (err) {
          banner(form, errorMessage(err, "Could not create the account. Please try again or contact Kridiya Travel."), "error");
          busy(form, false);
        }
      });
    });
  }

  function requestsHTML(requests) {
    if (!requests.length) return "";
    return '<div class="enq-extra customer-action-list"><h4>Action needed from you</h4>' + requests.map(function (r) {
      if (r.responded_at) {
        const answer = r.kind === "file"
          ? (r.response_file_name ? "Uploaded: " + KridiyaAuth.escapeHTML(r.response_file_name) : "Uploaded")
          : KridiyaAuth.escapeHTML(r.response_text || "");
        return '<p class="form-note enq-extra-done">' + icon("check") + " " + KridiyaAuth.escapeHTML(r.label) + " - " + answer + "</p>";
      }
      if (r.kind === "file") {
        return '<form class="cust-request-form" data-request-id="' + r.id + '" data-kind="file">' +
          "<label>" + KridiyaAuth.escapeHTML(r.label) + "</label>" +
          '<input type="file" required>' +
          '<button class="btn btn-outline" type="submit">Upload</button>' +
          "</form>";
      }
      return '<form class="cust-request-form" data-request-id="' + r.id + '" data-kind="text">' +
        "<label>" + KridiyaAuth.escapeHTML(r.label) + "</label>" +
        '<input type="text" required placeholder="Your answer">' +
        '<button class="btn btn-outline" type="submit">Send</button>' +
        "</form>";
    }).join("") + "</div>";
  }

  function money(v, c) {
    return KridiyaAuth.escapeHTML((c || "AED") + " " + Number(v || 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
  }

  function docPresentation(doc) {
    const source = String([doc.document_type, doc.file_name, doc.external_reference].filter(Boolean).join(" ")).toLowerCase();
    if (/ticket|e-?ticket|flight/.test(source)) return { type: "ticket", label: "Travel ticket" };
    if (/voucher|hotel|stay|transfer|tour|package/.test(source)) return { type: "voucher", label: "Voucher" };
    if (/invoice|tax|receipt|bill/.test(source)) return { type: "invoice", label: "Invoice" };
    if (/visa|permit/.test(source)) return { type: "visa", label: "Visa document" };
    if (/insurance|policy/.test(source)) return { type: "policy", label: "Policy" };
    return { type: "document", label: KridiyaAuth.statusLabel(doc.document_type || "Document") };
  }

  function quoteDetailRows(q) {
    const od = (q.option_data && typeof q.option_data === "object") ? q.option_data : {};
    let rows = Object.keys(od).map(function (k) {
      return od[k] ? '<div class="quote-row"><span class="quote-k">' + KridiyaAuth.escapeHTML(k) + '</span><span class="quote-v">' + KridiyaAuth.escapeHTML(String(od[k])) + "</span></div>" : "";
    }).join("");
    if (!rows) {
      const legacy = [];
      if (q.airline || q.stops) legacy.push(["Flight", [q.airline, q.stops].filter(Boolean).join(" / ")]);
      if (q.outbound) legacy.push(["Onward", q.outbound]);
      if (q.inbound) legacy.push(["Return", q.inbound]);
      if (q.baggage) legacy.push(["Baggage", q.baggage]);
      rows = legacy.map(function (r) {
        return '<div class="quote-row"><span class="quote-k">' + KridiyaAuth.escapeHTML(r[0]) + '</span><span class="quote-v">' + KridiyaAuth.escapeHTML(r[1]) + "</span></div>";
      }).join("");
    }
    return rows;
  }
  function quotesHTML(quotes) {
    if (!quotes.length) return "";
    const sortedQuotes = quotes.slice().sort(function (a, b) {
      const byPrice = Number(a.price_amount || 0) - Number(b.price_amount || 0);
      if (byPrice) return byPrice;
      return String(a.created_at || "").localeCompare(String(b.created_at || ""));
    });
    function displayTitle(q, index) {
      const name = String(q.title || "").replace(/^Option\s+\d+\s*:\s*/i, "").trim();
      return "Option " + (index + 1) + (name ? ": " + name : "");
    }
    return '<div class="enq-extra quote-list">' + sortedQuotes.map(function (q, index) {
      const amount = money(q.price_amount, q.currency);
      const validity = q.valid_until
        ? new Date(q.valid_until).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric" })
        : "";
      const details = quoteDetailRows(q);
      const adds = Array.isArray(q.addons) ? q.addons : [];
      const addonsHtml = adds.length
        ? '<div class="quote-addons"><span class="quote-addons-title">Optional add-ons</span>' + adds.map(function (a) {
            return '<div class="quote-row"><span class="quote-k">' + KridiyaAuth.escapeHTML(a.name) + '</span><span class="quote-v">' + (a.price != null ? money(a.price, q.currency) : "") + "</span></div>";
          }).join("") + "</div>"
        : "";
      const termsHtml = q.terms
        ? '<details class="quote-terms"><summary>Terms &amp; conditions</summary><ul>' + String(q.terms).split("\n").map(function (t) {
            t = t.replace(/^[-*]\s*/, "").trim();
            return t ? "<li>" + KridiyaAuth.escapeHTML(t) + "</li>" : "";
          }).join("") + "</ul></details>"
        : "";

      if (q.status === "sent") {
        return '<div class="quote-card">' +
          '<div class="quote-card-head"><h4>' + KridiyaAuth.escapeHTML(displayTitle(q, index)) + '</h4><div class="quote-price">' + amount + "</div></div>" +
          (details ? '<div class="quote-details">' + details + "</div>" : "") +
          addonsHtml +
          termsHtml +
          (validity ? '<p class="quote-valid">Valid until ' + KridiyaAuth.escapeHTML(validity) + "</p>" : "") +
          '<label class="quote-confirm"><input type="checkbox" data-quote-terms="' + q.id + '"> <span>I confirm I reviewed this quote and its terms.</span></label>' +
          '<div class="quote-actions">' +
            '<button class="btn btn-primary" type="button" data-quote-id="' + q.id + '" data-quote-updated="' + KridiyaAuth.escapeHTML(q.updated_at) + '" data-action="accepted">Accept quote</button>' +
            '<button class="btn btn-outline" type="button" data-quote-id="' + q.id + '" data-quote-updated="' + KridiyaAuth.escapeHTML(q.updated_at) + '" data-action="revision">Request changes</button>' +
            '<button class="btn btn-outline" type="button" data-quote-id="' + q.id + '" data-quote-updated="' + KridiyaAuth.escapeHTML(q.updated_at) + '" data-action="declined">Decline</button>' +
          "</div></div>";
      }
      return '<div class="quote-card quote-card-done">' +
        '<div class="quote-card-head"><h4>' + KridiyaAuth.escapeHTML(displayTitle(q, index)) + '</h4><div class="quote-price">' + amount + "</div></div>" +
        (details ? '<div class="quote-details">' + details + "</div>" : "") +
        '<p class="quote-status-line">' + icon("check") + " " + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(q.status)) + "</p></div>";
    }).join("") + "</div>";
  }
  function customerDocsHTML(docs) {
    if (!docs.length) return '<div class="enq-extra customer-doc-list customer-empty-list"><h4>Documents</h4><p>No customer-visible documents have been released yet.</p></div>';
    return '<div class="enq-extra customer-doc-list"><h4>Documents</h4>' + docs.map(function (d) {
      const created = d.created_at ? new Date(d.created_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "";
      const view = docPresentation(d);
      return '<div class="customer-doc-ticket doc-' + KridiyaAuth.escapeHTML(view.type) + '">' +
        '<div class="doc-ticket-mark"><span>' + KridiyaAuth.escapeHTML(view.label) + '</span></div>' +
        '<div class="doc-ticket-body"><b>' + KridiyaAuth.escapeHTML(d.file_name || view.label) + '</b>' +
        '<span>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(d.document_type || view.label)) + (created ? " / " + KridiyaAuth.escapeHTML(created) : "") + '</span>' +
        (d.external_reference ? '<small>Reference: ' + KridiyaAuth.escapeHTML(d.external_reference) + '</small>' : '') + '</div>' +
        (d.storage_path
          ? '<button class="btn btn-outline btn-sm customer-doc-download" type="button" data-document-id="' + KridiyaAuth.escapeHTML(d.id) + '" data-storage-path="' + KridiyaAuth.escapeHTML(d.storage_path) + '" data-storage-provider="' + KridiyaAuth.escapeHTML(d.storage_provider || "supabase") + '">Download</button>'
          : '<span class="customer-row-state">Released</span>') + '</div>';
    }).join("") + "</div>";
  }

  function customerPaymentsHTML(payments) {
    if (!payments.length) return '<div class="enq-extra customer-payment-list customer-empty-list"><h4>Payments and refunds</h4><p>No customer payment or refund updates yet.</p></div>';
    return '<div class="enq-extra customer-payment-list"><h4>Payments and refunds</h4>' + payments.map(function (p) {
      const status = KridiyaAuth.statusLabel(p.status);
      const amount = money(p.refund_amount || p.amount, p.currency);
      const isRefund = /refund/i.test(String(p.status || "")) || p.refund_amount;
      const ref = p.refund_reference || p.payment_reference || "";
      const canUpload = !isRefund && p.payment_direction === "customer_in" && /^(pending|proof_received)$/.test(String(p.status || ""));
      const proof = p.proof_uploaded_at ? '<small>Proof submitted ' + KridiyaAuth.escapeHTML(new Date(p.proof_uploaded_at).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })) + ' — awaiting verification</small>' : '';
      const upload = canUpload ? '<label class="btn btn-outline btn-sm proof-upload-label">' + (p.proof_uploaded_at ? 'Replace proof' : 'Upload proof') + '<input type="file" data-customer-proof="' + KridiyaAuth.escapeHTML(p.id) + '" accept="image/jpeg,image/png,image/webp,application/pdf" hidden></label>' : '';
      return '<div class="customer-mini-row customer-payment-row"><div><b>' + (isRefund ? "Refund" : "Payment") + ": " + amount + '</b><span>' + KridiyaAuth.escapeHTML(status) + ' / ' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(p.method)) + '</span>' + (ref ? '<small>Reference: ' + KridiyaAuth.escapeHTML(ref) + '</small>' : '') + proof + (p.refund_reason ? '<small>' + KridiyaAuth.escapeHTML(p.refund_reason) + '</small>' : '') + '</div><div class="account-actions"><span class="customer-row-state">' + KridiyaAuth.escapeHTML(status) + '</span>' + upload + '</div></div>';
    }).join("") + "</div>";
  }

  function tripTimelineHTML(events) {
    if (!events.length) return '<p class="form-note">No trip milestones are available yet.</p>';
    return '<ol class="trip-timeline">' + events.map(function (event) {
      const date = new Date(event.event_at);
      return '<li class="timeline-' + KridiyaAuth.escapeHTML(event.tone || "current") + '"><span></span><div><time datetime="' + KridiyaAuth.escapeHTML(event.event_at) + '">' + KridiyaAuth.escapeHTML(date.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })) + '</time><b>' + KridiyaAuth.escapeHTML(event.title) + '</b><small>' + KridiyaAuth.escapeHTML(event.detail || "") + '</small></div></li>';
    }).join("") + '</ol>';
  }

  function wireEnquiryExtras(listEl) {
    listEl.addEventListener("click", async function (event) {
      const button = event.target.closest("[data-trip-timeline]");
      if (!button) return;
      const box = listEl.querySelector('[data-trip-timeline-box="' + button.dataset.tripTimeline + '"]');
      if (!box) return;
      if (!box.hidden) { box.hidden = true; button.textContent = "View trip timeline"; return; }
      box.hidden = false; button.disabled = true; button.textContent = "Loading...";
      try { box.innerHTML = tripTimelineHTML(await KridiyaAuth.listMyBookingTimeline(button.dataset.tripTimeline)); button.textContent = "Hide trip timeline"; }
      catch (err) { box.innerHTML = '<div class="form-banner error" role="alert">' + KridiyaAuth.escapeHTML(errorMessage(err, "Could not load trip timeline.")) + '</div>'; button.textContent = "Try timeline again"; }
      button.disabled = false;
    });
    listEl.addEventListener("change", async function (event) {
      const input = event.target.closest("[data-customer-proof]");
      if (!input || !input.files || !input.files[0]) return;
      const file = input.files[0], label = input.closest("label"), old = label.firstChild.textContent;
      input.disabled = true; label.firstChild.textContent = "Uploading...";
      try { await KridiyaAuth.uploadMyPaymentProof(input.dataset.customerProof, file); toast("Payment proof submitted for verification."); location.reload(); }
      catch (err) { input.disabled = false; input.value = ""; label.firstChild.textContent = old; toast(errorMessage(err, "Could not upload payment proof.")); }
    });
    listEl.addEventListener("click", async function (e) {
      const btn = e.target.closest(".customer-doc-download");
      if (!btn) return;
      btn.disabled = true;
      const old = btn.textContent;
      btn.textContent = "Preparing...";
      try {
        await KridiyaAuth.openBookingDocument(btn.dataset.documentId, btn.dataset.storagePath, btn.dataset.storageProvider);
      } catch (err) {
        toast(errorMessage(err, "Could not prepare the document."));
      }
      btn.disabled = false;
      btn.textContent = old;
    });
    listEl.addEventListener("submit", async function (e) {
      const form = e.target.closest(".cust-request-form");
      if (!form) return;
      e.preventDefault();
      const id = form.dataset.requestId;
      const kind = form.dataset.kind;
      const btn = form.querySelector('button[type="submit"]');
      btn.disabled = true;
      try {
        if (kind === "file") {
          const file = form.querySelector('input[type="file"]').files[0];
          if (!file) { btn.disabled = false; return; }
          await KridiyaAuth.respondToFileRequest(id, file);
        } else {
          const value = form.querySelector('input[type="text"]').value.trim();
          if (!value) { btn.disabled = false; return; }
          await KridiyaAuth.respondToTextRequest(id, value);
        }
        toast("Sent - thank you.");
        location.reload();
      } catch (err) {
        btn.disabled = false;
        toast(errorMessage(err, "Could not send your reply."));
      }
    });

    listEl.addEventListener("click", async function (e) {
      const btn = e.target.closest("[data-quote-id]");
      if (!btn) return;
      const action = btn.dataset.action;
      const terms = listEl.querySelector('[data-quote-terms="' + btn.dataset.quoteId + '"]');
      if (action === "accepted" && (!terms || !terms.checked)) { toast("Please confirm you reviewed the quote and terms before accepting."); return; }
      btn.disabled = true;
      try {
        if (action === "revision") {
          const message = window.prompt("What would you like Kridiya to change in this quote?");
          if (!message) { btn.disabled = false; return; }
          await KridiyaAuth.requestQuoteRevision(btn.dataset.quoteId, message, btn.dataset.quoteUpdated);
          toast("Revision request sent to Kridiya operations.");
        } else {
          await KridiyaAuth.respondToQuote(btn.dataset.quoteId, action, btn.dataset.quoteUpdated, !!(terms && terms.checked));
          toast(action === "accepted" ? "Quote accepted." : "Quote declined.");
        }
        location.reload();
      } catch (err) {
        btn.disabled = false;
        toast(errorMessage(err, "Could not update the quote."));
      }
    });
  }

  function initCustomerSupport(bookings, enquiries) {
    const form = document.getElementById("support-request-form");
    const list = document.getElementById("support-request-list");
    if (!form || !list) return;
    const linked = form.linked_item;
    linked.innerHTML = '<option value="">Account-level request</option>' +
      bookings.map(function (b) { return '<option value="booking:' + KridiyaAuth.escapeHTML(b.id) + '">Booking ' + KridiyaAuth.escapeHTML(b.booking_reference) + '</option>'; }).join("") +
      enquiries.map(function (e) { return '<option value="enquiry:' + KridiyaAuth.escapeHTML(e.id) + '">Enquiry ' + KridiyaAuth.escapeHTML(e.reference) + '</option>'; }).join("");
    let rows = [];
    function render() {
      if (!rows.length) { list.innerHTML = '<p class="form-note">No support requests submitted from this account.</p>'; return; }
      list.innerHTML = '<div class="customer-doc-list">' + rows.map(function (r) {
        const canCancel = /^(submitted|acknowledged)$/.test(r.status);
        return '<div class="customer-doc-row"><div><b>' + KridiyaAuth.escapeHTML(r.subject) + '</b><small>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(r.category) + ' · ' + KridiyaAuth.statusLabel(r.status) + ' · ' + new Date(r.created_at).toLocaleDateString("en-GB")) + '</small>' + (r.resolution ? '<small>' + KridiyaAuth.escapeHTML(r.resolution) + '</small>' : '') + '</div>' + (canCancel ? '<button class="btn btn-outline" type="button" data-support-cancel="' + KridiyaAuth.escapeHTML(r.id) + '">Cancel</button>' : '') + '</div>';
      }).join("") + '</div>';
    }
    async function refresh() { rows = await KridiyaAuth.listMySupportRequests(); render(); }
    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      if (!validateForm(form)) return;
      const parts = String(linked.value || "").split(":");
      banner(form, ""); busy(form, true, "Submitting...");
      try {
        await KridiyaAuth.createMySupportRequest({ category: form.category.value, urgency: form.urgency.value, subject: form.subject.value, description: form.description.value, bookingId: parts[0] === "booking" ? parts[1] : null, enquiryId: parts[0] === "enquiry" ? parts[1] : null });
        form.reset(); banner(form, "Request submitted. Kridiya's operations team can now see it.", "success"); await refresh();
      } catch (err) { banner(form, errorMessage(err, "Could not submit the request."), "error"); }
      busy(form, false);
    });
    list.addEventListener("click", async function (event) {
      const button = event.target.closest("[data-support-cancel]"); if (!button) return;
      const row = rows.find(function (item) { return item.id === button.dataset.supportCancel; }); if (!row) return;
      if (!window.confirm("Cancel this support request?")) return;
      button.disabled = true;
      try { await KridiyaAuth.cancelMySupportRequest(row.id, row.updated_at); await refresh(); toast("Support request cancelled."); }
      catch (err) { button.disabled = false; toast(errorMessage(err, "Could not cancel the request.")); }
    });
    refresh().catch(function () { list.innerHTML = '<div class="form-banner error" role="alert">Could not load support requests.</div>'; });
  }

  if (page === "account") {
    document.addEventListener("DOMContentLoaded", async function () {
      const user = await KridiyaAuth.currentUser();
      if (!user) {
        location.replace("login.html?next=account.html");
        return;
      }

      document.getElementById("acc-avatar").textContent = (user.name || "T").trim().charAt(0).toUpperCase();
      document.getElementById("acc-name").textContent = user.name;
      document.getElementById("acc-email").textContent = user.email;
      const since = user.createdAt ? new Date(user.createdAt) : null;
      document.getElementById("acc-since").textContent = since
        ? "Member since " + since.toLocaleDateString("en-GB", { month: "long", year: "numeric" })
        : "";
      refreshHeaderName(user);

      const travellerForm = document.getElementById("traveller-form");
      const travellerList = document.getElementById("traveller-list");
      const travellerCancel = document.getElementById("traveller-cancel");
      let savedTravellers = [];
      function resetTravellerForm() {
        travellerForm.reset();
        travellerForm.traveller_id.value = "";
        travellerForm.expected_updated_at.value = "";
        travellerCancel.hidden = true;
        banner(travellerForm, "");
      }
      function renderTravellers() {
        if (!savedTravellers.length) {
          travellerList.innerHTML = '<div class="empty-state"><p><b>No saved travellers yet.</b><br>Add yourself or a frequent traveller below.</p></div>';
          return;
        }
        travellerList.innerHTML = '<div class="customer-doc-list">' + savedTravellers.map(function (t) {
          const details = [t.date_of_birth ? "Born " + t.date_of_birth : "", t.nationality || "", t.passport_masked || "No passport saved", t.passport_expiry ? "Expires " + t.passport_expiry : ""].filter(Boolean).join(" · ");
          return '<div class="customer-doc-row"><div><b>' + KridiyaAuth.escapeHTML(t.full_name) + '</b><small>' + KridiyaAuth.escapeHTML(details) + '</small></div><div class="account-actions"><button class="btn btn-outline" type="button" data-traveller-edit="' + KridiyaAuth.escapeHTML(t.id) + '">Edit</button><button class="btn btn-outline" type="button" data-traveller-archive="' + KridiyaAuth.escapeHTML(t.id) + '">Remove</button></div></div>';
        }).join("") + "</div>";
      }
      async function refreshTravellers() {
        savedTravellers = await KridiyaAuth.listMyTravellers();
        renderTravellers();
      }
      travellerList.addEventListener("click", async function (event) {
        const edit = event.target.closest("[data-traveller-edit]");
        const archive = event.target.closest("[data-traveller-archive]");
        const id = edit ? edit.dataset.travellerEdit : archive ? archive.dataset.travellerArchive : "";
        const row = savedTravellers.find(function (item) { return item.id === id; });
        if (!row) return;
        if (edit) {
          travellerForm.traveller_id.value = row.id;
          travellerForm.expected_updated_at.value = row.updated_at;
          travellerForm.full_name.value = row.full_name || "";
          travellerForm.date_of_birth.value = row.date_of_birth || "";
          travellerForm.nationality.value = row.nationality || "";
          travellerForm.passport_number.value = "";
          travellerForm.passport_expiry.value = row.passport_expiry || "";
          travellerCancel.hidden = false;
          travellerForm.scrollIntoView({ behavior: "smooth", block: "center" });
          return;
        }
        if (!window.confirm("Remove " + row.full_name + " from your saved travellers?")) return;
        try {
          await KridiyaAuth.archiveMyTraveller(row.id, row.updated_at);
          await refreshTravellers();
          resetTravellerForm();
          toast("Traveller removed.");
        } catch (err) { toast(errorMessage(err, "Could not remove traveller.")); }
      });
      travellerCancel.addEventListener("click", resetTravellerForm);
      travellerForm.addEventListener("submit", async function (event) {
        event.preventDefault();
        if (!validateForm(travellerForm)) return;
        banner(travellerForm, "");
        busy(travellerForm, true, "Saving...");
        try {
          await KridiyaAuth.saveMyTraveller({
            id: travellerForm.traveller_id.value,
            expectedUpdatedAt: travellerForm.expected_updated_at.value,
            fullName: travellerForm.full_name.value,
            dateOfBirth: travellerForm.date_of_birth.value,
            nationality: travellerForm.nationality.value,
            passportNumber: travellerForm.passport_number.value,
            passportExpiry: travellerForm.passport_expiry.value
          });
          await refreshTravellers();
          resetTravellerForm();
          toast("Traveller saved.");
        } catch (err) { banner(travellerForm, errorMessage(err, "Could not save traveller."), "error"); }
        busy(travellerForm, false);
      });
      try { await refreshTravellers(); } catch (err) {
        travellerList.innerHTML = '<div class="form-banner error" role="alert">Could not load saved travellers.</div>';
      }

      const listEl = document.getElementById("enq-list");
      try {
        let results = await Promise.all([
          KridiyaAuth.listBookings(),
          KridiyaAuth.listEnquiries(),
          KridiyaAuth.listRequests(),
          KridiyaAuth.listQuotes(),
          KridiyaAuth.listBookingDocuments()
        ]);
        const bookings = results[0];
        const enquiries = results[1];
        initCustomerSupport(bookings, enquiries);
        const docs = results[4] || [];
        const payments = await KridiyaAuth.listCustomerPayments(
          bookings.map(function (b) { return b.id; }),
          enquiries.map(function (e) { return e.id; })
        );
        const requestsByEnquiry = {};
        results[2].forEach(function (r) {
          if (!requestsByEnquiry[r.enquiry_id]) requestsByEnquiry[r.enquiry_id] = [];
          requestsByEnquiry[r.enquiry_id].push(r);
        });
        const quotesByEnquiry = {};
        results[3].forEach(function (q) {
          if (!quotesByEnquiry[q.enquiry_id]) quotesByEnquiry[q.enquiry_id] = [];
          quotesByEnquiry[q.enquiry_id].push(q);
        });
        const docsByBooking = {};
        docs.forEach(function (d) {
          if (!docsByBooking[d.booking_id]) docsByBooking[d.booking_id] = [];
          docsByBooking[d.booking_id].push(d);
        });
        const paymentsByBooking = {};
        const paymentsByEnquiry = {};
        payments.forEach(function (p) {
          if (p.booking_id) {
            if (!paymentsByBooking[p.booking_id]) paymentsByBooking[p.booking_id] = [];
            paymentsByBooking[p.booking_id].push(p);
          }
          if (p.enquiry_id) {
            if (!paymentsByEnquiry[p.enquiry_id]) paymentsByEnquiry[p.enquiry_id] = [];
            paymentsByEnquiry[p.enquiry_id].push(p);
          }
        });

        const openRequests = results[2].filter(function (r) {
          return !/submitted|completed|done|closed/i.test(String(r.status || ""));
        });
        const activeQuotes = results[3].filter(function (q) {
          return !/declined|expired|cancelled/i.test(String(q.status || ""));
        });

        const combined = enquiries.map(function (e) {
          return {
            id: e.id,
            isEnquiry: true,
            reference: e.reference,
            status: e.status,
            title: KridiyaAuth.statusLabel(e.service_type) + " enquiry",
            detail: e.summary,
            paxLabel: "",
            amount: "Quote pending",
            created_at: e.created_at
          };
        }).concat(bookings.map(function (booking) {
          const pax = (booking.adults || 0) + (booking.children || 0) + (booking.infants || 0);
          return {
            id: booking.id,
            isEnquiry: false,
            reference: booking.booking_reference,
            status: booking.status,
            title: booking.title,
            detail: booking.route_or_destination || booking.service_type,
            paxLabel: pax ? pax + " traveller" + (pax === 1 ? "" : "s") : "",
            amount: booking.amount ? (booking.currency + " " + Number(booking.amount).toLocaleString("en-GB")) : "Quote pending",
            paymentStatus: booking.payment_status,
            documentStatus: booking.document_status,
            created_at: booking.created_at
          };
        })).sort(function (a, b) { return new Date(b.created_at) - new Date(a.created_at); });

        const summaryBookings = document.getElementById("summary-bookings");
        if (summaryBookings) summaryBookings.textContent = String(combined.length);
        renderPortalOverview(combined, activeQuotes, openRequests);

        if (combined.length) {
          listEl.innerHTML = combined.map(function (item) {
            const created = new Date(item.created_at);
            const requests = item.isEnquiry ? (requestsByEnquiry[item.id] || []) : [];
            const quotes = item.isEnquiry ? (quotesByEnquiry[item.id] || []) : [];
            const itemDocs = item.isEnquiry ? [] : (docsByBooking[item.id] || []);
            const itemPayments = item.isEnquiry ? (paymentsByEnquiry[item.id] || []) : (paymentsByBooking[item.id] || []);
            const itemType = item.isEnquiry ? "Enquiry" : "Booking";
            const attention = requests.length ? "Needs your reply" : quotes.length ? "Quote ready" : itemDocs.length ? "Documents released" : itemPayments.length ? "Payment updated" : "In progress";
            const detailText = item.detail || "Team will update";
            return '<article class="enq-item">' +
              '<div class="enq-top"><div><span class="account-chip">' + KridiyaAuth.escapeHTML(itemType) + '</span><b>' + KridiyaAuth.escapeHTML(item.title || item.reference || itemType) + "</b></div>" +
              '<time datetime="' + KridiyaAuth.escapeHTML(item.created_at) + '">' +
              created.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) +
              "</time></div>" +
              '<div class="customer-status-strip"><span>' + KridiyaAuth.escapeHTML(attention) + '</span><small>' + KridiyaAuth.escapeHTML(item.reference || "Reference pending") + '</small></div>' +
              '<div class="account-item-grid">' +
                '<span class="account-fact"><small>Reference</small><b>' + KridiyaAuth.escapeHTML(item.reference || "Pending") + '</b></span>' +
                '<span class="account-fact"><small>Status</small><b>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(item.status)) + '</b></span>' +
                '<span class="account-fact account-fact-amount"><small>Amount</small><b>' + KridiyaAuth.escapeHTML(item.amount) + '</b></span>' +
                (item.paxLabel ? '<span class="account-fact"><small>Travellers</small><b>' + KridiyaAuth.escapeHTML(item.paxLabel) + '</b></span>' : "") +
                (item.paymentStatus ? '<span class="account-fact"><small>Payment</small><b>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(item.paymentStatus)) + '</b></span>' : "") +
                (item.documentStatus ? '<span class="account-fact"><small>Documents</small><b>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(item.documentStatus)) + '</b></span>' : "") +
                '<span class="account-detail"><small>Details</small><b>' + KridiyaAuth.escapeHTML(detailText) + '</b></span>' +
              '</div>' +
              ((requests.length || quotes.length || itemDocs.length || itemPayments.length) ? '<div class="account-item-alerts">' +
                (requests.length ? '<span>' + KridiyaAuth.escapeHTML(String(requests.length)) + ' request(s)</span>' : '') +
                (quotes.length ? '<span>' + KridiyaAuth.escapeHTML(String(quotes.length)) + ' quote(s)</span>' : '') +
                (itemDocs.length ? '<span>' + KridiyaAuth.escapeHTML(String(itemDocs.length)) + ' document(s)</span>' : '') +
                (itemPayments.length ? '<span>' + KridiyaAuth.escapeHTML(String(itemPayments.length)) + ' payment/refund update(s)</span>' : '') +
              '</div>' : '') +
              requestsHTML(requests) +
              quotesHTML(quotes) +
              (!item.isEnquiry ? customerDocsHTML(itemDocs) : '') +
              customerPaymentsHTML(itemPayments) +
              (!item.isEnquiry ? '<div class="enq-extra trip-timeline-wrap"><button class="btn btn-outline btn-sm" type="button" data-trip-timeline="' + KridiyaAuth.escapeHTML(item.id) + '">View trip timeline</button><div data-trip-timeline-box="' + KridiyaAuth.escapeHTML(item.id) + '" hidden></div></div>' : '') +
              "</article>";
          }).join("");
          wireEnquiryExtras(listEl);
        } else {
          listEl.innerHTML = '<div class="empty-state"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 12h-4a3 3 0 0 1-6 0H5V5h14v10z"/></svg><p><b>No bookings linked yet.</b><br>Send an enquiry while signed in, or ask our team to attach an existing booking to this account.</p><div class="empty-actions"><a class="btn btn-primary" href="index.html">Start planning</a><a class="btn btn-outline" href="https://wa.me/971509413873" target="_blank" rel="noopener">WhatsApp support</a></div></div>';
        }
      } catch (err) {
        listEl.innerHTML = '<div class="form-banner error" role="alert">Could not load your enquiries yet: ' + KridiyaAuth.escapeHTML(errorMessage(err, "Please refresh and try again.")) + "</div>";
      }

      const pf = document.getElementById("profile-form");
      pf.name.value = user.name || "";
      pf.phone.value = user.phone || "";
      pf.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(pf)) return;
        const btn = pf.querySelector('button[type="submit"]');
        btn.disabled = true;
        try {
          const updated = await KridiyaAuth.updateProfile(user.email, { name: pf.name.value, phone: pf.phone.value });
          toast("Profile updated.");
          document.getElementById("acc-name").textContent = updated.name;
          document.getElementById("acc-avatar").textContent = updated.name.trim().charAt(0).toUpperCase();
          refreshHeaderName(updated);
        } catch (err) {
          toast(errorMessage(err, "Could not update your profile."));
        }
        btn.disabled = false;
      });

      const pwf = document.getElementById("password-form");
      initPwToggles(pwf);
      pwf.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(pwf)) return;
        const issue = KridiyaAuth.passwordIssue(pwf.newpass.value);
        if (issue) {
          setFieldError(pwf.newpass, issue);
          return;
        }
        banner(pwf, "");
        busy(pwf, true, "Updating...");
        try {
          await KridiyaAuth.changePassword(user.email, pwf.current.value, pwf.newpass.value);
          banner(pwf, "Password updated successfully.", "success");
          pwf.reset();
        } catch (err) {
          banner(pwf, errorMessage(err, "Could not update your password."), "error");
        }
        busy(pwf, false);
      });

      document.getElementById("logout-btn").addEventListener("click", async function () {
        await KridiyaAuth.logout();
        location.href = "index.html";
      });
    });
  }

  if (page === "corporate-account") {
    document.addEventListener("DOMContentLoaded", async function () {
      const user = await KridiyaAuth.currentUser();
      if (!user) {
        location.replace("login.html?next=corporate-account.html");
        return;
      }
      const gate = document.getElementById("corporate-account-gate");
      const app = document.getElementById("corporate-account-app");
      try {
        const companies = await KridiyaAuth.getMyCorporatePortal();
        if (!companies.length) {
          gate.innerHTML =
            '<div class="form-banner error" role="alert"><b>Corporate portal not activated yet.</b><br>Kridiya must approve your company and link your login before private company records appear here. You can still send a request below.</div>' +
            '<p><a class="btn btn-primary" href="corporate-booking.html">Send corporate request</a> <a class="btn btn-outline" href="https://wa.me/971509413873?text=Hello%20Kridiya%20Travel!%20Please%20activate%20my%20corporate%20portal%20access." target="_blank" rel="noopener">WhatsApp support</a></p>';
          return;
        }
        const activeCompany = companies[0];
        const bookings = await KridiyaAuth.listMyCorporateBookings(activeCompany.corporate_account_id);
        renderCorporatePortal(companies, bookings, activeCompany);
        initCorporatePortalRequest(activeCompany, function () {
          return KridiyaAuth.listMyCorporateBookings(activeCompany.corporate_account_id).then(function (fresh) {
            renderCorporatePortal(companies, fresh, activeCompany);
          });
        });
        gate.hidden = true;
        app.hidden = false;
      } catch (err) {
        gate.innerHTML = '<div class="form-banner error" role="alert">Could not load corporate portal yet: ' + KridiyaAuth.escapeHTML(errorMessage(err, "Please refresh and try again.")) + "</div>";
      }
    });
  }

  function renderCorporatePortal(companies, bookings, activeCompany) {
    const companyList = document.getElementById("corp-company-list");
    const bookingList = document.getElementById("corp-booking-list");
    document.getElementById("corp-visible-items").textContent = String(bookings.length);
    document.getElementById("corp-company-count").textContent = String(companies.length);
    document.getElementById("corp-company-name").textContent = activeCompany.company_name || "Approved company";
    document.getElementById("corp-member-role").textContent = KridiyaAuth.statusLabel(activeCompany.member_role || "Member");
    document.getElementById("corp-access-copy").textContent =
      (activeCompany.company_name || "Your company") + " is linked to this login. You can see portal-safe company booking status and create new requests.";

    companyList.innerHTML = companies.map(function (company) {
      const chips = [
        company.can_request ? "Can request" : "Request locked",
        company.can_approve_quotes ? "Can approve quotes" : "Approval by staff/company admin",
        company.can_view_finance ? "Finance visible" : "Finance hidden",
        company.lpo_required ? "LPO required" : "No LPO flag"
      ];
      return '<div class="corporate-company-card">' +
        '<b>' + KridiyaAuth.escapeHTML(company.company_name || "Company") + '</b>' +
        '<p>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(company.member_role || "member")) + ' access · ' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(company.status || "active")) + '</p>' +
        '<div>' + chips.map(function (chip) { return '<span>' + KridiyaAuth.escapeHTML(chip) + '</span>'; }).join("") + '</div>' +
      '</div>';
    }).join("");

    if (!bookings.length) {
      bookingList.innerHTML = '<div class="empty-state"><p>No corporate bookings are visible yet. Submit your first portal request or ask Kridiya to link existing company bookings.</p></div>';
      return;
    }

    bookingList.innerHTML = bookings.map(function (booking) {
      const amount = booking.amount ? '<strong>' + KridiyaAuth.escapeHTML(String(booking.currency || "AED")) + ' ' + KridiyaAuth.escapeHTML(String(booking.amount)) + '</strong>' : '<span>Finance restricted</span>';
      return '<article class="corporate-booking-card">' +
        '<div><b>' + KridiyaAuth.escapeHTML(booking.booking_reference || "Corporate request") + '</b><span>' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(booking.status)) + '</span></div>' +
        '<h3>' + KridiyaAuth.escapeHTML(booking.title || KridiyaAuth.statusLabel(booking.service_type)) + '</h3>' +
        '<p>' + KridiyaAuth.escapeHTML([booking.service_type, booking.route_or_destination].filter(Boolean).map(KridiyaAuth.statusLabel).join(" · ") || "Corporate travel request") + '</p>' +
        '<footer><small>Payment: ' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(booking.payment_status || "not_requested")) + '</small><small>Docs: ' + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(booking.document_status || "not_started")) + '</small>' + amount + '</footer>' +
      '</article>';
    }).join("");
  }

  function initCorporatePortalRequest(activeCompany, refresh) {
    const form = document.getElementById("corp-portal-request-form");
    if (!form || form.dataset.ready === "true") return;
    form.dataset.ready = "true";
    if (!activeCompany.can_request) {
      form.innerHTML = '<div class="form-banner error" role="alert">Your login can view this company, but request creation is not enabled. Ask Kridiya admin to enable request access.</div>';
      return;
    }
    form.addEventListener("submit", async function (e) {
      e.preventDefault();
      if (!validateForm(form)) return;
      banner(form, "");
      busy(form, true, "Submitting...");
      try {
        await KridiyaAuth.createMyCorporateRequest({
          corporateAccountId: activeCompany.corporate_account_id,
          serviceType: form.service.value,
          title: form.title.value,
          route: form.route.value,
          travelStart: form.start.value,
          travelEnd: form.end.value,
          notes: form.notes.value
        });
        banner(form, "Corporate request submitted. Kridiya admin can now see it under your company.", "success");
        form.reset();
        if (typeof refresh === "function") await refresh();
      } catch (err) {
        banner(form, errorMessage(err, "Could not submit corporate request."), "error");
      }
      busy(form, false);
    });
  }

  function renderPortalOverview(items, quotes, requests) {
    const summary = document.getElementById("portal-summary");
    const next = document.getElementById("portal-next-action");
    if (!summary || !next) return;
    const bookings = items.filter(function (item) { return !item.isEnquiry; }).length;
    const enquiries = items.length - bookings;
    summary.innerHTML =
      '<div><span>' + KridiyaAuth.escapeHTML(String(items.length)) + '</span><b>Total items</b><small>' + KridiyaAuth.escapeHTML(bookings + " booking(s), " + enquiries + " enquiry(s)") + '</small></div>' +
      '<div><span>' + KridiyaAuth.escapeHTML(String(quotes.length)) + '</span><b>Quotes</b><small>Active options from our team</small></div>' +
      '<div><span>' + KridiyaAuth.escapeHTML(String(requests.length)) + '</span><b>Requests</b><small>Documents or replies needed</small></div>';
    let tone = "ok";
    let title = "Your portal is ready";
    let text = "You can start a new enquiry or message our team for an update.";
    let href = "index.html";
    let cta = "New enquiry";
    if (requests.length) {
      tone = "warn";
      title = "Action needed";
      text = requests.length + " request(s) need your reply or document update.";
      href = "#enq-list";
      cta = "Review requests";
    } else if (quotes.length) {
      tone = "info";
      title = "Quote available";
      text = quotes.length + " quote option(s) are waiting for your review.";
      href = "#enq-list";
      cta = "View quotes";
    } else if (!items.length) {
      tone = "neutral";
      title = "No linked travel yet";
      text = "Send your first enquiry, or ask our team to attach an existing booking to this account.";
    }
    next.innerHTML = '<div class="portal-next portal-next-' + tone + '"><div><b>' + KridiyaAuth.escapeHTML(title) + '</b><p>' + KridiyaAuth.escapeHTML(text) + '</p></div><a class="btn btn-primary" href="' + KridiyaAuth.escapeHTML(href) + '">' + KridiyaAuth.escapeHTML(cta) + '</a></div>';
  }

  if (page === "reset-password") {
    document.addEventListener("DOMContentLoaded", async function () {
      const form = document.getElementById("reset-password-form");
      initPwToggles(form);
      try { await KridiyaAuth.client(); } catch (e) {}
      form.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(form)) return;
        const issue = KridiyaAuth.passwordIssue(form.password.value);
        if (issue) {
          setFieldError(form.password, issue);
          return;
        }
        if (form.password.value !== form.confirm.value) {
          setFieldError(form.confirm, "Passwords do not match.");
          form.confirm.focus();
          return;
        }
        banner(form, "");
        busy(form, true, "Saving...");
        try {
          await KridiyaAuth.completePasswordReset(form.password.value);
          banner(form, "Password updated. Taking you to your account...", "success");
          setTimeout(function () { location.href = "account.html"; }, 1000);
        } catch (err) {
          banner(form, errorMessage(err, "Could not update your password."), "error");
          busy(form, false);
        }
      });
    });
  }

  if (page === "forgot-password") {
    document.addEventListener("DOMContentLoaded", async function () {
      const form = document.getElementById("forgot-password-form");
      try { await KridiyaAuth.client(); } catch (e) {}
      form.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(form)) return;
        banner(form, "");
        busy(form, true, "Sending...");
        try {
          await KridiyaAuth.resetPassword(form.email.value);
          banner(form, "Password reset email sent. Check your inbox and use the newest link.", "success");
          form.reset();
        } catch (err) {
          banner(form, errorMessage(err, "Could not send the password reset email. Please try again."), "error");
        }
        busy(form, false);
      });
    });
  }
})();
