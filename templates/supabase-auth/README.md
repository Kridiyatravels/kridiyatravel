# Supabase auth emails — copy-paste pack

These are ready to paste into **Authentication → Emails** in the Supabase
dashboard. They are numbered in the exact order that screen lists them, so
you can work straight down the page.

## How to paste one

1. Open the template in the Supabase dashboard.
2. Switch the editor from **Preview** to **Source** / `</>` — pasting into
   the preview tab will not save the HTML.
3. Select everything already there and delete it.
4. Open the matching file below, copy the whole file, paste it in.
5. Save.

Do one, then send yourself a test of that one before doing the rest. If the
first works, the other twelve will.

## The files

| # | Supabase section | Template on that screen | File | Variables it uses |
|---|---|---|---|---|
| 01 | Authentication | Confirm sign up | `01-confirm-sign-up.html` | `{{ .ConfirmationURL }}` |
| 02 | Authentication | Invite user | `02-invite-user.html` | `{{ .ConfirmationURL }}` |
| 03 | Authentication | Magic link or OTP | `03-magic-link-or-otp.html` | `{{ .ConfirmationURL }}` `{{ .Token }}` |
| 04 | Authentication | Change email address | `04-change-email-address.html` | `{{ .NewEmail }}` `{{ .ConfirmationURL }}` |
| 05 | Authentication | Reset password | `05-reset-password.html` | `{{ .ConfirmationURL }}` |
| 06 | Authentication | Reauthentication | `06-reauthentication.html` | `{{ .Token }}` |
| 07 | Security | Password changed | `07-password-changed.html` | _none_ |
| 08 | Security | Email address changed | `08-email-address-changed.html` | _none_ |
| 09 | Security | Phone number changed | `09-phone-number-changed.html` | _none_ |
| 10 | Security | Sign-in method linked | `10-sign-in-method-linked.html` | _none_ |
| 11 | Security | Sign-in method removed | `11-sign-in-method-removed.html` | _none_ |
| 12 | Security | MFA method added | `12-mfa-method-added.html` | _none_ |
| 13 | Security | MFA method removed | `13-mfa-method-removed.html` | _none_ |

## Two things to know

**The MFA toggles are off.** In your dashboard, *MFA method added* and
*MFA method removed* are switched off, so 12 and 13 will not send until you
turn them on. Paste them anyway — they are then ready if you enable MFA.

**The Security templates use no variables.** That is correct: Supabase sends
those as fixed notifications. Only the six Authentication templates carry
`{{ .ConfirmationURL }}` or `{{ .Token }}`, and those must be left exactly as
written or the links in the email will not work.

## Not part of this pack

- `docs/email-template-preview-index.html` — no matching slot on the Supabase screen.
- `docs/email-template-preview-security-alert.html` — no matching slot on the Supabase screen.
- `docs/email-template-preview-security-notifications.html` — no matching slot on the Supabase screen.
