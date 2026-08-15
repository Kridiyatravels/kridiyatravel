"use strict";

document.addEventListener("DOMContentLoaded", async function () {
  const form = document.getElementById("track-enquiry-form");
  if (!form || !window.KridiyaAuth) return;
  const errorBox = form.querySelector(".form-banner.error");
  const successBox = form.querySelector(".form-banner.success");
  const button = form.querySelector('button[type="submit"]');
  const refInput = form.elements.reference;
  const emailInput = form.elements.email;
  const params = new URLSearchParams(location.search);
  const savedRef = sessionStorage.getItem("kridiya_track_reference") || params.get("ref") || "";
  const savedEmail = sessionStorage.getItem("kridiya_track_email") || "";
  refInput.value = savedRef.toUpperCase();
  emailInput.value = savedEmail;

  function message(box, value) {
    errorBox.hidden = true; successBox.hidden = true;
    box.textContent = value; box.hidden = false;
  }

  async function claim(reference) {
    const sb = await KridiyaAuth.client();
    const result = await sb.rpc("claim_my_enquiry", { p_reference: reference });
    if (result.error) throw result.error;
    sessionStorage.removeItem("kridiya_track_reference");
    sessionStorage.removeItem("kridiya_track_email");
    location.replace("account.html?claimed=1");
  }

  const user = await KridiyaAuth.currentUser();
  if (user && savedRef) {
    try { await claim(savedRef); }
    catch (error) { message(errorBox, "We could not match that reference to your verified account email. Check the reference or contact our team."); }
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    const reference = String(refInput.value || "").trim().toUpperCase();
    const email = String(emailInput.value || "").trim().toLowerCase();
    if (!/^KD-[A-Z]{3}-[A-Z0-9]{8}$/.test(reference) || !emailInput.validity.valid) {
      message(errorBox, "Enter a valid Kridiya reference and email address."); return;
    }
    button.disabled = true; button.textContent = "Checking...";
    try {
      const activeUser = await KridiyaAuth.currentUser();
      if (activeUser) {
        if (String(activeUser.email || "").toLowerCase() !== email) throw new Error("EMAIL_MISMATCH");
        await claim(reference); return;
      }
      const sb = await KridiyaAuth.client();
      const redirect = new URL("track-enquiry.html", location.href);
      redirect.searchParams.set("ref", reference);
      const result = await sb.auth.signInWithOtp({ email: email, options: { shouldCreateUser: true, emailRedirectTo: redirect.href } });
      if (result.error) throw result.error;
      sessionStorage.setItem("kridiya_track_reference", reference);
      sessionStorage.setItem("kridiya_track_email", email);
      message(successBox, "Check your email and open the one-time Kridiya sign-in link on this device. We will connect the enquiry after verification.");
    } catch (error) {
      message(errorBox, error && error.message === "EMAIL_MISMATCH" ? "You are signed in with a different email. Log out first or use the email shown in your account." : "We could not start verification. Please wait a moment and try again.");
    } finally {
      button.disabled = false; button.textContent = button.dataset.label || "Verify and track";
    }
  });
});
