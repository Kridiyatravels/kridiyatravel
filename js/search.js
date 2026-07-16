/* ============================================================
   Kridiya Travel — booking widget, airport autocomplete,
   custom date calendar, and search -> enquiry result panels.
   Requires: airports.js, main.js
   ============================================================ */
"use strict";

/* ---------- Airport autocomplete ---------- */
function searchAirports(q, limit) {
  q = q.trim().toLowerCase();
  if (q.length < 2) return [];
  const starts = [], cityHits = [], other = [];
  for (let i = 0; i < AIRPORTS.length; i++) {
    const a = AIRPORTS[i]; // [IATA, city, country, name]
    const iata = a[0].toLowerCase(), city = a[1].toLowerCase(),
          country = a[2].toLowerCase(), name = a[3].toLowerCase();
    if (iata === q || iata.indexOf(q) === 0) starts.push(a);
    else if (city.indexOf(q) === 0) cityHits.push(a);
    else if (city.indexOf(q) > 0 || name.indexOf(q) >= 0 || country.indexOf(q) === 0) other.push(a);
    if (starts.length >= limit && cityHits.length >= limit) break;
  }
  return starts.concat(cityHits, other).slice(0, limit || 8);
}

function attachAirportAC(input) {
  if (input.dataset.acInit) return;
  input.dataset.acInit = "1";
  const field = input.closest(".field");
  const list = document.createElement("ul");
  list.className = "ac-list";
  list.hidden = true;
  list.setAttribute("role", "listbox");
  field.appendChild(list);
  input.setAttribute("autocomplete", "off");
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-expanded", "false");
  let items = [], active = -1;

  function close() {
    list.hidden = true;
    input.setAttribute("aria-expanded", "false");
    active = -1;
  }
  function choose(a) {
    input.value = a[1] + " (" + a[0] + ")";
    input.dataset.iata = a[0];
    input.dataset.city = a[1];
    setFieldError(input, "");
    close();
  }
  function render() {
    if (!items.length) { close(); return; }
    list.innerHTML = items.map(function (a, i) {
      return '<li class="ac-item' + (i === active ? " active" : "") + '" role="option" data-i="' + i + '">' +
        '<span class="ac-code">' + a[0] + "</span>" +
        '<span class="ac-main"><span class="ac-city">' + a[1] + ", " + a[2] + "</span>" +
        '<span class="ac-name">' + a[3] + "</span></span></li>";
    }).join("");
    list.hidden = false;
    input.setAttribute("aria-expanded", "true");
  }

  input.addEventListener("input", function () {
    delete input.dataset.iata;
    items = searchAirports(input.value, 8);
    active = -1;
    render();
  });
  input.addEventListener("keydown", function (e) {
    if (list.hidden) return;
    if (e.key === "ArrowDown") { e.preventDefault(); active = (active + 1) % items.length; render(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); active = (active - 1 + items.length) % items.length; render(); }
    else if (e.key === "Enter" && active >= 0) { e.preventDefault(); choose(items[active]); }
    else if (e.key === "Escape") close();
  });
  list.addEventListener("pointerdown", function (e) {
    const li = e.target.closest(".ac-item");
    if (li) { e.preventDefault(); choose(items[+li.dataset.i]); }
  });
  input.addEventListener("blur", function () { setTimeout(close, 120); });
}

/* Resolve a typed value to an airport even without a dropdown pick */
function resolveAirport(input) {
  if (input.dataset.iata) return { iata: input.dataset.iata, city: input.dataset.city };
  const m = input.value.match(/\(([A-Za-z]{3})\)\s*$/);
  const q = m ? m[1] : input.value;
  const hit = searchAirports(q, 1)[0];
  return hit ? { iata: hit[0], city: hit[1] } : null;
}

/* ---------- Custom calendar date picker ----------
   Every date field is a hidden <input type=hidden name=X> (holds the ISO
   value the rest of the app reads) plus a button that opens a styled
   month-grid popover. Replaces native <input type=date> everywhere so the
   calendar looks and behaves the same across browsers. */
const WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];
const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function isoOf(y, m, d) {
  return y + "-" + String(m + 1).padStart(2, "0") + "-" + String(d).padStart(2, "0");
}

function dateFieldHTML(id, name, label, opts) {
  opts = opts || {};
  let attrs = ' data-date-name="' + name + '"';
  if (opts.minToday !== false) attrs += ' data-min-today="1"';
  if (opts.defaultOffset != null) attrs += ' data-default-offset="' + opts.defaultOffset + '"';
  if (opts.afterField) attrs += ' data-after-field="' + opts.afterField + '"';
  return (
    '<div class="field date-field"' + attrs + '>' +
      '<label for="' + id + '">' + label + '</label>' +
      '<input type="hidden" name="' + name + '">' +
      '<button type="button" class="fake-input date-btn placeholder" id="' + id + '" aria-haspopup="true" aria-expanded="false">' +
        (opts.placeholder || "Select date") +
      "</button>" +
    "</div>"
  );
}

function initDatePickers(scope) {
  scope.querySelectorAll(".date-field").forEach(function (field) {
    if (field.dataset.dpInit) return;
    field.dataset.dpInit = "1";
    const name = field.dataset.dateName;
    const hidden = field.querySelector('input[type="hidden"][name="' + name + '"]');
    const btn = field.querySelector(".date-btn");
    const form = field.closest("form");
    const placeholderText = btn.textContent;

    const pop = document.createElement("div");
    pop.className = "cal-pop";
    pop.hidden = true;
    field.appendChild(pop);

    let viewY, viewM;

    function minISO() {
      let min = field.dataset.minToday ? todayISO(0) : null;
      if (field.dataset.afterField && form) {
        const otherField = form.querySelector('.date-field[data-date-name="' + field.dataset.afterField + '"]');
        const other = otherField && otherField.querySelector('input[type="hidden"]');
        if (other && other.value) {
          const d = new Date(other.value + "T00:00:00");
          d.setDate(d.getDate() + 1);
          const afterISO = localISO(d);
          if (!min || afterISO > min) min = afterISO;
        }
      }
      return min;
    }

    function setValue(iso, silent) {
      hidden.value = iso || "";
      if (iso) {
        btn.textContent = fmtDate(iso);
        btn.classList.remove("placeholder");
      } else {
        btn.textContent = placeholderText;
        btn.classList.add("placeholder");
      }
      if (!silent) hidden.dispatchEvent(new Event("change", { bubbles: true }));
    }
    field._dateSet = setValue;
    field._dateMin = minISO;

    function render() {
      const min = minISO();
      const first = new Date(viewY, viewM, 1);
      const startDow = first.getDay();
      const daysInMonth = new Date(viewY, viewM + 1, 0).getDate();
      const todayIso = todayISO(0);
      let cells = "";
      for (let i = 0; i < startDow; i++) cells += '<span class="cal-cell empty"></span>';
      for (let d = 1; d <= daysInMonth; d++) {
        const iso = isoOf(viewY, viewM, d);
        const disabled = min && iso < min;
        const selected = hidden.value === iso;
        const isToday = iso === todayIso;
        cells += '<button type="button" class="cal-cell' + (selected ? " selected" : "") + (isToday ? " today" : "") +
          '" data-iso="' + iso + '"' + (disabled ? " disabled" : "") + '>' + d + "</button>";
      }
      const prevDisabled = min && new Date(viewY, viewM, 0) < new Date(min.slice(0, 4), +min.slice(5, 7) - 1, 1);
      pop.innerHTML =
        '<div class="cal-head">' +
          '<button type="button" class="cal-nav" data-dir="-1" aria-label="Previous month"' + (prevDisabled ? " disabled" : "") + ">" + icon("chevronLeft") + "</button>" +
          "<b>" + MONTH_NAMES[viewM] + " " + viewY + "</b>" +
          '<button type="button" class="cal-nav" data-dir="1" aria-label="Next month">' + icon("chevronRight") + "</button>" +
        "</div>" +
        '<div class="cal-dow">' + WEEKDAYS.map(function (w) { return "<span>" + w + "</span>"; }).join("") + "</div>" +
        '<div class="cal-grid">' + cells + "</div>";
    }

    function open() {
      scope.querySelectorAll(".cal-pop").forEach(function (p) { if (p !== pop) p.hidden = true; });
      const min = minISO();
      const base = hidden.value || min || todayISO(0);
      const cur = new Date(base + "T00:00:00");
      viewY = cur.getFullYear(); viewM = cur.getMonth();
      render();
      pop.hidden = false;
      btn.setAttribute("aria-expanded", "true");
    }
    function close() {
      pop.hidden = true;
      btn.setAttribute("aria-expanded", "false");
    }

    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      if (pop.hidden) open(); else close();
    });
    pop.addEventListener("click", function (e) {
      const nav = e.target.closest(".cal-nav");
      if (nav) {
        if (nav.disabled) return;
        viewM += +nav.dataset.dir;
        if (viewM < 0) { viewM = 11; viewY--; }
        if (viewM > 11) { viewM = 0; viewY++; }
        render();
        return;
      }
      const cell = e.target.closest(".cal-cell:not(.empty):not([disabled])");
      if (cell) { setValue(cell.dataset.iso); close(); }
    });
    document.addEventListener("pointerdown", function (e) {
      if (!pop.hidden && !field.contains(e.target)) close();
    });
    document.addEventListener("keydown", function (e) {
      if (!pop.hidden && e.key === "Escape") { close(); btn.focus(); }
    });

    // When a preceding date (e.g. depart) changes, re-clamp this field if it's now invalid
    if (field.dataset.afterField && form) {
      const otherField = form.querySelector('.date-field[data-date-name="' + field.dataset.afterField + '"]');
      const otherHidden = otherField && otherField.querySelector('input[type="hidden"]');
      if (otherHidden) {
        otherHidden.addEventListener("change", function () {
          const min = minISO();
          if (min && hidden.value && hidden.value < min) setValue(min);
        });
      }
    }
  });
}

function applyDateDefaults(scope) {
  scope.querySelectorAll(".date-field[data-default-offset]").forEach(function (field) {
    const hidden = field.querySelector('input[type="hidden"]');
    if (hidden && !hidden.value && field._dateSet) {
      let iso = todayISO(+field.dataset.defaultOffset);
      const min = field._dateMin ? field._dateMin() : null;
      if (min && iso < min) iso = min;
      field._dateSet(iso, true);
    }
  });
}

function getDateField(form, name) {
  return form.querySelector('.date-field[data-date-name="' + name + '"]');
}
function setDateFieldValue(form, name, iso) {
  const f = getDateField(form, name);
  if (f && f._dateSet) f._dateSet(iso);
}
function getDateFieldValue(form, name) {
  const f = getDateField(form, name);
  return f ? f.querySelector('input[type="hidden"]').value : "";
}

/* ---------- Travellers popover ---------- */
function initPaxPopover(panel) {
  const btn = panel.querySelector(".pax-btn");
  const pop = panel.querySelector(".pax-pop");
  if (!btn || !pop || btn.dataset.paxInit) return;
  btn.dataset.paxInit = "1";
  const counts = { adults: 1, children: 0, infants: 0 };
  const MAXTOTAL = 9;

  function label() {
    const total = counts.adults + counts.children + counts.infants;
    const cls = pop.querySelector('select[name="class"]').value;
    btn.textContent = total + " Traveller" + (total > 1 ? "s" : "") + " · " + cls;
    btn.dataset.adults = counts.adults;
    btn.dataset.children = counts.children;
    btn.dataset.infants = counts.infants;
    btn.dataset.class = cls;
  }
  function refresh() {
    pop.querySelectorAll(".pax-row").forEach(function (row) {
      const k = row.dataset.kind;
      row.querySelector("output").textContent = counts[k];
      const total = counts.adults + counts.children + counts.infants;
      row.querySelector('[data-dir="-1"]').disabled = counts[k] <= (k === "adults" ? 1 : 0);
      row.querySelector('[data-dir="1"]').disabled =
        total >= MAXTOTAL || (k === "infants" && counts.infants >= counts.adults);
    });
    label();
  }
  pop.addEventListener("click", function (e) {
    const b = e.target.closest("button[data-dir]");
    if (b) {
      counts[b.closest(".pax-row").dataset.kind] += +b.dataset.dir;
      refresh();
    }
    if (e.target.closest(".done")) { pop.hidden = true; btn.setAttribute("aria-expanded", "false"); }
  });
  pop.querySelector("select").addEventListener("change", label);
  btn.addEventListener("click", function () {
    pop.hidden = !pop.hidden;
    btn.setAttribute("aria-expanded", String(!pop.hidden));
  });
  document.addEventListener("pointerdown", function (e) {
    if (!pop.hidden && !pop.contains(e.target) && e.target !== btn) {
      pop.hidden = true;
      btn.setAttribute("aria-expanded", "false");
    }
  });
  refresh();
}

/* ---------- Multi-city flight segments ---------- */
const MAX_SEGMENTS = 4;

function segmentHTML(index) {
  return (
    '<div class="mc-seg" data-seg="' + index + '">' +
      '<div class="mc-seg-num">Leg ' + (index + 1) + "</div>" +
      '<div class="mc-seg-fields">' +
        '<div class="field"><label for="mc-from-' + index + '">FROM</label>' +
          '<input id="mc-from-' + index + '" data-airport data-seg-from="' + index + '" placeholder="City or airport" required></div>' +
        '<div class="field"><label for="mc-to-' + index + '">TO</label>' +
          '<input id="mc-to-' + index + '" data-airport data-seg-to="' + index + '" placeholder="City or airport" required></div>' +
        dateFieldHTML("mc-date-" + index, "seg-date-" + index, "DATE", { defaultOffset: 3 + index * 3 }) +
      "</div>" +
      (index >= 2 ? '<button type="button" class="mc-remove" data-remove="' + index + '" aria-label="Remove this flight">' + icon("trash") + "</button>" : '<span class="mc-remove-spacer"></span>') +
    "</div>"
  );
}

function initMultiCity(ff) {
  const mc = ff.querySelector(".mc-segments");
  if (!mc || mc.dataset.mcInit) return;
  mc.dataset.mcInit = "1";
  const addBtn = ff.querySelector(".mc-add");

  function wireSegment(seg) {
    seg.querySelectorAll("input[data-airport]").forEach(attachAirportAC);
    initDatePickers(seg);
    applyDateDefaults(seg);
  }
  function renumber() {
    Array.from(mc.children).forEach(function (seg, i) {
      seg.querySelector(".mc-seg-num").textContent = "Leg " + (i + 1);
    });
    addBtn.hidden = mc.children.length >= MAX_SEGMENTS;
  }

  // First two segments ship in the markup already; wire them.
  Array.from(mc.children).forEach(wireSegment);

  addBtn.addEventListener("click", function () {
    if (mc.children.length >= MAX_SEGMENTS) return;
    const div = document.createElement("div");
    div.innerHTML = segmentHTML(mc.children.length);
    const seg = div.firstElementChild;
    mc.appendChild(seg);
    wireSegment(seg);
    renumber();
  });
  mc.addEventListener("click", function (e) {
    const rm = e.target.closest(".mc-remove");
    if (rm) { rm.closest(".mc-seg").remove(); renumber(); }
  });
  renumber();
}

/* ---------- Widget tabs + forms ---------- */
function initSearchWidget(root, activeTab) {
  if (!root) return;
  const tabs = root.querySelectorAll(".widget-tab");
  const panels = root.querySelectorAll(".widget-panel");
  function select(name) {
    tabs.forEach(function (t) { t.setAttribute("aria-selected", String(t.dataset.tab === name)); });
    panels.forEach(function (p) { p.hidden = p.dataset.tab !== name; });
  }
  if (tabs.length > 1) {
    tabs.forEach(function (t) {
      t.addEventListener("click", function () { select(t.dataset.tab); });
    });
    select(activeTab || tabs[0].dataset.tab);
  } else {
    panels.forEach(function (p) { p.hidden = false; });
  }

  /* Flights */
  const ff = root.querySelector('form[data-tab-form="flights"]');
  if (ff) {
    ff.querySelectorAll("input[data-airport]").forEach(attachAirportAC);
    initDatePickers(ff);
    applyDateDefaults(ff);
    initPaxPopover(ff);
    initMultiCity(ff);

    const segRow = ff.querySelector(".seg-row");
    const mcWrap = ff.querySelector(".mc-wrap");
    function tripChanged() {
      const trip = ff.trip.value;
      const oneWay = trip === "oneway";
      const multi = trip === "multicity";
      segRow.hidden = multi;
      mcWrap.hidden = !multi;
      const returnField = getDateField(ff, "return");
      if (returnField) {
        returnField.style.opacity = oneWay ? 0.45 : 1;
        returnField.querySelector(".date-btn").disabled = oneWay;
        if (!oneWay && !getDateFieldValue(ff, "return")) setDateFieldValue(ff, "return", todayISO(6));
      }
    }
    ff.querySelectorAll('input[name="trip"]').forEach(function (r) { r.addEventListener("change", tripChanged); });
    tripChanged();

    const swap = ff.querySelector(".swap-btn");
    swap.addEventListener("click", function () {
      const a = ff.querySelector('input[name="from"]'), b = ff.querySelector('input[name="to"]');
      const tv = a.value, ti = a.dataset.iata, tc = a.dataset.city;
      a.value = b.value; b.value = tv;
      if (b.dataset.iata) { a.dataset.iata = b.dataset.iata; a.dataset.city = b.dataset.city; } else { delete a.dataset.iata; }
      if (ti) { b.dataset.iata = ti; b.dataset.city = tc; } else { delete b.dataset.iata; }
      swap.classList.toggle("spun");
    });

    ff.addEventListener("submit", function (e) {
      e.preventDefault();
      const pax = ff.querySelector(".pax-btn").dataset;

      if (ff.trip.value === "multicity") {
        const segs = Array.from(ff.querySelectorAll(".mc-seg"));
        const legs = [];
        let bad = false, prevDate = null;
        segs.forEach(function (seg, i) {
          const fromInput = seg.querySelector("[data-seg-from]");
          const toInput = seg.querySelector("[data-seg-to]");
          const from = resolveAirport(fromInput);
          const to = resolveAirport(toInput);
          const date = getDateFieldValue(ff, "seg-date-" + i);
          if (!from) { setFieldError(fromInput, "Pick a departure city."); bad = true; }
          if (!to) { setFieldError(toInput, "Pick a destination city."); bad = true; }
          if (from && to && from.iata === to.iata) { setFieldError(toInput, "Must differ from departure."); bad = true; }
          if (!date) { setFieldError(seg.querySelector(".date-btn"), "Choose a date."); bad = true; }
          else if (prevDate && date < prevDate) { setFieldError(seg.querySelector(".date-btn"), "Should not be before the previous flight."); bad = true; }
          if (date) prevDate = date;
          if (from && to && date) legs.push({ from: from.iata, fromCity: from.city, to: to.iata, toCity: to.city, date: date });
        });
        if (bad) return;
        const p = new URLSearchParams({ trip: "multicity", legs: legs.length, adults: pax.adults, children: pax.children, infants: pax.infants, cabin: pax.class });
        legs.forEach(function (l, i) {
          p.set("seg" + i + "from", l.from); p.set("seg" + i + "fromCity", l.fromCity);
          p.set("seg" + i + "to", l.to); p.set("seg" + i + "toCity", l.toCity);
          p.set("seg" + i + "date", l.date);
        });
        location.href = "flights.html?" + p.toString();
        return;
      }

      const from = resolveAirport(ff.querySelector('input[name="from"]'));
      const to = resolveAirport(ff.querySelector('input[name="to"]'));
      let bad = false;
      if (!from) { setFieldError(ff.querySelector('input[name="from"]'), "Pick a departure city from the list."); bad = true; }
      if (!to) { setFieldError(ff.querySelector('input[name="to"]'), "Pick a destination city from the list."); bad = true; }
      if (from && to && from.iata === to.iata) { setFieldError(ff.querySelector('input[name="to"]'), "Destination must differ from departure."); bad = true; }
      const departVal = getDateFieldValue(ff, "depart");
      if (!departVal) { setFieldError(ff.querySelector(".date-field[data-date-name='depart'] .date-btn"), "Choose a departure date."); bad = true; }
      if (bad) return;
      const p = new URLSearchParams({
        trip: ff.trip.value,
        from: from.iata, fromCity: from.city,
        to: to.iata, toCity: to.city,
        depart: departVal,
        adults: pax.adults, children: pax.children, infants: pax.infants,
        cabin: pax.class
      });
      const returnVal = getDateFieldValue(ff, "return");
      if (ff.trip.value === "round" && returnVal) p.set("return", returnVal);
      location.href = "flights.html?" + p.toString();
    });
  }

  /* Hotels */
  const hf = root.querySelector('form[data-tab-form="hotels"]');
  if (hf) {
    initDatePickers(hf);
    applyDateDefaults(hf);
    hf.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!hf.city.value.trim()) { setFieldError(hf.city, "This field is required."); return; }
      const checkin = getDateFieldValue(hf, "checkin"), checkout = getDateFieldValue(hf, "checkout");
      if (!checkin) { setFieldError(hf.querySelector(".date-field[data-date-name='checkin'] .date-btn"), "Choose a check-in date."); return; }
      if (!checkout) { setFieldError(hf.querySelector(".date-field[data-date-name='checkout'] .date-btn"), "Choose a check-out date."); return; }
      const p = new URLSearchParams({
        city: hf.city.value.trim(), checkin: checkin, checkout: checkout,
        rooms: hf.rooms.value, guests: hf.guests.value
      });
      location.href = "hotels.html?" + p.toString();
    });
  }

  /* Holidays */
  const yf = root.querySelector('form[data-tab-form="holidays"]');
  if (yf) {
    yf.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!validateForm(yf)) return;
      const p = new URLSearchParams({ dest: yf.dest.value, month: yf.month.value, nights: yf.nights.value });
      location.href = "holidays.html?" + p.toString() + "#enquire";
    });
  }

  /* Visa */
  const vf = root.querySelector('form[data-tab-form="visa"]');
  if (vf) {
    initDatePickers(vf);
    vf.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!validateForm(vf)) return;
      const p = new URLSearchParams({ country: vf.country.value, nationality: vf.nationality.value.trim() });
      const travel = getDateFieldValue(vf, "travel");
      if (travel) p.set("travel", travel);
      location.href = "visa.html?" + p.toString() + "#apply";
    });
  }
}

/* ---------- Widget HTML (shared across pages) ---------- */
const WIDGET_TABS = [
  ["flights", "Flights", "plane"],
  ["hotels", "Hotels", "hotel"],
  ["holidays", "Holidays", "suitcase"],
  ["visa", "Visa", "passport"]
];

function flightsPanelHTML() {
  return (
    '<div class="widget-panel" data-tab="flights" role="tabpanel" hidden>' +
    '<form data-tab-form="flights" novalidate>' +
      '<div class="trip-type" role="radiogroup" aria-label="Trip type">' +
        '<label><input type="radio" name="trip" value="round" checked> Round Trip</label>' +
        '<label><input type="radio" name="trip" value="oneway"> One Way</label>' +
        '<label><input type="radio" name="trip" value="multicity"> Multi City</label>' +
      "</div>" +
      '<div class="seg-row">' +
        '<div class="field seg-3"><label for="fl-from">FROM</label>' +
          '<input id="fl-from" name="from" data-airport placeholder="City or airport" required>' +
          '<button type="button" class="swap-btn" aria-label="Swap departure and destination">' + icon("swap") + "</button></div>" +
        '<div class="field seg-3"><label for="fl-to">TO</label>' +
          '<input id="fl-to" name="to" data-airport placeholder="City or airport" required></div>' +
        dateFieldHTML("fl-depart", "depart", "DEPART", { defaultOffset: 3, placeholder: "Add date" }).replace('class="field date-field"', 'class="field date-field seg-2"') +
        dateFieldHTML("fl-return", "return", "RETURN", { defaultOffset: 6, afterField: "depart", placeholder: "Add date" }).replace('class="field date-field"', 'class="field date-field seg-2"') +
        '<div class="field seg-2"><label id="pax-label">TRAVELLERS &amp; CLASS</label>' +
          '<button type="button" class="fake-input pax-btn" aria-haspopup="true" aria-expanded="false" aria-labelledby="pax-label">1 Traveller · Economy</button>' +
          '<div class="pax-pop" hidden>' +
            '<div class="pax-row" data-kind="adults"><span class="pax-label"><b>Adults</b><small>12+ years</small></span>' +
              '<span class="stepper"><button type="button" data-dir="-1" aria-label="Fewer adults">−</button><output>1</output><button type="button" data-dir="1" aria-label="More adults">+</button></span></div>' +
            '<div class="pax-row" data-kind="children"><span class="pax-label"><b>Children</b><small>2–11 years</small></span>' +
              '<span class="stepper"><button type="button" data-dir="-1" aria-label="Fewer children">−</button><output>0</output><button type="button" data-dir="1" aria-label="More children">+</button></span></div>' +
            '<div class="pax-row" data-kind="infants"><span class="pax-label"><b>Infants</b><small>Under 2, on lap</small></span>' +
              '<span class="stepper"><button type="button" data-dir="-1" aria-label="Fewer infants">−</button><output>0</output><button type="button" data-dir="1" aria-label="More infants">+</button></span></div>' +
            '<div class="field"><label for="fl-class">CABIN CLASS</label>' +
              '<select id="fl-class" name="class"><option>Economy</option><option>Premium Economy</option><option>Business</option><option>First</option></select></div>' +
            '<button type="button" class="btn btn-primary done">Done</button>' +
          "</div></div>" +
      "</div>" +
      '<div class="mc-wrap" hidden>' +
        '<div class="mc-segments">' + segmentHTML(0) + segmentHTML(1) + "</div>" +
        '<button type="button" class="mc-add">' + icon("plus") + " Add another flight</button>" +
      "</div>" +
      '<div class="widget-actions">' +
        '<button class="btn btn-primary btn-lg" type="submit">' + icon("plane") + "Search Flights</button></div>" +
    "</form></div>"
  );
}

function hotelsPanelHTML() {
  return (
    '<div class="widget-panel" data-tab="hotels" role="tabpanel" hidden>' +
    '<form data-tab-form="hotels" novalidate>' +
      '<div class="seg-row">' +
        '<div class="field seg-4"><label for="ht-city">DESTINATION / CITY</label>' +
          '<input id="ht-city" name="city" placeholder="e.g. Dubai, Ras Al Khaimah, London" required></div>' +
        dateFieldHTML("ht-in", "checkin", "CHECK-IN", { defaultOffset: 3, placeholder: "Add date" }).replace('class="field date-field"', 'class="field date-field seg-2"') +
        dateFieldHTML("ht-out", "checkout", "CHECK-OUT", { defaultOffset: 5, afterField: "checkin", placeholder: "Add date" }).replace('class="field date-field"', 'class="field date-field seg-2"') +
        '<div class="field seg-2"><label for="ht-rooms">ROOMS</label>' +
          '<select id="ht-rooms" name="rooms"><option>1</option><option>2</option><option>3</option><option>4+</option></select></div>' +
        '<div class="field seg-2"><label for="ht-guests">GUESTS</label>' +
          '<select id="ht-guests" name="guests"><option>1</option><option selected>2</option><option>3</option><option>4</option><option>5</option><option>6+</option></select></div>' +
      "</div>" +
      '<div class="widget-actions">' +
        '<button class="btn btn-primary btn-lg" type="submit">' + icon("hotel") + "Search Hotels</button></div>" +
    "</form></div>"
  );
}

function holidaysPanelHTML() {
  return (
    '<div class="widget-panel" data-tab="holidays" role="tabpanel" hidden>' +
    '<form data-tab-form="holidays" novalidate>' +
      '<div class="seg-row">' +
        '<div class="field seg-5"><label for="hd-dest">DESTINATION</label>' +
          '<select id="hd-dest" name="dest" required>' +
            "<option value=\"\">Choose a destination…</option>" +
            ["Dubai & UAE Staycation", "Umrah Package", "Georgia (Tbilisi)", "Azerbaijan (Baku)", "Thailand", "Bali, Indonesia", "Maldives", "Turkey (Istanbul)", "Europe (Schengen)", "Kerala, India", "Kashmir, India", "Sri Lanka", "Egypt (Cairo)", "Other — tell us!"].map(function (d) { return "<option>" + d + "</option>"; }).join("") +
          "</select></div>" +
        '<div class="field seg-4"><label for="hd-month">TRAVEL MONTH</label>' +
          '<input id="hd-month" name="month" type="month" required></div>' +
        '<div class="field seg-3"><label for="hd-nights">NIGHTS</label>' +
          '<select id="hd-nights" name="nights"><option>2–3</option><option selected>4–6</option><option>7–9</option><option>10+</option></select></div>' +
      "</div>" +
      '<div class="widget-actions">' +
        '<button class="btn btn-primary btn-lg" type="submit">' + icon("suitcase") + "Find Packages</button></div>" +
    "</form></div>"
  );
}

function visaPanelHTML() {
  return (
    '<div class="widget-panel" data-tab="visa" role="tabpanel" hidden>' +
    '<form data-tab-form="visa" novalidate>' +
      '<div class="seg-row">' +
        '<div class="field seg-5"><label for="vs-country">VISA FOR (COUNTRY)</label>' +
          '<select id="vs-country" name="country" required>' +
            "<option value=\"\">Choose a country…</option>" +
            ["United Arab Emirates", "Saudi Arabia (Umrah/Visit)", "Schengen (Europe)", "United Kingdom", "United States", "Canada", "Australia", "Turkey", "Georgia", "Azerbaijan", "Thailand", "Malaysia", "Singapore", "India", "Egypt", "Other"].map(function (c) { return "<option>" + c + "</option>"; }).join("") +
          "</select></div>" +
        '<div class="field seg-4"><label for="vs-nat">YOUR NATIONALITY</label>' +
          '<input id="vs-nat" name="nationality" placeholder="e.g. Indian, Filipino, Pakistani" required></div>' +
        dateFieldHTML("vs-date", "travel", "PLANNED TRAVEL DATE", { defaultOffset: 21, placeholder: "Add date" }).replace('class="field date-field"', 'class="field date-field seg-3"') +
      "</div>" +
      '<div class="widget-actions">' +
        '<button class="btn btn-primary btn-lg" type="submit">' + icon("passport") + "Check Visa Options</button></div>" +
    "</form></div>"
  );
}

const PANEL_BUILDERS = { flights: flightsPanelHTML, hotels: hotelsPanelHTML, holidays: holidaysPanelHTML, visa: visaPanelHTML };

/* only: pass a single tab key ("flights"/"hotels"/"holidays"/"visa") to render
   just that vertical's form with no tab switcher — used on the dedicated pages
   so each page offers only the search relevant to it. Omit for the full
   4-tab portal switcher (home page). */
function searchWidgetHTML(only) {
  if (only && PANEL_BUILDERS[only]) {
    return '<div class="search-widget search-widget-solo" id="search-widget">' + PANEL_BUILDERS[only]() + "</div>";
  }
  return (
    '<div class="search-widget" id="search-widget">' +
    '<div class="widget-tabs" role="tablist" aria-label="What would you like to book?">' +
    WIDGET_TABS.map(function (t) {
      return '<button class="widget-tab" role="tab" data-tab="' + t[0] + '" aria-selected="false">' + icon(t[2]) + t[1] + "</button>";
    }).join("") +
    "</div>" +
    WIDGET_TABS.map(function (t) { return PANEL_BUILDERS[t[0]](); }).join("") +
    "</div>"
  );
}

/* ---------- Enquiry panel builder ---------- */
function enquiryFormHTML(opts) {
  const s = window.KridiyaAuth ? KridiyaAuth.session() : null;
  const u = s && KridiyaAuth.getUser ? (KridiyaAuth.getUser(s.email) || s) : null;
  const hidden = Object.keys(opts.details).map(function (k) {
    return '<input type="hidden" name="' + k + '" value="' + String(opts.details[k]).replace(/"/g, "&quot;") + '">';
  }).join("");
  return (
    '<form class="form-grid" method="POST" action="https://formsubmit.co/' + KRIDIYA.emails.enquiry + '" data-formsubmit data-enquiry-type="' + opts.type + '" novalidate>' +
      '<input type="hidden" name="_subject" value="' + opts.subject.replace(/"/g, "&quot;") + '">' +
      '<input type="hidden" name="_captcha" value="false">' +
      '<input type="hidden" name="_template" value="table">' +
      hidden +
      '<div class="field"><label>YOUR NAME</label><input name="Name" placeholder="Full name" required value="' + (u ? u.name : "") + '"></div>' +
      '<div class="field"><label>EMAIL</label><input name="Email" type="email" placeholder="you@example.com" required value="' + (u ? u.email : "") + '"></div>' +
      '<div class="field"><label>PHONE / WHATSAPP</label><input name="Phone" type="tel" placeholder="+971 …" required value="' + (u && u.phone ? u.phone : "") + '"></div>' +
      '<div class="field"><label>ANYTHING ELSE? (OPTIONAL)</label><textarea name="Notes" placeholder="Preferred airline, budget, flexible dates…"></textarea></div>' +
      '<button class="btn btn-primary btn-block" type="submit">' + icon("mail") + " Send email</button>" +
      '<p class="form-note">Goes straight to our travel experts. We reply within business hours, usually much faster.</p>' +
    "</form>" +
    '<p class="or">— or —</p>' +
    '<a class="btn btn-wa btn-block" target="_blank" rel="noopener" href="' + waLink(opts.waText) + '">' + icon("whatsapp") + " Get a quote on WhatsApp</a>"
  );
}

const SORT_PILLS = [
  ["best", "Best", "Balanced price and duration across airlines"],
  ["cheapest", "Cheapest", "Lowest total fare, including budget and consolidated options"],
  ["fastest", "Fastest", "Shortest total travel time — direct and single-stop options first"]
];

function sortPillsHTML() {
  return '<div class="sort-pills" role="tablist" aria-label="Sort preference">' +
    SORT_PILLS.map(function (s, i) {
      return '<button type="button" class="sort-pill' + (i === 0 ? " active" : "") + '" data-sort="' + s[0] + '">' + s[1] + "</button>";
    }).join("") + "</div>";
}
function initSortPills(mount) {
  const pills = mount.querySelector(".sort-pills");
  const note = mount.querySelector(".sort-note");
  if (!pills || !note) return;
  pills.addEventListener("click", function (e) {
    const btn = e.target.closest(".sort-pill");
    if (!btn) return;
    pills.querySelectorAll(".sort-pill").forEach(function (b) { b.classList.toggle("active", b === btn); });
    const s = SORT_PILLS.find(function (x) { return x[0] === btn.dataset.sort; });
    note.textContent = s[2];
  });
}

function renderResultPanel(mount, opts) {
  mount.innerHTML =
    '<div class="result-panel reveal">' +
      '<div class="result-summary">' +
        '<span class="rs-main">' + icon(opts.icon) + opts.title + "</span>" +
        '<span class="rs-meta">' + opts.meta.map(function (m) { return "<span>" + m + "</span>"; }).join("") + "</span>" +
      "</div>" +
      (opts.sortPills ? '<div class="sort-wrap">' + sortPillsHTML() + '<p class="sort-note form-note">' + SORT_PILLS[0][2] + "</p></div>" : "") +
      '<div class="result-body">' +
        "<div><h3>" + opts.bodyTitle + "</h3><p>" + opts.bodyText + "</p>" + (opts.extra || "") + "</div>" +
        '<div class="enquiry-side"><h3>Get your quote</h3>' +
        '<p class="form-note" style="margin-bottom:0.9rem">No payment now — we confirm the best price with you first.</p>' +
        enquiryFormHTML(opts) + "</div>" +
      "</div>" +
    "</div>";
  mount.querySelectorAll("form[data-formsubmit]").forEach(prepareFormSubmit);
  if (opts.sortPills) initSortPills(mount);
  mount.querySelector(".reveal").classList.add("in");
  mount.scrollIntoView({ behavior: "smooth", block: "start" });
}

const AIRLINE_CHIPS = ["Emirates", "Etihad", "flydubai", "Air Arabia", "Air India Express", "IndiGo", "Qatar Airways", "Saudia", "Turkish Airlines", "Wizz Air"];

function airlinesHTML() {
  return '<div class="airline-row">' +
    AIRLINE_CHIPS.map(function (a) { return '<span class="airline-chip">' + a + "</span>"; }).join("") +
    "</div>";
}

/* ---------- Per-page result wiring ---------- */
function initFlightResults() {
  const mount = document.getElementById("results");
  if (!mount) return;
  const p = new URLSearchParams(location.search);

  if (p.get("trip") === "multicity" && +p.get("legs") > 0) {
    const n = +p.get("legs");
    const legs = [];
    for (let i = 0; i < n; i++) {
      legs.push({
        from: p.get("seg" + i + "from"), fromCity: p.get("seg" + i + "fromCity"),
        to: p.get("seg" + i + "to"), toCity: p.get("seg" + i + "toCity"),
        date: p.get("seg" + i + "date")
      });
    }
    const paxBits = [];
    if (+p.get("adults")) paxBits.push(p.get("adults") + " Adult" + (+p.get("adults") > 1 ? "s" : ""));
    if (+p.get("children")) paxBits.push(p.get("children") + " Child" + (+p.get("children") > 1 ? "ren" : ""));
    if (+p.get("infants")) paxBits.push(p.get("infants") + " Infant" + (+p.get("infants") > 1 ? "s" : ""));
    const routeShort = legs.map(function (l) { return l.from + "→" + l.to; }).join(" · ");
    const routeFull = legs.map(function (l) { return l.fromCity + " (" + l.from + ") → " + l.toCity + " (" + l.to + ") · " + fmtDate(l.date); }).join("<br>");
    const waText = "Hello Kridiya Travel! Multi-city flight enquiry:\n" +
      legs.map(function (l) { return l.fromCity + " (" + l.from + ") -> " + l.toCity + " (" + l.to + ") on " + fmtDate(l.date); }).join("\n") +
      "\n" + paxBits.join(", ") + " · " + p.get("cabin");

    renderResultPanel(mount, {
      icon: "route",
      type: "Multi-city flight enquiry",
      title: routeShort,
      meta: [legs.length + " flights", paxBits.join(", "), p.get("cabin")],
      sortPills: true,
      bodyTitle: "Multi-city fares, quoted as one itinerary",
      bodyText: "Multi-city trips are rarely priced well by booking sites — each leg gets shopped separately and the total balloons. Send us the full route below and we'll quote it as one connected itinerary across 40+ airlines.",
      extra: '<p style="font-size:0.9rem;color:var(--text-muted);margin:0.6rem 0 0">' + routeFull + "</p>" + airlinesHTML(),
      subject: "Multi-City Flight Enquiry: " + routeShort,
      waText: waText,
      details: { Route: legs.map(function (l) { return l.fromCity + " (" + l.from + ") to " + l.toCity + " (" + l.to + ") on " + fmtDate(l.date); }).join(" | "), Travellers: paxBits.join(", "), Cabin: p.get("cabin") }
    });
    return;
  }

  if (!p.get("from") || !p.get("to")) return;
  // Destination shortcut links carry no dates — assume next week
  if (!p.get("depart")) {
    p.set("depart", todayISO(7));
    if (p.get("trip") === "round") p.set("return", todayISO(14));
  }
  const round = p.get("trip") === "round" && p.get("return");
  const paxBits = [];
  if (+p.get("adults")) paxBits.push(p.get("adults") + " Adult" + (+p.get("adults") > 1 ? "s" : ""));
  if (+p.get("children")) paxBits.push(p.get("children") + " Child" + (+p.get("children") > 1 ? "ren" : ""));
  if (+p.get("infants")) paxBits.push(p.get("infants") + " Infant" + (+p.get("infants") > 1 ? "s" : ""));
  const route = p.get("fromCity") + " (" + p.get("from") + ") " + (round ? "⇄" : "→") + " " + p.get("toCity") + " (" + p.get("to") + ")";
  const dates = fmtDate(p.get("depart")) + (round ? " — " + fmtDate(p.get("return")) : "");
  const waText = "Hello Kridiya Travel! Flight enquiry:\n" + route + "\n" + dates + "\n" + paxBits.join(", ") + " · " + p.get("cabin");

  renderResultPanel(mount, {
    icon: "plane",
    type: "Flight enquiry",
    title: route,
    meta: [dates, paxBits.join(", "), p.get("cabin")],
    sortPills: true,
    bodyTitle: "We're on it — fares compared across 40+ airlines",
    bodyText: "Kridiya Travel checks published and consolidated fares that don't always appear on booking sites. Send this search and a travel expert will reply with the lowest live fare, baggage details and payment options.",
    extra: airlinesHTML(),
    subject: "Flight Enquiry: " + route + " · " + dates,
    waText: waText,
    details: {
      Route: route, Trip: round ? "Round trip" : "One way", Dates: dates,
      Travellers: paxBits.join(", "), Cabin: p.get("cabin")
    }
  });
}

function initHotelResults() {
  const mount = document.getElementById("results");
  if (!mount) return;
  const p = new URLSearchParams(location.search);
  if (!p.get("city")) return;
  const stay = fmtDate(p.get("checkin")) + " — " + fmtDate(p.get("checkout"));
  const who = p.get("rooms") + " room(s), " + p.get("guests") + " guest(s)";
  renderResultPanel(mount, {
    icon: "hotel",
    type: "Hotel enquiry",
    title: "Hotels in " + p.get("city"),
    meta: [stay, who],
    bodyTitle: "Handpicked stays at trade rates",
    bodyText: "From city hotels to beach resorts, we hold trade rates with major chains and local gems in " + p.get("city") + ". Tell us your budget and star preference and we'll send a shortlist with photos and total prices — no hidden fees.",
    subject: "Hotel Enquiry: " + p.get("city") + " · " + stay,
    waText: "Hello Kridiya Travel! Hotel enquiry:\n" + p.get("city") + "\n" + stay + "\n" + who,
    details: { City: p.get("city"), Stay: stay, Rooms_Guests: who }
  });
}

/* ---------- Boot ---------- */
document.addEventListener("DOMContentLoaded", function () {
  const wrap = document.getElementById("widget-mount");
  if (wrap) {
    const only = document.body.dataset.widgetOnly || null;
    wrap.innerHTML = searchWidgetHTML(only);
    initSearchWidget(wrap.firstElementChild, document.body.dataset.widgetTab);

    // Reflect an incoming search (URL params) back into the widget
    const p = new URLSearchParams(location.search);
    const ff = wrap.querySelector('form[data-tab-form="flights"]');
    if (ff && p.get("trip") === "multicity" && +p.get("legs") > 0) {
      ff.querySelector('input[name="trip"][value="multicity"]').checked = true;
      ff.querySelector('input[name="trip"]').dispatchEvent(new Event("change"));
      const mc = ff.querySelector(".mc-segments");
      const n = Math.min(+p.get("legs"), MAX_SEGMENTS);
      while (mc.children.length < n) ff.querySelector(".mc-add").click();
      for (let i = 0; i < n; i++) {
        const seg = mc.children[i];
        const fromInput = seg.querySelector("[data-seg-from]"), toInput = seg.querySelector("[data-seg-to]");
        const fCity = p.get("seg" + i + "fromCity"), fIata = p.get("seg" + i + "from");
        const tCity = p.get("seg" + i + "toCity"), tIata = p.get("seg" + i + "to");
        if (fIata) { fromInput.value = fCity + " (" + fIata + ")"; fromInput.dataset.iata = fIata; fromInput.dataset.city = fCity; }
        if (tIata) { toInput.value = tCity + " (" + tIata + ")"; toInput.dataset.iata = tIata; toInput.dataset.city = tCity; }
        const d = p.get("seg" + i + "date");
        if (d) setDateFieldValue(ff, "seg-date-" + i, d);
      }
    } else if (ff && p.get("from") && p.get("to")) {
      const from = ff.querySelector('input[name="from"]'), to = ff.querySelector('input[name="to"]');
      from.value = p.get("fromCity") + " (" + p.get("from") + ")";
      from.dataset.iata = p.get("from"); from.dataset.city = p.get("fromCity");
      to.value = p.get("toCity") + " (" + p.get("to") + ")";
      to.dataset.iata = p.get("to"); to.dataset.city = p.get("toCity");
      if (p.get("depart")) setDateFieldValue(ff, "depart", p.get("depart"));
      const trip = p.get("trip") === "oneway" ? "oneway" : "round";
      ff.querySelector('input[name="trip"][value="' + trip + '"]').checked = true;
      ff.querySelector('input[name="trip"]').dispatchEvent(new Event("change"));
      if (p.get("return")) setDateFieldValue(ff, "return", p.get("return"));
    }
    const hf = wrap.querySelector('form[data-tab-form="hotels"]');
    if (hf && p.get("city")) {
      hf.city.value = p.get("city");
      if (p.get("checkin")) setDateFieldValue(hf, "checkin", p.get("checkin"));
      if (p.get("checkout")) setDateFieldValue(hf, "checkout", p.get("checkout"));
      if (p.get("rooms")) hf.rooms.value = p.get("rooms");
      if (p.get("guests")) hf.guests.value = p.get("guests");
    }
  }
  initFlightResults();
  initHotelResults();
});

