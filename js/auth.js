/* ============================================================
   Kridiya Travel — customer accounts
   Client-side auth: PBKDF2-SHA256 (150k iterations, random salt)
   via WebCrypto. Accounts live in this browser's localStorage —
   swap this module for a real API when a backend is available.
   ============================================================ */
"use strict";

window.KridiyaAuth = (function () {
  const USERS_KEY = "kridiya_users";
  const SESSION_KEY = "kridiya_session";
  const ITERATIONS = 150000;
  const MAX_ATTEMPTS = 5;
  const LOCK_MINUTES = 5;

  /* ---------- storage ---------- */
  function users() {
    try { return JSON.parse(localStorage.getItem(USERS_KEY) || "{}"); }
    catch (e) { return {}; }
  }
  function saveUsers(u) { localStorage.setItem(USERS_KEY, JSON.stringify(u)); }

  function session() {
    try {
      const raw = sessionStorage.getItem(SESSION_KEY) || localStorage.getItem(SESSION_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  }
  function setSession(user, remember) {
    const payload = JSON.stringify({ email: user.email, name: user.name, at: Date.now() });
    (remember ? localStorage : sessionStorage).setItem(SESSION_KEY, payload);
  }
  function logout() {
    sessionStorage.removeItem(SESSION_KEY);
    localStorage.removeItem(SESSION_KEY);
  }

  /* ---------- crypto ---------- */
  function toHex(buf) {
    return Array.from(new Uint8Array(buf)).map(function (b) { return b.toString(16).padStart(2, "0"); }).join("");
  }
  function cryptoOK() {
    return !!(window.crypto && crypto.subtle && crypto.getRandomValues);
  }
  async function hashPassword(password, saltHex) {
    const enc = new TextEncoder();
    const salt = new Uint8Array(saltHex.match(/.{2}/g).map(function (h) { return parseInt(h, 16); }));
    const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
    const bits = await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt: salt, iterations: ITERATIONS }, key, 256
    );
    return toHex(bits);
  }
  function newSalt() {
    const s = new Uint8Array(16);
    crypto.getRandomValues(s);
    return toHex(s.buffer);
  }

  /* ---------- lockout ---------- */
  function lockState(email) {
    try { return JSON.parse(localStorage.getItem("kridiya_lock_" + email) || "null"); }
    catch (e) { return null; }
  }
  function noteFailure(email) {
    const st = lockState(email) || { count: 0, until: 0 };
    st.count += 1;
    if (st.count >= MAX_ATTEMPTS) {
      st.until = Date.now() + LOCK_MINUTES * 60000;
      st.count = 0;
    }
    localStorage.setItem("kridiya_lock_" + email, JSON.stringify(st));
    return st;
  }
  function clearFailures(email) { localStorage.removeItem("kridiya_lock_" + email); }
  function lockedUntil(email) {
    const st = lockState(email);
    return st && st.until && st.until > Date.now() ? st.until : 0;
  }

  /* ---------- public API ---------- */
  async function register(opts) {
    if (!cryptoOK()) throw new Error("Secure login needs HTTPS (or localhost). Please open the site via a web server.");
    const email = opts.email.trim().toLowerCase();
    const all = users();
    if (all[email]) throw new Error("An account with this email already exists. Try logging in instead.");
    const salt = newSalt();
    const hash = await hashPassword(opts.password, salt);
    all[email] = {
      name: opts.name.trim(),
      email: email,
      phone: opts.phone.trim(),
      salt: salt,
      hash: hash,
      iterations: ITERATIONS,
      createdAt: new Date().toISOString()
    };
    saveUsers(all);
    setSession(all[email], true);
    return all[email];
  }

  async function login(email, password, remember) {
    if (!cryptoOK()) throw new Error("Secure login needs HTTPS (or localhost). Please open the site via a web server.");
    email = email.trim().toLowerCase();
    const until = lockedUntil(email);
    if (until) {
      const mins = Math.ceil((until - Date.now()) / 60000);
      throw new Error("Too many failed attempts. Try again in " + mins + " minute" + (mins > 1 ? "s" : "") + ".");
    }
    const user = users()[email];
    const hash = user ? await hashPassword(password, user.salt) : null;
    if (!user || hash !== user.hash) {
      noteFailure(email);
      throw new Error("Incorrect email or password.");
    }
    clearFailures(email);
    setSession(user, remember);
    return user;
  }

  async function changePassword(email, current, next) {
    const all = users();
    const user = all[email];
    if (!user) throw new Error("Account not found.");
    const curHash = await hashPassword(current, user.salt);
    if (curHash !== user.hash) throw new Error("Your current password is incorrect.");
    user.salt = newSalt();
    user.hash = await hashPassword(next, user.salt);
    saveUsers(all);
  }

  function updateProfile(email, fields) {
    const all = users();
    const user = all[email];
    if (!user) throw new Error("Account not found.");
    if (fields.name) user.name = fields.name.trim();
    if (fields.phone) user.phone = fields.phone.trim();
    saveUsers(all);
    const s = session();
    if (s && s.email === email) setSession(user, !!localStorage.getItem(SESSION_KEY));
    return user;
  }

  function getUser(email) { return users()[email] || null; }

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
    return score; // 0–5
  }

  return {
    session: session, register: register, login: login, logout: logout,
    changePassword: changePassword, updateProfile: updateProfile, getUser: getUser,
    passwordIssue: passwordIssue, passwordStrength: passwordStrength
  };
})();

/* ============================================================
   Page wiring (login / register / account)
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

  /* ---------- Login ---------- */
  if (page === "login") {
    if (KridiyaAuth.session()) { location.replace("account.html"); return; }
    const form = document.getElementById("login-form");
    initPwToggles(form);
    form.addEventListener("submit", async function (e) {
      e.preventDefault();
      if (!validateForm(form)) return;
      banner(form, "");
      busy(form, true, "Signing in…");
      try {
        const user = await KridiyaAuth.login(
          form.email.value, form.password.value, form.remember.checked
        );
        toast("Welcome back, " + user.name.split(" ")[0] + "!");
        const dest = new URLSearchParams(location.search).get("next");
        location.href = dest && /^[a-z-]+\.html/.test(dest) ? dest : "account.html";
      } catch (err) {
        banner(form, err.message, "error");
        busy(form, false);
      }
    });
  }

  /* ---------- Register ---------- */
  if (page === "register") {
    if (KridiyaAuth.session()) { location.replace("account.html"); return; }
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
      if (issue) { setFieldError(form.password, issue); form.password.focus(); return; }
      if (form.password.value !== form.confirm.value) {
        setFieldError(form.confirm, "Passwords do not match.");
        form.confirm.focus();
        return;
      }
      banner(form, "");
      busy(form, true, "Creating account…");
      try {
        const user = await KridiyaAuth.register({
          name: form.name.value, email: form.email.value,
          phone: form.phone.value, password: form.password.value
        });
        toast("Welcome to Kridiya Travel, " + user.name.split(" ")[0] + "!");
        location.href = "account.html";
      } catch (err) {
        banner(form, err.message, "error");
        busy(form, false);
      }
    });
  }

  /* ---------- Account ---------- */
  if (page === "account") {
    const s = KridiyaAuth.session();
    if (!s) { location.replace("login.html?next=account.html"); return; }
    const user = KridiyaAuth.getUser(s.email) || s;

    document.addEventListener("DOMContentLoaded", function () {
      // Profile summary
      document.getElementById("acc-avatar").textContent = (user.name || "?").trim().charAt(0).toUpperCase();
      document.getElementById("acc-name").textContent = user.name;
      document.getElementById("acc-email").textContent = user.email;
      const since = user.createdAt ? new Date(user.createdAt) : null;
      document.getElementById("acc-since").textContent = since
        ? "Member since " + since.toLocaleDateString("en-GB", { month: "long", year: "numeric" })
        : "";

      // Enquiry history
      const listEl = document.getElementById("enq-list");
      let list = [];
      try { list = JSON.parse(localStorage.getItem("kridiya_enquiries_" + user.email) || "[]"); } catch (e) {}
      if (list.length) {
        listEl.innerHTML = list.map(function (q) {
          const d = new Date(q.at);
          return '<div class="enq-item"><div class="enq-top"><b>' + q.type + "</b>" +
            '<time datetime="' + q.at + '">' + d.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) + "</time></div>" +
            "<p>" + q.summary.replace(/</g, "&lt;") + "</p></div>";
        }).join("");
      }

      // Profile form
      const pf = document.getElementById("profile-form");
      pf.name.value = user.name || "";
      pf.phone.value = user.phone || "";
      pf.addEventListener("submit", function (e) {
        e.preventDefault();
        if (!validateForm(pf)) return;
        KridiyaAuth.updateProfile(user.email, { name: pf.name.value, phone: pf.phone.value });
        toast("Profile updated.");
        document.getElementById("acc-name").textContent = pf.name.value;
        const btn = document.getElementById("account-btn");
        if (btn) btn.textContent = "Hi, " + pf.name.value.split(" ")[0];
      });

      // Password form
      const pwf = document.getElementById("password-form");
      initPwToggles(pwf);
      pwf.addEventListener("submit", async function (e) {
        e.preventDefault();
        if (!validateForm(pwf)) return;
        const issue = KridiyaAuth.passwordIssue(pwf.newpass.value);
        if (issue) { setFieldError(pwf.newpass, issue); return; }
        banner(pwf, "");
        busy(pwf, true, "Updating…");
        try {
          await KridiyaAuth.changePassword(user.email, pwf.current.value, pwf.newpass.value);
          banner(pwf, "Password updated successfully.", "success");
          pwf.reset();
        } catch (err) {
          banner(pwf, err.message, "error");
        }
        busy(pwf, false);
      });

      // Logout
      document.getElementById("logout-btn").addEventListener("click", function () {
        KridiyaAuth.logout();
        location.href = "index.html";
      });
    });
  }
})();

