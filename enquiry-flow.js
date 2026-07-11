(function(){
  "use strict";

  var CONFIG = window.KRIDIYA_ENQUIRY_CONFIG || {};
  var SECTION_LABELS = {
    packages: "Holiday Package",
    honeymoon: "Honeymoon",
    umrah: "Umrah & Hajj",
    corporate: "Corporate",
    cruises: "Cruise",
    visa: "Visa"
  };

  function normalize(text){
    return (text || "").replace(/\s+/g, " ").trim();
  }

  function slugify(text){
    return normalize(text).toLowerCase()
      .replace(/&/g, "and")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "travel-enquiry";
  }

  function getText(root, selector){
    var el = root && root.querySelector(selector);
    return el ? normalize(el.textContent) : "";
  }

  function splitMeta(text){
    var clean = normalize(text);
    var parts = clean.split(/\s+-\s+/);
    if(parts.length > 1){
      return {
        duration: normalize(parts[0]),
        price: normalize(parts.slice(1).join(" - "))
      };
    }
    return { duration: "", price: clean };
  }

  function sectionCategory(card, trigger){
    if(trigger && trigger.getAttribute("data-category")) return trigger.getAttribute("data-category");
    if(card && card.getAttribute("data-category-label")) return card.getAttribute("data-category-label");
    var section = trigger && trigger.closest("section[id]");
    if(section && SECTION_LABELS[section.id]) return SECTION_LABELS[section.id];
    if(document.getElementById("cruises")) return "Cruise";
    return "Travel";
  }

  function collectDetails(trigger){
    var card = trigger.closest("[data-enquiry-item], .ecard, .hcard, .tier, .corp-enquiry-card, .depart-box, .vs-card");
    var item = trigger.getAttribute("data-item") ||
      (card && card.getAttribute("data-enquiry-item")) ||
      getText(card, ".ecard-name, .hcard-name, .tier-name, .corp-enquiry-title, .vs-card-country") ||
      "Travel enquiry";

    var category = sectionCategory(card, trigger);
    var duration = trigger.getAttribute("data-duration") || "";
    var price = trigger.getAttribute("data-price") || "";

    if(card && card.classList.contains("hcard")){
      var h = splitMeta(getText(card, ".hcard-price"));
      price = price || h.duration || h.price;
      duration = duration || h.price;
    } else if(card && card.classList.contains("tier")){
      var tierPrice = getText(card, ".tier-price");
      var tierPp = getText(card, ".tier-pp");
      var pp = splitMeta(tierPp);
      price = price || normalize(tierPrice + " " + (pp.duration || tierPp).replace(/^per person/i, "per person"));
      duration = duration || pp.price || tierPp.replace(/^.*-\s*/, "");
    } else if(card){
      var meta = splitMeta(getText(card, ".ecard-meta"));
      duration = duration || meta.duration;
      price = price || meta.price;
    }

    return {
      item: item,
      category: category,
      duration: duration || trigger.getAttribute("data-duration") || "Custom",
      price: price || trigger.getAttribute("data-price") || "Custom quote",
      slug: trigger.getAttribute("data-slug") || slugify(item),
      source: location.pathname.split("/").pop() || "site"
    };
  }

  function buildEnquireUrl(details){
    var params = new URLSearchParams();
    params.set("item", details.item || "Travel enquiry");
    params.set("category", details.category || "Travel");
    params.set("duration", details.duration || "Custom");
    params.set("price", details.price || "Custom quote");
    params.set("slug", details.slug || slugify(details.item));
    params.set("source", details.source || "");
    return "enquire.html?" + params.toString();
  }

  function attachEnquireLinks(scope){
    var root = scope || document;
    root.querySelectorAll("[data-enquire]").forEach(function(trigger){
      if(trigger.closest("#enquiryForm")) return;
      var url = buildEnquireUrl(collectDetails(trigger));
      if(trigger.tagName.toLowerCase() === "a"){
        trigger.setAttribute("href", url);
        trigger.removeAttribute("target");
        trigger.removeAttribute("rel");
      }
      trigger.addEventListener("click", function(e){
        e.preventDefault();
        window.location.href = url;
      });
    });
  }

  function parseQuery(){
    var params = new URLSearchParams(window.location.search);
    return {
      item: params.get("item") || "Travel enquiry",
      category: params.get("category") || "Travel",
      duration: params.get("duration") || "Custom",
      price: params.get("price") || "Custom quote",
      slug: params.get("slug") || "travel-enquiry",
      source: params.get("source") || "",
      travelDates: params.get("travelDates") || "",
      adults: params.get("adults") || "",
      children: params.get("children") || "",
      infants: params.get("infants") || "",
      cabinClass: params.get("cabinClass") || "",
      farePreference: params.get("farePreference") || "",
      directOnly: params.get("directOnly") || "",
      message: params.get("message") || ""
    };
  }

  function saveLocalBackup(payload, status){
    var key = "kridiyaEnquiryBackup";
    var list = [];
    try { list = JSON.parse(localStorage.getItem(key) || "[]"); }
    catch(e){ list = []; }
    list.push({
      status: status || "pending",
      savedAt: new Date().toISOString(),
      payload: payload
    });
    try { localStorage.setItem(key, JSON.stringify(list.slice(-50))); }
    catch(e){ /* local storage can be unavailable in private browsing */ }
  }

  function validEmail(value){
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  function setError(field, message){
    if(!field) return;
    field.classList.add("error");
    var msg = field.querySelector(".field-error");
    if(msg) msg.textContent = message || "Required";
  }

  function clearError(field){
    if(!field) return;
    field.classList.remove("error");
    var msg = field.querySelector(".field-error");
    if(msg) msg.textContent = "";
  }

  function isFlightEnquiry(item){
    return String(item.category || "").toLowerCase() === "flights" || /flights\.html/i.test(item.source || "");
  }

  function pluralCount(value, singular, plural){
    var num = Number(value);
    if(!Number.isFinite(num) || num <= 0) return "";
    return num + " " + (num === 1 ? singular : plural);
  }

  function travellersText(item){
    var parts = [
      pluralCount(item.adults || 1, "Adult", "Adults"),
      pluralCount(item.children, "Child", "Children"),
      pluralCount(item.infants, "Infant", "Infants")
    ].filter(Boolean);
    return parts.join(", ") || "1 Adult";
  }

  function directText(value){
    if(String(value).toLowerCase() === "yes") return "Direct flights only";
    if(String(value).toLowerCase() === "no") return "Stops allowed";
    return "";
  }

  function showLockedFlightDetails(item){
    var card = document.getElementById("selectedFlightCard");
    if(!card) return;

    var preferenceParts = [
      item.farePreference ? item.farePreference + " fare" : "",
      directText(item.directOnly)
    ].filter(Boolean);

    document.getElementById("selectedTravelDates").textContent = item.travelDates || item.duration || "Selected";
    document.getElementById("selectedTravellers").textContent = travellersText(item);
    document.getElementById("selectedCabin").textContent = item.cabinClass || "Selected";
    document.getElementById("selectedPreference").textContent = preferenceParts.join(" | ") || item.price || "Selected";

    card.hidden = false;
    ["travelDatesField", "adultsField", "childrenField"].forEach(function(id){
      var field = document.getElementById(id);
      if(field) field.classList.add("is-hidden");
    });
  }

  function initEnquiryPage(){
    var form = document.getElementById("enquiryForm");
    if(!form) return;

    var item = parseQuery();
    var itemName = document.getElementById("itemName");
    var itemCategory = document.getElementById("itemCategory");
    var itemDuration = document.getElementById("itemDuration");
    var itemPrice = document.getElementById("itemPrice");
    var endpointNotice = document.getElementById("endpointNotice");
    var flexible = document.getElementById("flexibleDates");
    var dates = document.getElementById("travelDates");
    var adultsInput = document.getElementById("adults");
    var childrenInput = document.getElementById("children");

    itemName.textContent = item.item;
    itemCategory.textContent = item.category;
    itemDuration.textContent = item.duration;
    itemPrice.textContent = item.price;

    if(!CONFIG.formSubmitEndpoint && endpointNotice){
      endpointNotice.hidden = false;
    }

    flexible.addEventListener("change", function(){
      dates.disabled = flexible.checked;
      if(flexible.checked) dates.value = "";
    });

    if(item.travelDates){
      if(item.travelDates.toLowerCase() === "flexible"){
        flexible.checked = true;
        dates.disabled = true;
      } else {
        dates.value = item.travelDates;
      }
    }
    if(item.adults) adultsInput.value = item.adults;
    if(item.children) childrenInput.value = item.children;
    if(item.message) document.getElementById("message").value = item.message;
    if(isFlightEnquiry(item)) showLockedFlightDetails(item);

    form.querySelectorAll("input, textarea").forEach(function(el){
      el.addEventListener("input", function(){ clearError(el.closest(".form-field")); });
    });

    form.addEventListener("submit", function(e){
      e.preventDefault();

      var fullName = normalize(document.getElementById("fullName").value);
      var phone = normalize(document.getElementById("phone").value);
      var email = normalize(document.getElementById("email").value);
      var adults = normalize(document.getElementById("adults").value);
      var children = normalize(document.getElementById("children").value);
      var message = normalize(document.getElementById("message").value);
      var valid = true;

      if(!fullName){ setError(document.getElementById("fullName").closest(".form-field"), "Full name is required"); valid = false; }
      if(!phone){ setError(document.getElementById("phone").closest(".form-field"), "Phone number is required"); valid = false; }
      if(!email || !validEmail(email)){ setError(document.getElementById("email").closest(".form-field"), "Valid email is required"); valid = false; }
      if(!adults || Number(adults) < 1){ setError(document.getElementById("adults").closest(".form-field"), "At least 1 adult is required"); valid = false; }
      if(children === "" || Number(children) < 0){ setError(document.getElementById("children").closest(".form-field"), "Use 0 if no children"); valid = false; }

      if(!valid){
        var first = form.querySelector(".form-field.error input, .form-field.error textarea");
        if(first) first.focus();
        return;
      }

      var payload = {
        itemName: item.item,
        itemSlug: item.slug,
        category: item.category,
        duration: item.duration,
        price: item.price,
        sourcePage: item.source,
        fullName: fullName,
        phone: phone,
        email: email,
        travelDates: flexible.checked ? "Flexible" : normalize(dates.value),
        flexibleDates: flexible.checked,
        adults: adults,
        children: children,
        infants: item.infants || "0",
        cabinClass: item.cabinClass,
        farePreference: item.farePreference,
        directOnly: item.directOnly,
        message: message,
        submittedAt: new Date().toISOString(),
        pageUrl: window.location.href,
        userAgent: navigator.userAgent
      };

      var submit = document.getElementById("submitEnquiry");
      var formStatus = document.getElementById("formStatus");
      submit.disabled = true;
      submit.textContent = "Submitting...";
      formStatus.textContent = "";
      saveLocalBackup(payload, "pending");

      if(!CONFIG.formSubmitEndpoint){
        submit.disabled = false;
        submit.textContent = "Submit Enquiry";
        formStatus.textContent = "Business email is set to " + (CONFIG.businessEmail || "your email") + ", but automatic sending needs a FormSubmit endpoint in enquiry-config.js.";
        formStatus.className = "form-status error";
        return;
      }

      fetch(CONFIG.formSubmitEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: JSON.stringify({
          _subject: "New travel enquiry: " + item.item,
          "Full Name": fullName,
          "Phone / WhatsApp": phone,
          "Email": email,
          "Item": item.item,
          "Category": item.category,
          "Duration": item.duration,
          "Price": item.price,
          "Travel Dates": payload.travelDates,
          "Adults": adults,
          "Children": children,
          "Infants": payload.infants,
          "Cabin Class": payload.cabinClass,
          "Fare Preference": payload.farePreference,
          "Direct Flights Only": payload.directOnly,
          "Message": message,
          "Source Page": item.source,
          "Page URL": payload.pageUrl,
          "Submitted At": payload.submittedAt
        })
      }).then(function(response){
        if(!response.ok) throw new Error("FormSubmit request failed");
        return response.json();
      }).then(function(){
        saveLocalBackup(payload, "sent-to-endpoint");
        var params = new URLSearchParams();
        params.set("name", fullName);
        params.set("item", item.item);
        window.location.href = "thank-you.html?" + params.toString();
      }).catch(function(){
        submit.disabled = false;
        submit.textContent = "Submit Enquiry";
        formStatus.textContent = "We could not submit the form right now. Your details were saved in this browser as a backup. Please try again or use WhatsApp.";
        formStatus.className = "form-status error";
      });
    });
  }

  function initThankYouPage(){
    var page = document.getElementById("thankYouMessage");
    if(!page) return;
    var params = new URLSearchParams(window.location.search);
    var name = params.get("name") || "there";
    var item = params.get("item") || "your trip";
    page.textContent = "Thank you " + name + "! We have received your enquiry for " + item + ". Our team will contact you shortly.";
    var wa = document.getElementById("thankYouWhatsApp");
    if(wa){
      var text = "Hi Kridiya Travel! I just submitted an enquiry for " + item + " and would like a faster response.";
      wa.href = "https://wa.me/" + (CONFIG.whatsappNumber || "971509413873") + "?text=" + encodeURIComponent(text);
    }
  }

  window.KridiyaEnquiry = {
    attachEnquireLinks: attachEnquireLinks,
    collectDetails: collectDetails,
    url: buildEnquireUrl,
    slugify: slugify
  };

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", function(){
      attachEnquireLinks(document);
      initEnquiryPage();
      initThankYouPage();
    });
  } else {
    attachEnquireLinks(document);
    initEnquiryPage();
    initThankYouPage();
  }
})();
