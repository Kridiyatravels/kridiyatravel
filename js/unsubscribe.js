"use strict";

(function () {
  const form = document.getElementById("unsubscribe-form");
  const status = document.getElementById("unsubscribe-status");
  if (!form || !status) return;

  function setStatus(message, type) {
    status.textContent = message;
    status.className = "preference-status " + (type || "");
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
      const client = await window.KridiyaAuth.client();
      const result = await client.from("marketing_suppression_events").insert({
        email: email,
        source: "website_unsubscribe",
        requested_at: new Date().toISOString()
      });
      if (result.error) throw result.error;
      form.reset();
      setStatus("You have been unsubscribed from Kridiya Travel promotional emails.", "success");
    } catch (error) {
      console.error("Kridiya: unsubscribe request failed", error);
      setStatus("We could not update your preference. Please try again or email deals@kridiyatravel.com.", "error");
    } finally {
      button.disabled = false;
    }
  });
})();
