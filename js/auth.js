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

  let clientPromise = null;
  let cachedClient = null;

  function cleanEmail(email) {
    return String(email || "").trim().toLowerCase();
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

  /* Sessions are stored in a cookie scoped to .kridiyatravel.com (not the
     browser's default localStorage, which is locked to one exact origin)
     so a login on kridiyatravel.com is also recognised on
     admin.kridiyatravel.com, and vice versa. Falls back to a plain,
     unscoped cookie on localhost so local development still works. */
  function sharedCookieStorage() {
    const isLocal = location.hostname === "localhost" || location.hostname === "127.0.0.1";
    function readCookie(name) {
      const m = document.cookie.match(new RegExp("(?:^|; )" + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "=([^;]*)"));
      return m ? decodeURIComponent(m[1]) : null;
    }
    return {
      getItem: function (key) {
        return readCookie(key);
      },
      setItem: function (key, value) {
        const maxAge = 60 * 60 * 24 * 180;
        document.cookie = key + "=" + encodeURIComponent(value) +
          (isLocal ? "" : "; domain=.kridiyatravel.com") +
          "; path=/; max-age=" + maxAge +
          (isLocal ? "" : "; secure") +
          "; samesite=lax";
      },
      removeItem: function (key) {
        document.cookie = key + "=" + (isLocal ? "" : "; domain=.kridiyatravel.com") + "; path=/; max-age=0";
      }
    };
  }

  async function client() {
    if (cachedClient) return cachedClient;
    if (!clientPromise) {
      clientPromise = loadSupabaseScript().then(function () {
        cachedClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
            storage: sharedCookieStorage()
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
        emailRedirectTo: new URL("account.html", location.href).href,
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
      redirectTo: new URL("reset-password.html", location.href).href
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
      .select("id, booking_reference, service_type, title, route_or_destination, travel_start, travel_end, adults, children, infants, amount, currency, status, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false });

    if (result.error) throw result.error;
    return result.data || [];
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

  async function respondToQuote(quoteId, status) {
    const sb = await client();
    const result = await sb.from("quotes").update({ status: status }).eq("id", quoteId).select("*").single();
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
    listRequests: listRequests,
    listQuotes: listQuotes,
    respondToTextRequest: respondToTextRequest,
    respondToFileRequest: respondToFileRequest,
    respondToQuote: respondToQuote,
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
    const destOk = dest && (/^[a-z-]+\.html$/.test(dest) || /^https:\/\/admin\.kridiyatravel\.com\//.test(dest));
    return destOk ? dest : "account.html";
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
          toast("Welcome back, " + user.name.split(" ")[0] + "!");
          location.href = loginRedirectTarget();
        } catch (err) {
          banner(form, err.message, "error");
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
            banner(form, err.message, "error");
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
            banner(form, "Account created. Check your email and click the confirmation link before logging in.", "success");
            form.reset();
            meter.style.width = "0";
            busy(form, false);
            return;
          }

          toast("Welcome to Kridiya Travel, " + user.name.split(" ")[0] + "!");
          location.href = "account.html";
        } catch (err) {
          banner(form, err.message, "error");
          busy(form, false);
        }
      });
    });
  }

  function requestsHTML(requests) {
    if (!requests.length) return "";
    return '<div class="enq-extra">' + requests.map(function (r) {
      if (r.responded_at) {
        const answer = r.kind === "file"
          ? (r.response_file_name ? "Uploaded: " + KridiyaAuth.escapeHTML(r.response_file_name) : "Uploaded")
          : KridiyaAuth.escapeHTML(r.response_text || "");
        return '<p class="form-note enq-extra-done">' + icon("check") + " " + KridiyaAuth.escapeHTML(r.label) + " — " + answer + "</p>";
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

  function quotesHTML(quotes) {
    if (!quotes.length) return "";
    return '<div class="enq-extra">' + quotes.map(function (q) {
      const amount = KridiyaAuth.escapeHTML(q.currency + " " + Number(q.price_amount).toLocaleString("en-GB"));
      const validity = q.valid_until
        ? "Valid until " + new Date(q.valid_until).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })
        : "";
      if (q.status === "sent") {
        return '<div class="quote-card">' +
          "<p><b>" + KridiyaAuth.escapeHTML(q.title) + "</b> — " + amount + "</p>" +
          (q.terms ? '<p class="form-note">' + KridiyaAuth.escapeHTML(q.terms) + "</p>" : "") +
          (validity ? '<p class="form-note">' + validity + "</p>" : "") +
          '<div class="quote-actions">' +
            '<button class="btn btn-primary" type="button" data-quote-id="' + q.id + '" data-action="accepted">Accept quote</button>' +
            '<button class="btn btn-outline" type="button" data-quote-id="' + q.id + '" data-action="declined">Decline</button>' +
          "</div></div>";
      }
      return '<p class="form-note enq-extra-done">' + icon("check") + " " + KridiyaAuth.escapeHTML(q.title) + " — " + amount +
        " (" + KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(q.status)) + ")</p>";
    }).join("") + "</div>";
  }

  function wireEnquiryExtras(listEl) {
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
        toast("Sent — thank you.");
        location.reload();
      } catch (err) {
        btn.disabled = false;
        toast(err.message);
      }
    });

    listEl.addEventListener("click", async function (e) {
      const btn = e.target.closest("[data-quote-id]");
      if (!btn) return;
      btn.disabled = true;
      try {
        await KridiyaAuth.respondToQuote(btn.dataset.quoteId, btn.dataset.action);
        toast(btn.dataset.action === "accepted" ? "Quote accepted." : "Quote declined.");
        location.reload();
      } catch (err) {
        btn.disabled = false;
        toast(err.message);
      }
    });
  }

  if (page === "account") {
    document.addEventListener("DOMContentLoaded", async function () {
      const user = await KridiyaAuth.currentUser();
      if (!user) {
        location.replace("login.html?next=account.html");
        return;
      }

      document.getElementById("acc-avatar").textContent = (user.name || "?").trim().charAt(0).toUpperCase();
      document.getElementById("acc-name").textContent = user.name;
      document.getElementById("acc-email").textContent = user.email;
      const since = user.createdAt ? new Date(user.createdAt) : null;
      document.getElementById("acc-since").textContent = since
        ? "Member since " + since.toLocaleDateString("en-GB", { month: "long", year: "numeric" })
        : "";
      refreshHeaderName(user);

      const listEl = document.getElementById("enq-list");
      try {
        const results = await Promise.all([
          KridiyaAuth.listBookings(),
          KridiyaAuth.listEnquiries(),
          KridiyaAuth.listRequests(),
          KridiyaAuth.listQuotes()
        ]);
        const bookings = results[0];
        const enquiries = results[1];
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
            id: null,
            isEnquiry: false,
            reference: booking.booking_reference,
            status: booking.status,
            title: booking.title,
            detail: booking.route_or_destination || booking.service_type,
            paxLabel: pax ? pax + " traveller" + (pax === 1 ? "" : "s") : "",
            amount: booking.amount ? (booking.currency + " " + Number(booking.amount).toLocaleString("en-GB")) : "Quote pending",
            created_at: booking.created_at
          };
        })).sort(function (a, b) { return new Date(b.created_at) - new Date(a.created_at); });

        const summaryBookings = document.getElementById("summary-bookings");
        if (summaryBookings) summaryBookings.textContent = String(combined.length);

        if (combined.length) {
          listEl.innerHTML = combined.map(function (item) {
            const created = new Date(item.created_at);
            const requests = item.isEnquiry ? (requestsByEnquiry[item.id] || []) : [];
            const quotes = item.isEnquiry ? (quotesByEnquiry[item.id] || []) : [];
            return '<div class="enq-item">' +
              '<div class="enq-top"><b>' + KridiyaAuth.escapeHTML(item.title) + "</b>" +
              '<time datetime="' + KridiyaAuth.escapeHTML(item.created_at) + '">' +
              created.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) +
              "</time></div>" +
              "<p>" +
              KridiyaAuth.escapeHTML(item.reference) + " - " +
              KridiyaAuth.escapeHTML(KridiyaAuth.statusLabel(item.status)) + " - " +
              KridiyaAuth.escapeHTML(item.detail || "") +
              (item.paxLabel ? " - " + item.paxLabel : "") + " - " +
              KridiyaAuth.escapeHTML(item.amount) +
              "</p>" +
              requestsHTML(requests) +
              quotesHTML(quotes) +
              "</div>";
          }).join("");
          wireEnquiryExtras(listEl);
        }
      } catch (err) {
        listEl.innerHTML = '<div class="form-banner error" role="alert">Could not load your enquiries yet: ' + KridiyaAuth.escapeHTML(err.message) + "</div>";
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
          toast(err.message);
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
          banner(pwf, err.message, "error");
        }
        busy(pwf, false);
      });

      document.getElementById("logout-btn").addEventListener("click", async function () {
        await KridiyaAuth.logout();
        location.href = "index.html";
      });
    });
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
          banner(form, err.message, "error");
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
          banner(form, err.message, "error");
        }
        busy(form, false);
      });
    });
  }
})();
