# Kridiya Marketing and Growth System — Implementation Gap Audit

Audit date: 2026-07-29
Compared against: `KRIDIYA_DIGITAL_MARKETING_AND_GROWTH_SYSTEM_PLAN.md`
Audit basis: local public-site repository, local Supabase SQL/migrations, local corporate-site repository, local admin repository at `C:\Users\Who\kridiya-admin`, and existing handoff/operations documents.

## 1. Important scope note

The supplied attachment is byte-for-byte identical to the workspace file:

`docs/KRIDIYA_DIGITAL_MARKETING_AND_GROWTH_SYSTEM_PLAN.md`

The master plan and the marketing-system kit are currently untracked in the main Git repository. They exist locally, but are not part of the current committed/deployed public-site history.

This audit distinguishes four statuses:

- **Implemented:** supported by repository code or a usable operating artifact.
- **Partial:** a foundation exists, but important requirements are missing.
- **Planned only:** described in documents/templates, with no operating implementation found.
- **Unverified external:** depends on a live account, deployment, staff process, or third-party platform that was not verifiable from repository evidence.

No live GA4, Search Console, Google Business Profile, Google Ads, Meta Ads, WhatsApp Business, Supabase production data, or campaign results were available for verification. The public and corporate sites also could not be independently confirmed as matching the local working trees.

## 2. What Kridiya already has

### Public/customer system

- 20 top-level HTML pages.
- Major service pages for flights, hotels, holidays, visas, Umrah, cruises, contact, customer account, and corporate requests.
- Responsive public design with one-tap WhatsApp, phone, and email access.
- Canonical tags and meta descriptions on the principal public pages.
- A homepage `TravelAgency` structured-data block.
- `robots.txt` and `sitemap.xml`.
- Service-specific enquiry forms for holidays, visas, Umrah, cruises, corporate requests, and contact.
- Dynamic flight/hotel search-to-enquiry forms.
- Supabase enquiry capture plus FormSubmit email delivery.
- Website-generated enquiry references and a useful thank-you page.
- Customer registration, login, account, enquiry/quote, booking, document, and payment-status surfaces.
- Privacy policy and terms pages.
- 84 image/SVG assets, including contextual service illustrations and campaign artwork.

### CRM, operations, and finance foundation

- `enquiries`, enquiry notes, requests, quotes, bookings, customers, staff, corporate accounts, payments, receipts, documents, activity, and task/reminder structures.
- Eight current enquiry statuses.
- Quote builder with validity, terms, service-specific details, and multiple options.
- Booking-level follow-up tasks and assignment.
- Supplier cost, selling price, refund, gross-profit, and accounting/export capabilities.
- Staff roles and permission controls.
- Private document-storage direction and signed-access patterns.
- Audit/activity logging.
- Corporate enquiry conversion into company, contact, and booking records.

### Admin/staff system

- 17 HTML pages and 20 JavaScript modules in the separate admin repository.
- Enquiry queue, filters, notes, quote creation, follow-up views, booking conversion, customer records, corporate accounts, documents, payments, accounting, backups, staff, and activity controls.
- A useful operational dashboard and gross-profit reporting foundation.

### Corporate system

- Public corporate request/account forms.
- Corporate company and contact data model.
- Booking and approval/LPO-related fields.
- A separate corporate site with 9 HTML pages and a private portal direction.
- Corporate portal access and quote-control migrations in local repository code.

### Marketing operating artifacts

- Full master strategy.
- Marketing-system README and capability matrix.
- Starter always-on campaign and ad kit.
- 36-row draft 90-day content calendar.
- Six-item experiment backlog.
- Empty/example campaign scorecard ready for live data.
- Two generated always-on/brand ad creative sets.
- Email and WhatsApp template document.

## 3. Executive conclusion

Kridiya has built the **website, enquiry, quote, booking, corporate, finance, and staff-operation foundation** needed to support marketing.

Kridiya has **not yet built the complete marketing measurement and growth system** described in the master plan. The largest missing layer is the connection:

`campaign -> tracked visit/message -> attributed enquiry -> qualified lead -> quote -> booking -> gross profit -> repeat/referral`

At present:

- the campaign strategy is documented;
- customer enquiries can be captured;
- bookings and gross profit can be recorded;
- but acquisition identity, source/campaign persistence, SLA timestamps, lead qualification, lost reasons, consent/opt-out controls, and campaign-to-profit reporting are not joined into one reliable system.

Paid media should therefore remain behind the plan's own launch gate.

## 4. Item-by-item comparison against all 19 plan sections

| Plan section | Status | What exists | What is missing or conflicting |
|---|---|---|---|
| 1. Executive decision | **Partial** | Human-advisor positioning, WhatsApp access, service breadth, UAE identity, enquiry-first model | Public copy still uses “cheap,” “lowest price,” “best-price,” and broad “24/7” language that conflicts with the approved trust/clarity position |
| 2. Outcomes and targets | **Planned only** | North-star and 90-day targets are documented; finance system can calculate booking gross profit | No baseline, SLA timestamps, attributed booking report, live campaign results, or owner scorecard populated |
| 3. Brand/message architecture | **Partial** | Legal name, RAK identity, slogan, support, trust sections, terms, privacy, quote workflow | Claims are inconsistent; no centrally enforced claim/voice approval process; testimonial substantiation is not recorded |
| 4. Priority audiences | **Partial** | Service pages cover residents, families, visa, Umrah, cruise, and corporate needs | Audience tags/segments are not standardized in CRM; destination/nationality-specific landing clusters are mostly absent |
| 5. Offer system | **Partial** | Service-specific forms, quote builder, multiple quote options, validity and terms | Value/Comfort/Premium is not a standardized quote/offer system across services; no campaign-specific offer record, margin approval, or follow-up sequence |
| 6. Funnel and CRM | **Partial** | Enquiries, notes, requests, quotes, bookings, tasks, customer/corporate data, finance | Required attribution fields, detailed stages, enquiry owner, next action/date, SLA timestamps, lost reason, consent source, review/referral fields, and lead score are missing |
| 7.1 Website/landing pages | **Partial** | Major service pages, mobile WhatsApp, forms, trust content, thank-you page, SEO basics | Campaign attribution absent; destination clusters absent; structured data only on homepage; FAQs inconsistent; response promise conflicts; no verified performance/accessibility measurement |
| 7.2 Local SEO/reputation | **Unverified external** | Local RAK identity and consistent core contact details in local code | GBP verification/completeness, real photos, review workflow, replies, direction/call tracking, and local partnership activity are not evidenced |
| 7.3 Search marketing | **Planned only** | Starter RSA copy, negatives, launch checklist, budget framework | No verified Google Ads campaigns, click-ID capture, search-term reviews, conversion imports, or qualified-lead/booking optimization |
| 7.4 Meta/Instagram/Facebook | **Partial/planned** | Social links, creative concepts, two ad assets, content calendar, click-to-WhatsApp direction | No verified live campaigns, pixels/CAPI, retargeting audiences, exclusions, CRM outcome return, or creative performance data |
| 7.5 Email/WhatsApp | **Partial** | Form emails, WhatsApp CTAs/prefills, manual operational templates, newsletter form | No lifecycle automation, CRM segments, lawful marketing list workflow, unsubscribe/stop control, preference center, or 60/90/180-day reminders |
| 7.6 Corporate acquisition | **Partial** | Strong corporate request, account, portal, company/contact, booking, LPO, and billing foundation | No named-account prospect list, 20-account weekly process, outbound sequence, corporate one-pager/case study, or pipeline reporting |
| 7.7 Partnerships/referrals | **Planned only** | Strategy and potential partner list documented | No partner records, codes, agreements, payout controls, referral cost, fraud review, or monthly partner-profit report |
| 8. Content operating system | **Partial/planned** | Six pillars, creative brief, 36 draft calendar rows, ad assets | Calendar is draft-only and below the plan's stated monthly production volume; no approval workflow, published-asset log, performance data, proof library, or repurposing tracker |
| 9. Campaign timeline | **Planned only** | Seasonal lead-time framework and campaign stages | No dated annual calendar tied to verified 2026/2027 travel moments, supplier validation, margins, owners, budgets, or launch status |
| 10. Paid-media budget | **Planned only** | AED 6,000–10,000 framework, allocation, scale rules, formulas | No approved budget, stop-loss, channel spend, qualified CPL, CAC, contribution, or scaling decision data |
| 11. Measurement/attribution | **Missing critical layer** | Supabase operations and gross-profit calculation; empty scorecard; admin can display a source if one happens to exist | No GA4 tag/events found, no campaign persistence, no click IDs, no first/last touch, no joined dashboard, no offline conversion import, no campaign-to-profit report |
| 12. Retention/reviews/referrals | **Planned only** | Customer history, booking completion status, templates, strategy | No automated lifecycle, review request timestamp/workflow, direct review link, future-interest tag, next-travel window, referral code, benefit, or cost tracking |
| 13. Roles/governance | **Partial/planned** | Staff roles, permissions, operational responsibilities, approval guidance | No named human owner for each marketing role, campaign approval record, RACI in use, claims register, or documented monthly marketing meeting output |
| 14. Privacy/security/quality | **Partial** | Privacy/terms, RLS direction, consents table, newsletter flag, private-document controls, no raw-card design | Newsletter/enquiry forms do not implement an explicit separate promotional opt-in; no unsubscribe workflow; campaign claims log absent; production RLS/legal review not fully verified |
| 15. 90-day plan | **Partially started** | Strategy, assets, forms, CRM/admin, content calendar, scorecard template, corporate foundation | Days 1–30 attribution/consent/SLA gates are incomplete; therefore days 31–90 paid launch, optimization, and retention should not be considered started |
| 16. Months 4–12 | **Future** | Roadmap documented | SEO expansion, lifecycle automation, partnerships, multilingual tests, API messaging, LTV reporting, annual channel review, and archive process are not implemented |
| 17. What not to do | **Policy documented; compliance partial** | Good written guardrails | Current copy violates the “no lowest-price/unverified availability language” rule in several places; campaign/account ownership and list/review practices are externally unverified |
| 18. Owner scorecard | **Not operational** | Empty scorecard structure and finance data foundation | The owner cannot yet reliably answer campaign, source-profit, SLA, quote-follow-up, lost-reason, repeat/referral, or claims-expiry questions from one report |
| 19. Reference implementation | **Documented only** | Google/Meta reference links and intended architecture | The recommended UTM, offline-conversion, and click-to-message implementations are not connected end to end |

## 5. Detailed CRM and attribution gap

### Current enquiry record

The current `enquiries` table has:

- reference;
- user;
- service type;
- one of eight statuses;
- name, email, phone;
- summary and generic `details` JSON;
- created and updated timestamps.

This is enough for basic enquiry handling, but not enough for the master plan.

### Required fields not standardized on the enquiry/lead path

The following master-plan fields were not found as standardized enquiry columns or equivalent reliable records:

- `first_touch_source`
- `first_touch_medium`
- `first_touch_campaign`
- `last_touch_source`
- `last_touch_medium`
- `last_touch_campaign`
- `utm_id`
- `utm_source`
- `utm_medium`
- `utm_campaign`
- `utm_content`
- `utm_term`
- `gclid`
- platform click IDs
- `landing_page`
- `referrer`
- `lead_created_at` as a named business timestamp
- `first_response_at`
- `qualified_at`
- `quote_sent_at`
- `booking_confirmed_at` on the originating lead
- `assigned_staff_id` on the enquiry
- `service_interest` as a marketing tag separate from the current service type
- `destination_interest`
- `travel_window`
- `lead_temperature`
- `estimated_booking_value`
- `estimated_gross_profit`
- `lost_reason`
- `marketing_consent`
- `marketing_consent_at` on the lead
- `marketing_consent_source`
- `unsubscribe_at`
- `review_requested_at`
- `referral_source_customer_id`

The admin code contains a reader for `details.utm_source`, but no public-site writer for UTM values was found. That means the UI is ready to display a source that the current enquiry path does not reliably capture.

### Current versus required funnel stages

| Required stage | Current equivalent | Gap |
|---|---|---|
| New enquiry | `received` | Present |
| Acknowledged | None | Missing timestamp/status |
| Qualified | None | Missing |
| Supplier checking | `checking_availability` | Present |
| Quote sent | `quote_sent` | Present |
| Follow-up due | Admin inference / booking tasks | Not a durable enquiry stage/date |
| Customer approved | `confirmed` | Ambiguous but usable |
| Payment requested | `payment_pending` | Present |
| Payment received | Booking/payment records | Not joined as a lead stage |
| Booking confirmed | `booked` | Present |
| Travel completed | Booking `completed` | Not an enquiry stage |
| Review requested | None | Missing |
| Repeat/referral eligible | None | Missing |
| Lost/closed | `closed` | Lost reason missing |

### Lead qualification

The proposed 100-point qualification model is not implemented. There is no score, score explanation, or staff override record.

## 6. Measurement-event check

| Required event | Repository status |
|---|---|
| `view_service` | Not implemented as an analytics event |
| `start_enquiry` | Not implemented |
| `submit_enquiry` | Enquiry submission exists operationally, but no analytics event |
| `click_whatsapp` | Link exists; no event tracking |
| `click_call` | Link exists; no event tracking |
| `click_email` | Link exists; no event tracking |
| `register_account` | Registration exists operationally; no analytics event |
| `login_account` | Login exists operationally; no analytics event |
| `quote_sent` | CRM action exists; no marketing event/export connection |
| `qualified_lead` | No qualification state/event |
| `payment_received` | Finance state exists; no marketing attribution event |
| `booking_confirmed` | Booking state exists; no marketing attribution event |
| `refund_completed` | Refund state exists; no marketing attribution event |

No GA4/Google Tag Manager/Meta Pixel code was found in the public-site implementation.

## 7. Website conversion checklist

| Requirement | Status |
|---|---|
| Major service pages | Implemented |
| Destination/theme landing clusters | Mostly missing |
| Sticky mobile WhatsApp | Implemented |
| Sticky mobile call CTA | Partial; phone is available but not paired as a consistent sticky action |
| Short service-specific forms | Implemented for several services; flights/hotels use dynamic forms |
| Trust near first CTA | Partial and page-dependent |
| Visible response expectation | Implemented, but inconsistent with the 5/15-minute target and 24/7 wording |
| Real-objection FAQs | Present on flights, hotels, and about; inconsistent elsewhere |
| Honest price/availability language | Partial; several lowest/best/cheap claims conflict with the plan |
| Useful thank-you path | Implemented |
| First-party campaign attribution | Missing |
| Structured data | Homepage only |
| Mobile/accessibility quality | Prior local QA passed selected pages; not a full audited score |

## 8. Brand and claims conflicts requiring correction

The master plan says not to claim lowest price, guaranteed visas, or live availability without evidence. Current local code includes:

- “Cheap Flight Tickets” in the flight page title.
- “best-price quote” in flight metadata.
- “send you the lowest price” on the flight page.
- “lowest live fare” in search-result copy.
- “best live fare” on the homepage.
- “Cheap flights” in homepage metadata.
- a customer quote claiming AED 700 cheaper than every website.
- broad “24/7 support” language alongside more limited business-hour response promises.

These should be changed to evidence-safe language such as “we compare suitable available options and confirm the fare, baggage, and conditions before payment.” If the testimonial is genuine, permission and substantiation should be stored.

## 9. Privacy and consent gaps

### Implemented

- Privacy and terms pages.
- Profile-level `newsletter_opt_in` and `marketing_consent_at`.
- A generic consents table for authenticated users.
- RLS and private-storage direction.
- No design for storing raw card data.

### Missing

- Explicit, optional, unbundled marketing consent on the newsletter and enquiry paths.
- Consent source/version for guest leads.
- A clear unsubscribe/stop workflow.
- `unsubscribe_at` or suppression-list enforcement.
- Separate operational-versus-promotional communication controls.
- Audience-export authorization workflow.
- Campaign claims register with source, approver, validity, and expiry.
- Recorded legal review of the exact UAE implementation.

The footer newsletter currently submits an email address through FormSubmit, but does not create a consent record or show a separate marketing opt-in control.

## 10. Content and campaign readiness

### Ready as planning material

- One complete always-on campaign concept.
- Meta copy and story direction.
- Google RSA starter copy and negatives.
- Three creative hypotheses.
- One A/B test.
- Six experiment ideas.
- Two ad creative outputs.
- 36 draft content-calendar rows.

### Not ready as an operating campaign system

- No evidence of approved or published content.
- No content asset IDs, approval dates, claim expiry, or source proof.
- No verified four-week prepared content batch.
- No live campaign IDs tied to platform campaigns.
- No populated campaign scorecard.
- No real spend, impressions, clicks, conversations, leads, quotes, bookings, or profit.
- No dated seasonal calendar using verified dates and supplier inventory.
- No campaign archive or retrospective.

The 36-row 90-day calendar averages three items per week. The plan's minimum monthly production target is materially higher and also calls for daily useful stories, SEO articles, a corporate article/case study, proof posts, and eight short videos per month.

## 11. Repository and deployment risks

- The main public worktree has many modified and untracked files.
- The marketing plan and entire `docs/marketing-system/` folder are untracked.
- Two main-public commits are recorded as local-only in system memory.
- The separate corporate repository has modified CSS/HTML and an untracked preview server.
- Corporate portal migrations and cross-company isolation testing are not fully verified live.
- The admin repository is clean for application code but contains untracked local support files.
- There is no single verified statement that the public website, corporate website, admin, and live Supabase schema all match the local repository state.

These conditions do not invalidate the work, but they mean “exists locally” must not be reported as “live and operational.”

## 12. Priority action plan

### P0 — complete before paid media

1. Add the full attribution/consent/SLA field set to the enquiry data model.
2. Capture first-touch and last-touch UTMs, click IDs, landing page, and referrer before form submission.
3. Add enquiry owner, next action/date, qualification state, lost reason, and the required lifecycle timestamps.
4. Add GA4 with the required website events and a consent-aware implementation.
5. Connect quote, qualified lead, payment, booking, refund, supplier cost, and gross profit back to campaign ID.
6. Build one daily/weekly/monthly marketing dashboard from CRM and finance truth.
7. Implement explicit promotional opt-in, unsubscribe/suppression, and consent source/version.
8. Correct cheap/lowest/best/24-7 claims so the website matches the approved brand rules.
9. Verify live Supabase migrations, RLS, portal isolation, and actual deployment versions.
10. Run a complete test: tagged click -> enquiry -> assigned lead -> quote -> payment -> booking -> gross profit report.

### P1 — launch foundation

1. Name the real owners for marketing, sales follow-up, operations approval, finance, and technical reporting.
2. Standardize the 14-stage pipeline and response/follow-up SLA.
3. Complete high-intent landing pages and add destination clusters from verified demand.
4. Add accurate service/FAQ/breadcrumb structured data where applicable.
5. Verify and complete Google Business Profile; implement the review request/reply routine.
6. Produce and approve four weeks of content at the actual sustainable cadence.
7. Create the first flight, holiday, visa, Umrah, and corporate campaign records with owners, margins, UTMs, budgets, and stop rules.
8. Build the corporate named-account list and weekly outreach workflow.
9. Create the customer review and controlled referral workflows.

### P2 — controlled growth

1. Launch high-intent Google Search only after P0 passes.
2. Launch two or three Meta click-to-WhatsApp tests.
3. Import qualified lead and confirmed booking outcomes to ad platforms where lawful.
4. Add lifecycle segments and manual sequences, then automate only proven workflows.
5. Add repeat-customer, dormant-customer, seasonal, review, and referral reporting.
6. Formalize partner agreements, tracking codes, benefit/payout rules, and profit reviews.
7. Expand SEO, destination pages, multilingual content, and WhatsApp Business API only after operating economics and consent controls are proven.

## 13. Final readiness verdict

### Ready now

- Organic website enquiries.
- Manual WhatsApp/call/email conversion.
- Staff enquiry, quote, booking, document, payment, and finance handling.
- Manual corporate enquiry intake and account/booking operations.
- Campaign planning and content preparation.

### Not ready now

- Paid-media scaling.
- Reliable campaign attribution.
- Campaign-to-gross-profit optimization.
- Automated email/WhatsApp marketing.
- Remarketing audience activation.
- Referral payouts.
- Management claims that the 90-day growth system is operational.

### Correct overall description

**Kridiya currently has a strong operational and website foundation plus a comprehensive proposed marketing system. The marketing system itself is not yet fully implemented. Its first required implementation phase is attribution, CRM discipline, consent, measurement, and claims alignment—not additional ad spend.**
