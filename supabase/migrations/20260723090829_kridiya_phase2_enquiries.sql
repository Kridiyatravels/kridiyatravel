-- Kridiya Travel - enquiry tracking (phase 2)
begin;

do $$
begin
  create type public.enquiry_status as enum (
    'received',
    'checking_availability',
    'quote_sent',
    'confirmed',
    'payment_pending',
    'booked',
    'documents_sent',
    'closed'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.enquiries (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  user_id uuid references auth.users(id) on delete set null,
  service_type text not null,
  status public.enquiry_status not null default 'received',
  full_name text not null,
  email text not null,
  phone text,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint enquiries_reference_length check (char_length(trim(reference)) between 4 and 40),
  constraint enquiries_service_type_check check (service_type in ('flight', 'hotel', 'holiday', 'visa', 'umrah', 'cruise', 'other')),
  constraint enquiries_full_name_length check (char_length(trim(full_name)) between 2 and 160),
  constraint enquiries_summary_length check (char_length(trim(summary)) between 2 and 500)
);

create index if not exists enquiries_user_id_idx on public.enquiries(user_id);
create index if not exists enquiries_status_idx on public.enquiries(status);
create index if not exists enquiries_service_type_idx on public.enquiries(service_type);
create index if not exists enquiries_created_at_idx on public.enquiries(created_at desc);

drop trigger if exists enquiries_set_updated_at on public.enquiries;
create trigger enquiries_set_updated_at
before update on public.enquiries
for each row execute function public.set_updated_at();

create table if not exists public.enquiry_notes (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  note text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint enquiry_notes_length check (char_length(trim(note)) between 1 and 2000)
);

create index if not exists enquiry_notes_enquiry_id_idx on public.enquiry_notes(enquiry_id);

alter table public.enquiries enable row level security;
alter table public.enquiry_notes enable row level security;

drop policy if exists "enquiries_insert_public" on public.enquiries;
create policy "enquiries_insert_public"
on public.enquiries for insert
to anon, authenticated
with check (
  status = 'received'
  and (user_id is null or user_id = auth.uid())
);

drop policy if exists "enquiries_select_own_or_staff" on public.enquiries;
create policy "enquiries_select_own_or_staff"
on public.enquiries for select
to authenticated
using (user_id = auth.uid() or public.is_staff());

drop policy if exists "enquiries_update_staff" on public.enquiries;
create policy "enquiries_update_staff"
on public.enquiries for update
to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "enquiry_notes_staff_only" on public.enquiry_notes;
create policy "enquiry_notes_staff_only"
on public.enquiry_notes for all
to authenticated
using (public.is_staff())
with check (public.is_staff());

revoke all on public.enquiries from anon, authenticated;
revoke all on public.enquiry_notes from anon, authenticated;

grant insert on public.enquiries to anon, authenticated;
grant select, update on public.enquiries to authenticated;
grant select, insert on public.enquiry_notes to authenticated;

grant execute on function public.is_staff() to authenticated;

commit;
