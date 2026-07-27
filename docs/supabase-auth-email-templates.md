# Kridiya Supabase Auth Email Templates

Use these samples in Supabase Dashboard > Authentication > Emails > Templates.

Sender name: `Kridiya Travel`
Sender email: `noreply@kridiyatravel.com`

## Brand System Used

These email previews are based on the live site treatment in `css/styles.css`: cream controls, amber text accents, soft shadows, and bold Plus Jakarta-style headings.

```css
--brand-deep: #b6530f;
--brand-soft: #fff4e6;
--gold: #f6c445;
--blue-deep: #ffe0a6;
--ink: #2f2415;
--heading-ink: #1e1509;
--ink-3: #5a4629;
--text: #574b3b;
--text-muted: #79694f;
--bg: #fdf8f0;
--surface: #ffffff;
--line: #f1e8d8;
--line-strong: #e3d5be;
--on-dark: #fff8ec;
```

The HTML is inline and table-based so it can be pasted into Supabase Auth email bodies with minimal email-client risk.

## Supabase Variables

Keep Supabase variables exactly as written. The templates use:

`{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .NewEmail }}`, `{{ .OldEmail }}`, `{{ .Email }}`, `{{ .Provider }}`, `{{ .FactorType }}`, `{{ .Phone }}`.

Supabase currently supports hosted editing in the dashboard and local/self-hosted template files. For local development, configure `content_path` entries in `supabase/config.toml`.

## Preview

Open this file in a browser:

```text
docs/email-template-preview-index.html
```

## Template Files

### Confirm Sign Up

Subject:

```text
Confirm your Kridiya Travel account
```

Body source:

```text
docs/email-template-preview-confirm-signup.html
```

### Invite User

Subject:

```text
You are invited to Kridiya Travel
```

Body source:

```text
docs/email-template-preview-invite-user.html
```

### Magic Link / OTP

Subject:

```text
Your Kridiya Travel sign-in link
```

Body source:

```text
docs/email-template-preview-magic-link.html
```

### Reset Password

Subject:

```text
Reset your Kridiya Travel password
```

Body source:

```text
docs/email-template-preview-reset-password.html
```

### Change Email Address

Subject:

```text
Confirm your new Kridiya Travel email
```

Body source:

```text
docs/email-template-preview-change-email.html
```

### Reauthentication

Subject:

```text
{{ .Token }} is your Kridiya Travel verification code
```

Body source:

```text
docs/email-template-preview-reauthentication.html
```

### Security Alert

Subject:

```text
Your Kridiya Travel account was updated
```

Body source:

```text
docs/email-template-preview-security-alert.html
```

## Copy Note

For hosted Supabase, paste the email body HTML into the template body field. If the dashboard strips `<!doctype html>`, `html`, `head`, or `body`, paste the inner content starting from the first outer `<div>`.
