/* ============================================================
   Kridiya Travel — shared chrome, config & helpers
   ============================================================ */
"use strict";

document.documentElement.classList.add("js");

/* ---------- Business config ---------- */
const KRIDIYA = {
  brand: "Kridiya Travel",
  legal: "Kridiya Travel and Tourism FZ-LLC",
  slogan: "Your Journey, Our Passion.",
  address: "Ras Al Khaimah, United Arab Emirates",
  phoneDisplay: "+971 50 941 3873",
  phoneTel: "+971509413873",
  waNumber: "971509413873",
  emails: {
    enquiry: "enquiry@kridiyatravel.com",
    contact: "contact@kridiyatravel.com",
    info: "info@kridiyatravel.com",
    deals: "deals@kridiyatravel.com"
  },
  social: {
    instagram: "https://www.instagram.com/kridiyatravel/",
    facebook: "https://www.facebook.com/profile.php?id=61592086520680"
  }
};

const KRIDIYA_GA4_MEASUREMENT_ID = "G-LB1TW8J03E";
const KRIDIYA_META_DATASET_ID = "1584188866628210";
const ANALYTICS_CONSENT_KEY = "kridiya_analytics_consent";
const MARKETING_CONSENT_KEY = "kridiya_marketing_measurement_consent";

/* ---------- Marketing attribution and event queue ----------
   No personal information is stored here. GA4 and any future GTM container
   consume the same dataLayer events without changing the enquiry forms. */
const ATTRIBUTION_KEYS = [
  "utm_id", "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
  "gclid", "fbclid", "msclkid", "ttclid"
];
const ATTRIBUTION_FIRST_KEY = "kridiya_first_touch";
const ATTRIBUTION_LAST_KEY = "kridiya_last_touch";

function safeStorage(storage, action, key, value) {
  try {
    if (action === "get") return storage.getItem(key);
    storage.setItem(key, value);
  } catch (e) { /* Storage may be blocked; attribution stays best-effort. */ }
  return null;
}

function setAnalyticsConsent(value, persist) {
  const granted = value === "granted";
  window.gtag("consent", "update", {
    analytics_storage: granted ? "granted" : "denied",
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied"
  });
  if (persist) safeStorage(localStorage, "set", ANALYTICS_CONSENT_KEY, granted ? "granted" : "denied");
}

function initMetaPixel() {
  if (window.kridiyaMetaPixelLoaded) return;
  window.kridiyaMetaPixelLoaded = true;

  if (!window.fbq) {
    const fbq = function () {
      fbq.callMethod ? fbq.callMethod.apply(fbq, arguments) : fbq.queue.push(arguments);
    };
    if (!window._fbq) window._fbq = fbq;
    fbq.push = fbq;
    fbq.loaded = true;
    fbq.version = "2.0";
    fbq.queue = [];
    window.fbq = fbq;
  }

  window.fbq("init", KRIDIYA_META_DATASET_ID);
  window.fbq("consent", "grant");
  window.fbq("track", "PageView");

  if (!document.querySelector('script[data-kridiya-meta-pixel]')) {
    const script = document.createElement("script");
    script.async = true;
    script.dataset.kridiyaMetaPixel = "true";
    script.src = "https://connect.facebook.net/en_US/fbevents.js";
    document.head.appendChild(script);
  }
}

function setMarketingMeasurementConsent(value, persist) {
  const granted = value === "granted";
  if (persist) {
    safeStorage(localStorage, "set", MARKETING_CONSENT_KEY, granted ? "granted" : "denied");
  }
  if (granted) initMetaPixel();
  else if (window.fbq) window.fbq("consent", "revoke");
}

function resetMeasurementConsent() {
  try {
    localStorage.removeItem(ANALYTICS_CONSENT_KEY);
    localStorage.removeItem(MARKETING_CONSENT_KEY);
  } catch (e) { /* A reload still leaves the existing choice if storage is blocked. */ }
  location.reload();
}

function initGoogleAnalytics() {
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };

  window.gtag("consent", "default", {
    analytics_storage: "denied",
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied",
    wait_for_update: 500
  });

  const savedConsent = safeStorage(localStorage, "get", ANALYTICS_CONSENT_KEY);
  if (savedConsent === "granted" || savedConsent === "denied") {
    setAnalyticsConsent(savedConsent, false);
  }

  window.gtag("js", new Date());
  window.gtag("config", KRIDIYA_GA4_MEASUREMENT_ID, {
    send_page_view: true
  });

  if (!document.querySelector('script[data-kridiya-ga4]')) {
    const script = document.createElement("script");
    script.async = true;
    script.dataset.kridiyaGa4 = "true";
    script.src = "https://www.googletagmanager.com/gtag/js?id=" +
      encodeURIComponent(KRIDIYA_GA4_MEASUREMENT_ID);
    document.head.appendChild(script);
  }
}

function initAnalyticsConsentBanner() {
  const savedAnalytics = safeStorage(localStorage, "get", ANALYTICS_CONSENT_KEY);
  const savedMarketing = safeStorage(localStorage, "get", MARKETING_CONSENT_KEY);
  if (savedMarketing === "granted") initMetaPixel();
  if (savedAnalytics && savedMarketing) return;

  const banner = document.createElement("aside");
  banner.className = "analytics-consent";
  banner.setAttribute("aria-label", "Website measurement privacy choice");
  banner.innerHTML =
    '<div><b>Website measurement</b><p>Choose whether Kridiya may use privacy-safe analytics and Meta advertising measurement. We never send names, contact details, passport information, or payment details in these events.</p></div>' +
    '<div class="analytics-consent-actions">' +
      '<button class="btn btn-outline" type="button" data-measurement-choice="denied">No thanks</button>' +
      '<button class="btn btn-outline" type="button" data-measurement-choice="analytics">Analytics only</button>' +
      '<button class="btn btn-primary" type="button" data-measurement-choice="all">Allow both</button>' +
    "</div>";

  banner.addEventListener("click", function (event) {
    const button = event.target.closest("[data-measurement-choice]");
    if (!button) return;
    const choice = button.dataset.measurementChoice;
    setAnalyticsConsent(choice === "denied" ? "denied" : "granted", true);
    setMarketingMeasurementConsent(choice === "all" ? "granted" : "denied", true);
    banner.remove();
  });

  document.body.appendChild(banner);
}

function readStoredJSON(storage, key) {
  const raw = safeStorage(storage, "get", key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch (e) { return null; }
}

function classifyTraffic(touch) {
  const medium = String(touch.utm_medium || "").toLowerCase();
  if (touch.gclid || touch.fbclid || touch.msclkid || touch.ttclid ||
      /^(cpc|ppc|paid|paid_social|display|affiliate)$/.test(medium)) return "paid";
  if (/^(organic|seo)$/.test(medium)) return "organic";
  if (touch.referrer) return "referral";
  return touch.utm_source ? "unknown" : "direct";
}

function sourceFromTouch(touch) {
  if (touch.utm_source) return touch.utm_source;
  if (touch.gclid) return "google";
  if (touch.fbclid) return "meta";
  if (touch.msclkid) return "microsoft";
  if (touch.ttclid) return "tiktok";
  if (touch.referrer) {
    try { return new URL(touch.referrer).hostname.replace(/^www\./, ""); }
    catch (e) { return "referral"; }
  }
  return "direct";
}

function captureAttribution() {
  const params = new URLSearchParams(location.search);
  const touch = {
    landing_page: location.href.slice(0, 1000),
    referrer: document.referrer ? document.referrer.slice(0, 1000) : "",
    captured_at: new Date().toISOString()
  };
  ATTRIBUTION_KEYS.forEach(function (key) {
    const value = params.get(key);
    if (value) touch[key] = value.slice(0, 500);
  });
  touch.source = sourceFromTouch(touch);
  touch.medium = touch.utm_medium || (touch.referrer ? "referral" : "none");
  touch.campaign = touch.utm_campaign || "";
  touch.traffic_type = classifyTraffic(touch);
  touch.source_basis = touch.utm_source || ATTRIBUTION_KEYS.some(function (k) { return touch[k]; })
    ? "campaign_parameter"
    : (touch.referrer ? "referrer" : "direct");
  touch.source_confidence = touch.source_basis === "campaign_parameter" ? "high" :
    (touch.source_basis === "referrer" ? "medium" : "low");

  if (!readStoredJSON(localStorage, ATTRIBUTION_FIRST_KEY)) {
    safeStorage(localStorage, "set", ATTRIBUTION_FIRST_KEY, JSON.stringify(touch));
  }
  safeStorage(sessionStorage, "set", ATTRIBUTION_LAST_KEY, JSON.stringify(touch));
  return touch;
}

function attributionPayload() {
  const first = readStoredJSON(localStorage, ATTRIBUTION_FIRST_KEY) || captureAttribution();
  const last = readStoredJSON(sessionStorage, ATTRIBUTION_LAST_KEY) || captureAttribution();
  return {
    first_touch_source: first.source || "direct",
    first_touch_medium: first.medium || "none",
    first_touch_campaign: first.campaign || null,
    last_touch_source: last.source || "direct",
    last_touch_medium: last.medium || "none",
    last_touch_campaign: last.campaign || null,
    utm_id: last.utm_id || null,
    utm_source: last.utm_source || null,
    utm_medium: last.utm_medium || null,
    utm_campaign: last.utm_campaign || null,
    utm_content: last.utm_content || null,
    utm_term: last.utm_term || null,
    gclid: last.gclid || null,
    fbclid: last.fbclid || null,
    msclkid: last.msclkid || null,
    ttclid: last.ttclid || null,
    landing_page: last.landing_page || location.href,
    referrer: last.referrer || null,
    traffic_type: last.traffic_type || "unknown",
    source_basis: last.source_basis || "direct",
    source_confidence: last.source_confidence || "low"
  };
}

function trackEvent(name, properties, meta) {
  const payload = Object.assign({
    page_type: document.body.dataset.page || "unknown",
    service_type: document.body.dataset.widgetOnly || null
  }, properties || {});
  window.gtag("event", name, payload);
  trackMetaEvent(name, payload, meta);
}

function trackMetaEvent(name, properties, meta) {
  if (safeStorage(localStorage, "get", MARKETING_CONSENT_KEY) !== "granted" ||
      typeof window.fbq !== "function") return;

  const safe = {
    content_name: properties.service_type || properties.enquiry_type || properties.page_type || "general",
    content_category: properties.page_type || "website"
  };
  if (properties.method) safe.method = properties.method;
  if (properties.link_location) safe.link_location = String(properties.link_location).slice(0, 100);

  const standardEvents = {
    view_service: "ViewContent",
    submit_enquiry: "Lead",
    newsletter_signup: "Subscribe",
    register_account: "CompleteRegistration",
    click_whatsapp: "Contact",
    click_call: "Contact",
    click_email: "Contact"
  };
  const standardName = standardEvents[name];
  const eventOptions = meta && meta.eventId ? { eventID: meta.eventId } : undefined;
  if (standardName) window.fbq("track", standardName, safe, eventOptions);
  else window.fbq("trackCustom", name, safe, eventOptions);
}

function generateMetaEventId(prefix) {
  const random = window.crypto && typeof window.crypto.randomUUID === "function"
    ? window.crypto.randomUUID()
    : Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
  return (prefix || "event") + "-" + random;
}

function readCookie(name) {
  const prefix = encodeURIComponent(name) + "=";
  const match = document.cookie.split(";").map(function (part) { return part.trim(); })
    .find(function (part) { return part.indexOf(prefix) === 0; });
  return match ? decodeURIComponent(match.slice(prefix.length)) : null;
}

async function sendMetaLeadServerEvent(eventId, serviceType, enquiryType) {
  if (safeStorage(localStorage, "get", MARKETING_CONSENT_KEY) !== "granted") return;
  const sb = await KridiyaAuth.client();
  const result = await sb.functions.invoke("meta-conversions", {
    body: {
      event_name: "Lead",
      event_id: eventId,
      event_source_url: location.href,
      client_user_agent: navigator.userAgent,
      fbp: readCookie("_fbp"),
      fbc: readCookie("_fbc"),
      custom_data: {
        content_name: serviceType || enquiryType || "general",
        content_category: document.body.dataset.page || "website"
      }
    }
  });
  if (result.error) throw result.error;
}

initGoogleAnalytics();
captureAttribution();

function waLink(message) {
  return "https://wa.me/" + KRIDIYA.waNumber + (message ? "?text=" + encodeURIComponent(message) : "");
}

/* ---------- SVG icon paths (24x24 viewBox) ---------- */
const ICONS = {
  phone: "M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.2.2 2.4.6 3.6.1.3 0 .7-.2 1l-2.3 2.2z",
  mail: "M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z",
  pin: "M12 2C8.1 2 5 5.1 5 9c0 5.2 7 13 7 13s7-7.8 7-13c0-3.9-3.1-7-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z",
  plane: "M21.5 15.5 13 10.7V4.5C13 3.7 12.3 3 11.5 3S10 3.7 10 4.5v6.2l-8.5 4.8v2l8.5-2.7v5.4L8 21.7V23l3.5-1 3.5 1v-1.3l-2-1.5v-5.4l8.5 2.7v-2z",
  hotel: "M7 13a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm12-6h-8v7H5V5H3v14h2v-2h14v2h2v-9a4 4 0 0 0-4-4z",
  globe: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm7 9h-3a15 15 0 0 0-1.3-5.7A8 8 0 0 1 19 11zM12 4.1c.9 1.2 1.8 3.5 2 6.9h-4c.2-3.4 1.1-5.7 2-6.9zM5 13h3a15 15 0 0 0 1.3 5.7A8 8 0 0 1 5 13zm4.3-2H5a8 8 0 0 1 4.3-5.7A15 15 0 0 0 9.3 11zM12 19.9c-.9-1.2-1.8-3.5-2-6.9h4c-.2 3.4-1.1 5.7-2 6.9zm2.7-1.2A15 15 0 0 0 16 13h3a8 8 0 0 1-4.3 5.7z",
  suitcase: "M9 6V4c0-1.1.9-2 2-2h2c1.1 0 2 .9 2 2v2h3c1.1 0 2 .9 2 2v11c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2V8c0-1.1.9-2 2-2h3zm2-2v2h2V4h-2zM8 9v9h1.5V9H8zm6.5 0v9H16V9h-1.5z",
  passport: "M6 2c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2H6zm6 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8zm0 1.6c.5.7 1 1.7 1.1 2.4h-2.2c.1-.7.6-1.7 1.1-2.4zM9.7 10c-.2-.6-.1-1 .1-1.5.3-.5.8-.8 1.2-1-.4.8-.7 1.7-.7 2.5h-.6zm4 0c0-.8-.3-1.7-.7-2.5.4.2.9.5 1.2 1 .2.5.3.9.1 1.5h-.6zM9.7 12h.6c0 .8.3 1.7.7 2.5-.4-.2-.9-.5-1.2-1-.2-.5-.3-.9-.1-1.5zm4.6 0h.6c.2.6.1 1-.1 1.5-.3.5-.8.8-1.2 1 .4-.8.7-1.7.7-2.5zM8 17h8v1.5H8V17z",
  whatsapp: "M12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3 .8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1-.2.2-.6.8-.8 1-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.4-3c-.3-.4 0-.5.2-.7l.4-.5c.1-.2.2-.3.3-.5v-.5c0-.1-.6-1.4-.8-1.9-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.2.3-.9.9-.9 2.2s1 2.5 1.1 2.7c.1.2 1.9 3 4.7 4.2.7.3 1.2.5 1.6.6.7.2 1.3.2 1.8.1.6-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.1-1.2l-.4-.3z",
  instagram: "M12 2.2c3.2 0 3.6 0 4.9.1 1.2.1 1.8.2 2.2.4.6.2 1 .5 1.4.9.4.4.7.8.9 1.4.2.4.4 1 .4 2.2.1 1.3.1 1.7.1 4.9s0 3.6-.1 4.9c-.1 1.2-.2 1.8-.4 2.2-.2.6-.5 1-.9 1.4-.4.4-.8.7-1.4.9-.4.2-1 .4-2.2.4-1.3.1-1.7.1-4.9.1s-3.6 0-4.9-.1c-1.2-.1-1.8-.2-2.2-.4-.6-.2-1-.5-1.4-.9-.4-.4-.7-.8-.9-1.4-.2-.4-.4-1-.4-2.2C2.2 15.6 2.2 15.2 2.2 12s0-3.6.1-4.9c.1-1.2.2-1.8.4-2.2.2-.6.5-1 .9-1.4.4-.4.8-.7 1.4-.9.4-.2 1-.4 2.2-.4C8.4 2.2 8.8 2.2 12 2.2zm0 1.8c-3.1 0-3.5 0-4.8.1-1.1.1-1.5.2-1.9.3-.5.2-.8.4-1.1.7-.3.3-.5.6-.7 1.1-.1.4-.3.8-.3 1.9-.1 1.3-.1 1.7-.1 4.8s0 3.5.1 4.8c.1 1.1.2 1.5.3 1.9.2.5.4.8.7 1.1.3.3.6.5 1.1.7.4.1.8.3 1.9.3 1.3.1 1.7.1 4.8.1s3.5 0 4.8-.1c1.1-.1 1.5-.2 1.9-.3.5-.2.8-.4 1.1-.7.3-.3.5-.6.7-1.1.1-.4.3-.8.3-1.9.1-1.3.1-1.7.1-4.8s0-3.5-.1-4.8c-.1-1.1-.2-1.5-.3-1.9-.2-.5-.4-.8-.7-1.1-.3-.3-.6-.5-1.1-.7-.4-.1-.8-.3-1.9-.3-1.3-.1-1.7-.1-4.8-.1zm0 3.1a5 5 0 1 1 0 9.9 5 5 0 0 1 0-9.9zm0 1.8a3.1 3.1 0 1 0 0 6.3 3.1 3.1 0 0 0 0-6.3zm5.1-2.2a1.2 1.2 0 1 1 0 2.3 1.2 1.2 0 0 1 0-2.3z",
  facebook: "M22 12a10 10 0 1 0-11.6 9.9v-7H7.9V12h2.5V9.8c0-2.5 1.5-3.9 3.8-3.9 1.1 0 2.2.2 2.2.2v2.5h-1.3c-1.2 0-1.6.8-1.6 1.6V12h2.8l-.4 2.9h-2.4v7A10 10 0 0 0 22 12z",
  shield: "M12 1 3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-2 16-4-4 1.4-1.4L10 14.2l6.6-6.6L18 9l-8 8z",
  clock: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4.2 14.2L11 13.3V7h1.5v5.4l4.5 2.7-.8 1.1z",
  tag: "M21.4 11.6 12.4 2.6A2 2 0 0 0 11 2H4a2 2 0 0 0-2 2v7c0 .5.2 1 .6 1.4l9 9c.8.8 2 .8 2.8 0l7-7c.8-.8.8-2 0-2.8zM6.5 8A1.5 1.5 0 1 1 8 6.5 1.5 1.5 0 0 1 6.5 8z",
  users: "M16 11c1.7 0 3-1.3 3-3s-1.3-3-3-3-3 1.3-3 3 1.3 3 3 3zm-8 0c1.7 0 3-1.3 3-3S9.7 5 8 5 5 6.3 5 8s1.3 3 3 3zm0 2c-2.3 0-7 1.2-7 3.5V19h14v-2.5C15 14.2 10.3 13 8 13zm8 0h-1.1c1.2.8 2.1 1.9 2.1 3.5V19h6v-2.5c0-2.3-4.7-3.5-7-3.5z",
  swap: "M6.99 11 3 15l3.99 4v-3H14v-2H6.99v-3zM21 9l-3.99-4v3H10v2h7.01v3L21 9z",
  calendar: "M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zM5 8V6h14v2H5z",
  menu: "M3 6h18v2H3V6zm0 5h18v2H3v-2zm0 5h18v2H3v-2z",
  close: "M19 6.4 17.6 5 12 10.6 6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12 19 6.4z",
  star: "M12 17.3 6.2 21l1.6-6.6L2.5 9.9l6.8-.5L12 3l2.7 6.4 6.8.5-5.3 4.5L17.8 21z",
  check: "M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z",
  inbox: "M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 12h-4a3 3 0 0 1-6 0H5V5h14v10z",
  chevronLeft: "M15.4 6 9.4 12l6 6 1.4-1.4L12.2 12l4.6-4.6z",
  chevronRight: "M8.6 6 14.6 12l-6 6-1.4-1.4L11.8 12 7.2 7.4z",
  plus: "M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z",
  trash: "M6 7h12l-1 13.1c-.1 1-.9 1.9-2 1.9H9c-1.1 0-1.9-.9-2-1.9zm3-3h6l1 2H8zM4 5h16v2H4z",
  route: "M4 6a3 3 0 1 1 4.9 2.3l3 3.6L18 9c-.6-.5-1-1.3-1-2.1a3 3 0 1 1 3.9 2.9l-6.6 6.6a1 1 0 0 1-1.4 0L7 10.6 4 14.3V19h13v2H4a2 2 0 0 1-2-2v-5.3a2 2 0 0 1 .4-1.2l3-4A3 3 0 0 1 4 6z",
  ship: "M20 21c-1.4 0-2.8-.5-4-1.3-2.4 1.7-5.6 1.7-8 0-1.2.8-2.6 1.3-4 1.3H2v2h2c1.4 0 2.7-.3 4-1 2.5 1.3 5.5 1.3 8 0 1.3.7 2.6 1 4 1h2v-2h-2zM4 11l1.3.4L4 12l-.3-.2-.6 2.1c0 .2 0 .5.1.7L4 15c1.6 0 3-.9 4-2 1 1.1 2.4 2 4 2s3-.9 4-2c1 1.1 2.4 2 4 2l.8-.5c.1-.2.2-.5.1-.7l-1.9-6.7c-.1-.3-.3-.5-.6-.6L20 6.6V4c0-1.1-.9-2-2-2h-3V1H9v3H6c-1.1 0-2 .9-2 2v.6L4 11zM6 6h12v3.9L12 8 6 9.9V6z",
  kaaba: "M12 2 4 6.5v11L12 22l8-4.5v-11L12 2zm0 2.3 5.8 3.3L12 10.9 6.2 7.6 12 4.3zM6 9.2l5 2.9v6.8l-5-2.8V9.2zm7 9.7v-6.8l5-2.9v6.8l-5 2.9z"
};

function icon(name, cls) {
  return '<svg class="' + (cls || "") + '" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="' + ICONS[name] + '"/></svg>';
}

/* ---------- Logo (uploaded KD artwork, shared by header and footer) ---------- */
function logoHTML(footer) {
  return (
    '<a class="logo" href="index.html" aria-label="Kridiya Travel — home">' +
      '<img class="logo-art" src="assets/logo.png" alt="Kridiya Travel and Tourism" width="256" height="256" decoding="async">' +
    "</a>"
  );
}

/* ---------- Site chrome ---------- */
const NAV_ITEMS = [
  ["index.html", "Home"],
  ["flights.html", "Flights"],
  ["hotels.html", "Hotels"],
  ["holidays.html", "Holidays"],
  ["umrah.html", "Umrah"],
  ["cruise.html", "Cruise"],
  ["visa.html", "Visa"],
  ["https://corporate.kridiyatravel.com", "Business Travel"],
  ["about.html", "About Us"],
  ["contact.html", "Contact"]
];

function currentPage() {
  const p = location.pathname.split("/").pop();
  return p === "" ? "index.html" : p;
}

function renderChrome() {
  const page = currentPage();
  const header = document.getElementById("site-header");
  if (header) {
    header.innerHTML =
      '<div class="topbar"><div class="container topbar-inner">' +
        '<div class="topbar-group">' +
          '<span class="topbar-item">' + icon("phone") + '<a href="tel:' + KRIDIYA.phoneTel + '">' + KRIDIYA.phoneDisplay + "</a></span>" +
          '<span class="topbar-item optional">' + icon("mail") + '<a href="mailto:' + KRIDIYA.emails.info + '">' + KRIDIYA.emails.info + "</a></span>" +
          '<span class="topbar-item optional">' + icon("pin") + "<span>" + KRIDIYA.address + "</span></span>" +
        "</div>" +
        '<div class="topbar-social">' +
          '<a class="icon-instagram" href="' + KRIDIYA.social.instagram + '" target="_blank" rel="noopener" aria-label="Kridiya Travel on Instagram">' + icon("instagram") + "</a>" +
          '<a class="icon-facebook" href="' + KRIDIYA.social.facebook + '" target="_blank" rel="noopener" aria-label="Kridiya Travel on Facebook">' + icon("facebook") + "</a>" +
          '<a class="icon-whatsapp" href="' + waLink() + '" target="_blank" rel="noopener" aria-label="Chat with Kridiya Travel on WhatsApp">' + icon("whatsapp") + "</a>" +
        "</div>" +
      "</div></div>" +
      '<div class="container header-inner">' +
        logoHTML(false) +
        '<button class="nav-toggle" aria-label="Open menu" aria-expanded="false" aria-controls="main-nav">' + icon("menu") + "</button>" +
        '<nav class="main-nav" id="main-nav" aria-label="Main navigation"><ul>' +
          NAV_ITEMS.map(function (it) {
            const cur = it[0] === page ? ' aria-current="page"' : "";
            return '<li><a href="' + it[0] + '"' + cur + ">" + it[1] + "</a></li>";
          }).join("") +
        "</ul></nav>" +
        '<div class="header-actions">' +
          '<a class="header-call" href="tel:' + KRIDIYA.phoneTel + '">' + icon("phone") +
            "<span><small>Call our team</small>" + KRIDIYA.phoneDisplay + "</span></a>" +
          '<a class="btn btn-primary" href="login.html" id="account-btn">Login</a>' +
        "</div>" +
      "</div>" +
      '<button class="nav-backdrop" aria-hidden="true" tabindex="-1"></button>';

    const nav = header.querySelector(".main-nav");
    const toggle = header.querySelector(".nav-toggle");
    const backdrop = header.querySelector(".nav-backdrop");
    function setNav(open) {
      nav.classList.toggle("open", open);
      backdrop.classList.toggle("show", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.innerHTML = icon(open ? "close" : "menu");
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    }
    toggle.addEventListener("click", function () { setNav(!nav.classList.contains("open")); });
    backdrop.addEventListener("click", function () { setNav(false); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("open")) setNav(false);
    });

    // Reflect signed-in state
    const session = window.KridiyaAuth ? KridiyaAuth.session() : null;
    if (session) {
      const btn = document.getElementById("account-btn");
      btn.textContent = "Hi, " + session.name.split(" ")[0];
      btn.href = "account.html";
    }
  }

  const footer = document.getElementById("site-footer");
  if (footer) {
    footer.innerHTML =
      '<div class="container">' +
      '<div class="footer-grid">' +
        '<div class="footer-brand">' + logoHTML(true) +
          "<p>" + KRIDIYA.legal + " is a licensed travel house in " + KRIDIYA.address +
          ". Flights, hotels, holidays, visas and Umrah — handled end to end by real travel experts.</p>" +
          '<div class="footer-social">' +
            '<a class="icon-instagram" href="' + KRIDIYA.social.instagram + '" target="_blank" rel="noopener" aria-label="Instagram">' + icon("instagram") + "</a>" +
            '<a class="icon-facebook" href="' + KRIDIYA.social.facebook + '" target="_blank" rel="noopener" aria-label="Facebook">' + icon("facebook") + "</a>" +
            '<a class="icon-whatsapp" href="' + waLink() + '" target="_blank" rel="noopener" aria-label="WhatsApp">' + icon("whatsapp") + "</a>" +
          "</div>" +
        "</div>" +
      "<div><h4>Our Services</h4><ul class=\"footer-links\">" +
          '<li><a href="flights.html">Flight Booking</a></li>' +
          '<li><a href="hotels.html">Hotel Booking</a></li>' +
          '<li><a href="holidays.html">Holiday Packages</a></li>' +
          '<li><a href="cruise.html">Cruise Packages</a></li>' +
          '<li><a href="umrah.html">Umrah Packages</a></li>' +
          '<li><a href="visa.html">Visa Services</a></li>' +
          '<li><a href="https://corporate.kridiyatravel.com">Business Travel</a></li>' +
          '<li><a href="contact.html">Travel Insurance</a></li>' +
        "</ul></div>" +
        "<div><h4>Company</h4><ul class=\"footer-links\">" +
          '<li><a href="about.html">About Us</a></li>' +
          '<li><a href="contact.html">Contact Us</a></li>' +
          '<li><a href="login.html">Customer Login</a></li>' +
          '<li><a href="https://corporate.kridiyatravel.com/login.html?next=corporate-account.html">Corporate Portal</a></li>' +
          '<li><a href="register.html">Create Account</a></li>' +
          '<li><a href="privacy.html">Privacy Policy</a></li>' +
          '<li><a href="unsubscribe.html">Unsubscribe from offers</a></li>' +
          '<li><a href="terms.html">Terms &amp; Conditions</a></li>' +
          '<li><a href="about.html#faq">FAQs</a></li>' +
        "</ul></div>" +
        "<div><h4>Get in Touch</h4><ul class=\"footer-contact\">" +
          "<li>" + icon("pin") + "<span>" + KRIDIYA.legal + "<br>" + KRIDIYA.address + "</span></li>" +
          "<li>" + icon("phone") + '<a href="tel:' + KRIDIYA.phoneTel + '">' + KRIDIYA.phoneDisplay + "</a></li>" +
          "<li>" + icon("mail") + '<a href="mailto:' + KRIDIYA.emails.info + '">' + KRIDIYA.emails.info + "</a></li>" +
        "</ul>" +
        "<h4>Deals in your inbox</h4>" +
        '<form class="newsletter-form" id="newsletter-form" method="POST" action="https://formsubmit.co/' + KRIDIYA.emails.deals + '">' +
          '<input type="hidden" name="_subject" value="Newsletter subscription — kridiyatravel.com">' +
          '<input type="hidden" name="_captcha" value="false">' +
          '<input type="hidden" name="_template" value="table">' +
          '<input type="email" name="email" placeholder="Your email address" required aria-label="Email address for newsletter">' +
          '<button class="btn btn-primary" type="submit">Join</button>' +
          '<label class="newsletter-consent"><input type="checkbox" name="Marketing_consent" value="Yes" required> ' +
          'I agree to receive travel offers by email. I can opt out at any time. See the <a href="privacy.html">privacy policy</a>.</label>' +
        "</form></div>" +
      "</div>" +
      '<div class="footer-routes"><h4>Popular flight routes</h4><p>' +
        [["DXB", "Dubai", "COK", "Kochi"], ["DXB", "Dubai", "BOM", "Mumbai"], ["DXB", "Dubai", "DEL", "Delhi"],
         ["SHJ", "Sharjah", "MNL", "Manila"], ["DXB", "Dubai", "KHI", "Karachi"], ["DXB", "Dubai", "DAC", "Dhaka"],
         ["DXB", "Dubai", "CAI", "Cairo"], ["DXB", "Dubai", "IST", "Istanbul"], ["DXB", "Dubai", "LHR", "London"],
         ["DXB", "Dubai", "TBS", "Tbilisi"], ["DXB", "Dubai", "BKK", "Bangkok"], ["DXB", "Dubai", "CCJ", "Kozhikode"]]
        .map(function (r) {
          return '<a href="flights.html?trip=round&from=' + r[0] + "&fromCity=" + r[1] + "&to=" + r[2] + "&toCity=" + r[3] +
            '&adults=1&children=0&infants=0&cabin=Economy">' + r[1] + " to " + r[3] + " flights</a>";
        }).join('<span class="dot" aria-hidden="true"> · </span>') +
      "</p></div>" +
      "</div>" +
      '<div class="footer-bar"><div class="container footer-legal">' +
        "<span>© " + new Date().getFullYear() + " " + KRIDIYA.legal + ". All rights reserved.</span>" +
        '<span class="slogan-line">' + KRIDIYA.slogan + "</span>" +
      "</div></div>";
    prepareFormSubmit(footer.querySelector("#newsletter-form"));
  }

  // Floating WhatsApp
  const wa = document.createElement("a");
  wa.className = "wa-float";
  wa.href = waLink("Hello Kridiya Travel! I have a travel enquiry.");
  wa.target = "_blank";
  wa.rel = "noopener";
  wa.setAttribute("aria-label", "Chat with us on WhatsApp");
  wa.innerHTML = icon("whatsapp") + "<span>WhatsApp us</span>";
  document.body.appendChild(wa);
}

/* ---------- Toast ---------- */
let toastTimer = null;
function toast(msg) {
  let el = document.querySelector(".toast");
  if (!el) {
    el = document.createElement("div");
    el.className = "toast";
    el.setAttribute("role", "status");
    document.body.appendChild(el);
  }
  el.textContent = msg;
  requestAnimationFrame(function () { el.classList.add("show"); });
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { el.classList.remove("show"); }, 4200);
}

/* ---------- FormSubmit plumbing ----------
   Every enquiry/contact form POSTs to https://formsubmit.co/<inbox>.
   Forms tagged data-enquiry-type also get a KD-XXX-##### reference,
   get written to Supabase (so the enquiry can be tracked on the account
   and admin pages), and hand the reference to thanks.html. The footer
   newsletter form has no data-enquiry-type and keeps submitting natively. */
const SERVICE_TYPE_RULES = [
  [/flight/i, "flight"],
  [/hotel/i, "hotel"],
  [/holiday/i, "holiday"],
  [/visa/i, "visa"],
  [/umrah/i, "umrah"],
  [/cruise/i, "cruise"]
];
const SERVICE_PREFIX = { flight: "FLT", hotel: "HTL", holiday: "HOL", visa: "VSA", umrah: "UMR", cruise: "CRU", other: "ENQ" };

function serviceTypeFromLabel(label) {
  const hit = SERVICE_TYPE_RULES.find(function (r) { return r[0].test(label || ""); });
  return hit ? hit[1] : "other";
}

function generateReference(serviceType) {
  const prefix = SERVICE_PREFIX[serviceType] || "ENQ";
  const stamp = Date.now().toString(36).toUpperCase().slice(-5);
  const rand = Math.random().toString(36).toUpperCase().slice(2, 5);
  return "KD-" + prefix + "-" + stamp + rand;
}

function gatherEnquiryFields(form) {
  const data = new FormData(form);
  const details = {};
  const parts = [];
  data.forEach(function (v, k) {
    if (k.charAt(0) === "_" || k === "Name" || k === "Email" || k === "Phone") return;
    const val = String(v).trim();
    if (!val) return;
    details[k] = val;
    parts.push(k.replace(/_/g, " ") + ": " + val);
  });
  return {
    fullName: String(data.get("Name") || "").trim(),
    email: String(data.get("Email") || "").trim(),
    phone: String(data.get("Phone") || "").trim(),
    marketingConsent: data.get("Marketing_consent") === "Yes",
    details: details,
    summary: parts.join(" · ")
  };
}

async function submitEnquiryToSupabase(fields, serviceType, reference) {
  const sb = await KridiyaAuth.client();
  const session = KridiyaAuth.session();
  const attribution = attributionPayload();
  const baseRecord = {
    reference: reference,
    user_id: session ? session.id : null,
    service_type: serviceType,
    full_name: fields.fullName,
    email: fields.email,
    phone: fields.phone || null,
    summary: fields.summary || "Enquiry",
    details: Object.assign({}, fields.details, { attribution: attribution })
  };
  let result = await sb.from("enquiries").insert(Object.assign({}, baseRecord, attribution, {
    marketing_consent: fields.marketingConsent,
    marketing_consent_at: fields.marketingConsent ? new Date().toISOString() : null,
    marketing_consent_source: fields.marketingConsent ? "website_enquiry" : null,
    marketing_consent_version: fields.marketingConsent ? "privacy-2026-07" : null
  }));
  if (result.error && (result.error.code === "PGRST204" || result.error.code === "42703")) {
    console.warn("Kridiya: attribution migration is not applied yet; saving the legacy enquiry record.");
    result = await sb.from("enquiries").insert(baseRecord);
  }
  if (result.error) throw result.error;
}

async function submitNewsletterConsent(email) {
  const sb = await KridiyaAuth.client();
  const a = attributionPayload();
  const result = await sb.from("marketing_subscription_events").insert({
    email: email,
    consent: true,
    consent_source: "website_footer",
    consent_version: "privacy-2026-07",
    first_touch_source: a.first_touch_source,
    first_touch_medium: a.first_touch_medium,
    first_touch_campaign: a.first_touch_campaign,
    last_touch_source: a.last_touch_source,
    last_touch_medium: a.last_touch_medium,
    last_touch_campaign: a.last_touch_campaign,
    landing_page: a.landing_page,
    referrer: a.referrer
  });
  if (result.error) throw result.error;
}

function formSubmitAjaxURL(form) {
  return form.action.replace("https://formsubmit.co/", "https://formsubmit.co/ajax/");
}

async function sendFormSubmitAjax(form, reference) {
  const data = new FormData(form);
  const payload = { Reference: reference };
  data.forEach(function (v, k) { payload[k] = v; });
  await fetch(formSubmitAjaxURL(form), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(payload)
  });
}

function restoreSubmitButton(btn, label) {
  if (!btn) return;
  btn.disabled = false;
  btn.textContent = label || "Send enquiry";
}

function stashEnquiryForThanksPage(reference, serviceType, summary, typeLabel, name) {
  try {
    sessionStorage.setItem("kridiya_last_enquiry", JSON.stringify({
      reference: reference,
      serviceType: serviceType,
      typeLabel: typeLabel,
      summary: summary,
      name: name,
      at: new Date().toISOString()
    }));
  } catch (e) { /* best-effort */ }
}

function prepareFormSubmit(form) {
  if (!form) return;
  if (form.dataset.kridiyaPrepared === "true") return;
  form.dataset.kridiyaPrepared = "true";
  if (form.dataset.enquiryType && !form.querySelector('input[name="Marketing_consent"]')) {
    const submitButton = form.querySelector('button[type="submit"]');
    if (submitButton) {
      submitButton.insertAdjacentHTML("beforebegin",
        '<label class="form-consent"><input type="checkbox" name="Marketing_consent" value="Yes"> ' +
        "Send me occasional travel offers by email. I can opt out at any time.</label>");
    }
  }
  let next = form.querySelector('input[name="_next"]');
  if (!next) {
    next = document.createElement("input");
    next.type = "hidden";
    next.name = "_next";
    form.appendChild(next);
  }
  next.value = new URL("thanks.html", location.href).href;

  let started = false;
  form.addEventListener("focusin", function () {
    if (started) return;
    started = true;
    trackEvent("start_enquiry", { enquiry_type: form.dataset.enquiryType || "newsletter" });
  });

  form.addEventListener("submit", function (e) {
    if (!validateForm(form)) { e.preventDefault(); return; }

    const type = form.dataset.enquiryType;
    if (!type) {
      e.preventDefault();
      const emailInput = form.querySelector('input[type="email"]');
      const newsletterButton = form.querySelector('button[type="submit"]');
      const newsletterLabel = newsletterButton ? newsletterButton.textContent : "Join";
      if (newsletterButton) newsletterButton.disabled = true;
      Promise.allSettled([
        submitNewsletterConsent(emailInput.value.trim()),
        sendFormSubmitAjax(form, "NEWSLETTER")
      ]).then(function (results) {
        if (results[0].status === "rejected") {
          console.error("Kridiya: could not record newsletter consent", results[0].reason);
        }
        if (results[1].status === "rejected") {
          console.error("Kridiya: could not email newsletter consent", results[1].reason);
        }
        if (results.every(function (r) { return r.status === "rejected"; })) {
          restoreSubmitButton(newsletterButton, newsletterLabel);
          toast("We could not save your subscription. Please try again.");
          return;
        }
        trackEvent("newsletter_signup", { method: "website_footer" });
        form.reset();
        restoreSubmitButton(newsletterButton, newsletterLabel);
        toast("Thank you. Your email preferences have been recorded.");
      });
      return;
    }

    e.preventDefault();
    const btn = form.querySelector('button[type="submit"]');
    const originalButtonLabel = btn ? btn.textContent : "";
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner" aria-hidden="true"></span> Sending…';
    }

    const serviceType = serviceTypeFromLabel(type);
    const reference = generateReference(serviceType);
    const fields = gatherEnquiryFields(form);
    const dest = next.value;

    Promise.allSettled([
      submitEnquiryToSupabase(fields, serviceType, reference),
      sendFormSubmitAjax(form, reference)
    ]).then(async function (results) {
      const savedToSupabase = results[0].status === "fulfilled";
      const emailedToTeam = results[1].status === "fulfilled";

      if (!savedToSupabase) console.error("Kridiya: could not save enquiry to Supabase", results[0].reason);
      if (!emailedToTeam) console.error("Kridiya: could not email enquiry", results[1].reason);

      if (!savedToSupabase && !emailedToTeam) {
        restoreSubmitButton(btn, originalButtonLabel);
        toast("We could not send this enquiry. Please try again or WhatsApp us on +971 50 941 3873.");
        return;
      }

      const metaEventId = generateMetaEventId("lead");
      trackEvent("submit_enquiry", {
        enquiry_type: type,
        service_type: serviceType,
        reference: reference,
        saved_to_crm: savedToSupabase
      }, { eventId: metaEventId });
      try {
        await sendMetaLeadServerEvent(metaEventId, serviceType, type);
      } catch (error) {
        console.warn("Kridiya: server-side Meta lead measurement was unavailable.", error);
      }
      stashEnquiryForThanksPage(reference, serviceType, fields.summary, type, fields.fullName);
      location.href = dest;
    });
  });
}

/* ---------- Validation ---------- */
const RE_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const RE_PHONE = /^\+?[0-9\s\-()]{7,17}$/;

function setFieldError(input, msg) {
  const field = input.closest(".field, .form-consent, .newsletter-consent");
  if (!field) return;
  let err = field.querySelector(".err");
  if (!err) {
    err = document.createElement("span");
    err.className = "err";
    field.appendChild(err);
  }
  if (msg) {
    field.classList.add("invalid");
    err.textContent = msg;
  } else {
    field.classList.remove("invalid");
    err.textContent = "";
  }
}

function validateForm(form) {
  let ok = true, first = null;
  form.querySelectorAll("input[required], select[required], textarea[required]").forEach(function (input) {
    if (input.type === "hidden") return;
    let msg = "";
    const v = input.value.trim();
    if (input.type === "checkbox" && !input.checked) msg = "Please confirm this choice.";
    else if (!v) msg = "This field is required.";
    else if (input.type === "email" && !RE_EMAIL.test(v)) msg = "Enter a valid email address.";
    else if (input.type === "tel" && !RE_PHONE.test(v)) msg = "Enter a valid phone number (e.g. +971 50 941 3873).";
    setFieldError(input, msg);
    if (msg) { ok = false; if (!first) first = input; }
  });
  if (first) first.focus();
  return ok;
}

/* Clear errors as the user types */
document.addEventListener("input", function (e) {
  if (e.target.matches(".field input, .field select, .field textarea")) setFieldError(e.target, "");
});

/* ---------- Reveal-on-scroll (enhance-only; content visible without JS) ---------- */
function initReveal() {
  if (!("IntersectionObserver" in window)) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.querySelectorAll(".reveal").forEach(function (el) { el.classList.add("in"); });
    return;
  }
  const io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
    });
  }, { rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll(".reveal").forEach(function (el) { io.observe(el); });
}

/* ---------- Date helpers ----------
   Always format dates from local Y/M/D, never toISOString() — that
   converts to UTC first and silently rolls the date back or forward
   a day depending on the visitor's timezone offset. */
function localISO(d) {
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
function todayISO(offsetDays) {
  const d = new Date();
  d.setDate(d.getDate() + (offsetDays || 0));
  return localISO(d);
}
function initDateMins() {
  document.querySelectorAll('input[type="date"][data-min-today]').forEach(function (el) {
    el.min = todayISO(0);
    if (!el.value) el.value = todayISO(parseInt(el.dataset.defaultOffset || "3", 10));
  });
}

function fmtDate(iso) {
  if (!iso) return "";
  const d = new Date(iso + "T00:00:00");
  return d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
}

/* ---------- Boot ---------- */
document.addEventListener("DOMContentLoaded", function () {
  renderChrome();
  initAnalyticsConsentBanner();
  initDateMins();
  document.querySelectorAll("form[data-formsubmit]").forEach(prepareFormSubmit);
  initReveal();
  trackEvent("view_service", {
    service_type: document.body.dataset.widgetOnly || document.body.dataset.page || "general"
  });
});

document.addEventListener("click", function (e) {
  const resetConsent = e.target.closest("[data-reset-measurement-consent]");
  if (resetConsent) {
    resetMeasurementConsent();
    return;
  }
  const link = e.target.closest("a[href]");
  if (!link) return;
  const href = link.getAttribute("href") || "";
  if (/whatsapp/i.test(href)) trackEvent("click_whatsapp", { link_location: link.className || "content" });
  else if (/^tel:/i.test(href)) trackEvent("click_call", { link_location: link.className || "content" });
  else if (/^mailto:/i.test(href)) trackEvent("click_email", { link_location: link.className || "content" });
});
