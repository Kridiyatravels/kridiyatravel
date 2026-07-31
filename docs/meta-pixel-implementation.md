# Kridiya Travel Meta Measurement

Last updated: 2026-07-31

## Platform details

- Business portfolio: Kridiya travel
- Business portfolio ID: `1164199873450609`
- Dataset name: Kridiya Travel Website
- Dataset/Pixel ID: `1584188866628210`
- Advertising account context: `1340811631454357`

## Website implementation

The public website loads the Meta Pixel only after the visitor explicitly
chooses **Allow both** in the website measurement banner. The default state is
denied. Choosing **No thanks** or **Analytics only** prevents the Meta script
from loading.

The privacy notice provides a control that clears the stored choice and presents
the banner again. Google advertising storage, advertising user data, and
advertising personalisation remain denied even when Meta measurement is allowed.

No names, email addresses, phone numbers, passport details, payment details, or
enquiry references are sent to Meta.

## Event mapping

| Website action | Meta event |
| --- | --- |
| Page load after consent | `PageView` |
| Service page viewed | `ViewContent` |
| Enquiry submitted | `Lead` |
| Newsletter signup | `Subscribe` |
| Customer registration | `CompleteRegistration` |
| WhatsApp, phone, or email click | `Contact` |
| Enquiry started or customer login | Custom event |

## Production verification

After deployment:

1. Open the production website in a fresh browser session.
2. Confirm no request to `connect.facebook.net` occurs before consent.
3. Choose **Allow both** and confirm `fbevents.js` loads.
4. In Meta Events Manager, open **Test events** for the Kridiya Travel Website
   dataset.
5. Visit a service page and submit a labelled test enquiry.
6. Confirm `PageView`, `ViewContent`, and `Lead` appear without personal data.

## Conversions API

The `meta-conversions` Supabase Edge Function sends a server-side `Lead` event
only after a website visitor has selected **Allow both** and a real enquiry has
been delivered. The browser and server events share the same `event_id` so Meta
can deduplicate them.

The function accepts only Kridiya website origins and a valid Supabase
publishable key. It allowlists the event type and fields, validates the source
URL, and never accepts or sends customer names, email addresses, phone numbers,
passport details, payment details, enquiry references, or enquiry content.

Required production secret:

- `META_CAPI_ACCESS_TOKEN` - generated in Meta Events Manager and stored only in
  Supabase Edge Function secrets.

Optional temporary testing secret:

- `META_TEST_EVENT_CODE` - copied from Events Manager Test Events and removed
  after production validation.
