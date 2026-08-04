begin;

create table if not exists public.staff_digest_email_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  digest_type text not null check (digest_type in ('daily', 'overdue')),
  digest_date date not null,
  status text not null default 'processing' check (status in ('processing', 'sent', 'failed', 'skipped')),
  task_count integer not null default 0 check (task_count >= 0),
  provider_message_id text,
  last_error text,
  attempted_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, digest_type, digest_date)
);

create index if not exists staff_digest_email_deliveries_recent_idx
  on public.staff_digest_email_deliveries(digest_date desc, digest_type, status);

alter table public.staff_digest_email_deliveries enable row level security;
revoke all on public.staff_digest_email_deliveries from public, anon, authenticated;

comment on table public.staff_digest_email_deliveries is
  'Service-only idempotency and delivery history for staff operations digests.';

commit;
