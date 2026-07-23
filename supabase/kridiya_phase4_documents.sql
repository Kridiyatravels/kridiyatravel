-- Kridiya Travel - business settings + document generation (phase 4)
-- One singleton business_settings row (license, VAT status, bank details),
-- and a public.documents audit table for every invoice / e-ticket /
-- cancellation notice / visa rejection notice ever generated. Documents
-- snapshot the business details at time of issue, so an old invoice never
-- silently changes if bank details are updated later.

begin;

create table if not exists public.business_settings (
  id boolean primary key default true,
  legal_name text not null default 'Kridiya Travel and Tourism FZ-LLC',
  trade_license_no text,
  vat_registered boolean not null default false,
  trn text,
  bank_name text,
  bank_account_name text,
  bank_iban text,
  bank_swift text,
  cancellation_policy text,
  invoice_footer_note text,
  updated_at timestamptz not null default now(),
  constraint business_settings_singleton check (id = true)
);

insert into public.business_settings (id)
values (true)
on conflict (id) do nothing;

drop trigger if exists business_settings_set_updated_at on public.business_settings;
create trigger business_settings_set_updated_at
before update on public.business_settings
for each row execute function public.set_updated_at();

alter table public.business_settings enable row level security;

drop policy if exists "business_settings_staff_only" on public.business_settings;
create policy "business_settings_staff_only"
on public.business_settings for all
to authenticated
using (public.is_staff())
with check (public.is_staff());

revoke all on public.business_settings from anon, authenticated;
grant select, insert, update on public.business_settings to authenticated;

-- ---------- Documents ----------

do $$
begin
  create type public.document_type as enum ('invoice', 'eticket', 'cancellation', 'visa_rejection');
exception when duplicate_object then null;
end $$;

create sequence if not exists public.doc_invoice_seq start 1;
create sequence if not exists public.doc_eticket_seq start 1;
create sequence if not exists public.doc_cancellation_seq start 1;
create sequence if not exists public.doc_rejection_seq start 1;

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  document_type public.document_type not null,
  enquiry_id uuid references public.enquiries(id) on delete set null,
  customer_name text not null,
  customer_email text,
  amount_total numeric(12, 2),
  currency text default 'AED',
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint documents_customer_name_length check (char_length(trim(customer_name)) between 2 and 160)
);

create index if not exists documents_enquiry_id_idx on public.documents(enquiry_id);
create index if not exists documents_type_idx on public.documents(document_type);
create index if not exists documents_created_at_idx on public.documents(created_at desc);

create or replace function public.set_document_number()
returns trigger
language plpgsql
as $$
declare
  yr text := to_char(now(), 'YYYY');
  prefix text;
  seq_name text;
begin
  if new.document_number is not null and new.document_number <> '' then
    return new;
  end if;
  case new.document_type
    when 'invoice' then prefix := 'INV'; seq_name := 'public.doc_invoice_seq';
    when 'eticket' then prefix := 'ETK'; seq_name := 'public.doc_eticket_seq';
    when 'cancellation' then prefix := 'CXL'; seq_name := 'public.doc_cancellation_seq';
    when 'visa_rejection' then prefix := 'REJ'; seq_name := 'public.doc_rejection_seq';
  end case;
  new.document_number := prefix || '-' || yr || '-' || lpad(nextval(seq_name)::text, 4, '0');
  return new;
end;
$$;

drop trigger if exists documents_set_number on public.documents;
create trigger documents_set_number
before insert on public.documents
for each row execute function public.set_document_number();

alter table public.documents enable row level security;

drop policy if exists "documents_select_own_or_staff" on public.documents;
create policy "documents_select_own_or_staff"
on public.documents for select
to authenticated
using (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
);

drop policy if exists "documents_insert_staff" on public.documents;
create policy "documents_insert_staff"
on public.documents for insert
to authenticated
with check (public.is_staff());

drop policy if exists "documents_update_staff" on public.documents;
create policy "documents_update_staff"
on public.documents for update
to authenticated
using (public.is_staff())
with check (public.is_staff());

revoke all on public.documents from anon, authenticated;
grant select, insert, update on public.documents to authenticated;

commit;
