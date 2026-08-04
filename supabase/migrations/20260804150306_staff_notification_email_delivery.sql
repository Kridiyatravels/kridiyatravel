begin;

create table if not exists public.staff_notification_email_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique references public.staff_notifications(id) on delete cascade,
  status text not null default 'processing' check (status in ('processing', 'sent', 'failed')),
  recipient_count integer not null default 0 check (recipient_count >= 0),
  provider_message_ids jsonb not null default '[]'::jsonb,
  last_error text,
  attempted_at timestamptz not null default now(),
  sent_at timestamptz
);

alter table public.staff_notification_email_deliveries enable row level security;
revoke all on public.staff_notification_email_deliveries from public, anon, authenticated;
grant all on public.staff_notification_email_deliveries to service_role;

comment on table public.staff_notification_email_deliveries is
  'Server-only idempotency and audit ledger for operational emails sent through Resend.';

commit;
