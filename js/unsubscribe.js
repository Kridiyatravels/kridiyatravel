"use strict";

(function () {
  const form = document.getElementById("unsubscribe-form");
  const status = document.getElementById("unsubscribe-status");
  if (!form || !status) return;

  function setStatus(message, type) {
    status.textContent = message;
    status.className = "preference-status " + (type || "");
  }

  async function submitPreference(body) {
    const client = await window.KridiyaAuth.client();
    const result = await client.functions.invoke("marketing-unsubscribe", { body: body });
    if (result.error) throw result.error;
    return result.data || {};
  }

  const linkToken = new URLSearchParams(window.location.search).get("token");
  if (linkToken) {
    setStatus("Confirming your email preference…", "pending");
    submitPreference({ token: linkToken }).then(function () {
      form.hidden = true;
      setStatus("You have been unsubscribed from Kridiya Travel promotional emails.", "success");
      window.history.replaceState({}, document.title, window.location.pathname);
    }).catch(function (error) {
      console.error("Kridiya: signed unsubscribe failed", error);
      setStatus("This unsubscribe link is invalid or expired. Enter your email to request a new one.", "error");
    });
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    const emailInput = form.elements.email;
    const honeypot = form.elements.company;
    const button = form.querySelector('button[type="submit"]');
    const email = String(emailInput.value || "").trim().toLowerCase();

    if (honeypot && honeypot.value) {
      setStatus("Your email preferences have been updated.", "success");
      form.reset();
      return;
    }
    if (!emailInput.checkValidity()) {
      emailInput.reportValidity();
      return;
    }

    button.disabled = true;
    setStatus("Updating your email preferences…", "pending");
    try {
      await submitPreference({ email: email });
      form.reset();
      setStatus("Check your inbox and confirm the unsubscribe request. The link expires in 24 hours.", "success");
    } catch (error) {
      console.error("Kridiya: unsubscribe request failed", error);
      setStatus("We could not update your preference. Please try again or email deals@kridiyatravel.com.", "error");
    } finally {
      button.disabled = false;
    }
  });
})();
