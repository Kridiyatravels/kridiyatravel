create table if not exists public.enquiry_requests (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  kind text not null check (kind in ('text', 'file')),
  label text not null,
  response_text text,
  response_file_path text,
  response_file_name text,
  responded_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint enquiry_requests_label_length check (char_length(trim(label)) between 2 and 200)
);

create index if not exists enquiry_requests_enquiry_id_idx on public.enquiry_requests(enquiry_id);

alter table public.enquiry_requests enable row level security;

drop policy if exists "enquiry_requests_select_own_or_staff" on public.enquiry_requests;
create policy "enquiry_requests_select_own_or_staff"
on public.enquiry_requests for select
to authenticated
using (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
);

drop policy if exists "enquiry_requests_insert_staff" on public.enquiry_requests;
create policy "enquiry_requests_insert_staff"
on public.enquiry_requests for insert
to authenticated
with check (public.is_staff());

drop policy if exists "enquiry_requests_update_own_response_or_staff" on public.enquiry_requests;
create policy "enquiry_requests_update_own_response_or_staff"
on public.enquiry_requests for update
to authenticated
using (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
)
with check (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
);

revoke all on public.enquiry_requests from anon, authenticated;
grant select, insert, update on public.enquiry_requests to authenticated;

do $$
begin
  create type public.quote_status as enum ('sent', 'accepted', 'declined', 'expired');
exception when duplicate_object then null;
end $$;

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  title text not null,
  description text,
  price_amount numeric(12, 2) not null,
  currency text not null default 'AED',
  valid_until timestamptz,
  terms text,
  status public.quote_status not null default 'sent',
  created_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotes_title_length check (char_length(trim(title)) between 2 and 200),
  constraint quotes_currency_length check (char_length(currency) = 3),
  constraint quotes_price_nonnegative check (price_amount >= 0)
);

create index if not exists quotes_enquiry_id_idx on public.quotes(enquiry_id);

drop trigger if exists quotes_set_updated_at on public.quotes;
create trigger quotes_set_updated_at
before update on public.quotes
for each row execute function public.set_updated_at();

create or replace function public.protect_quote_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_staff() then
    return new;
  end if;
  if old.status <> 'sent' or new.status not in ('accepted', 'declined') then
    raise exception 'Quotes can only be accepted or declined while status is sent';
  end if;
  if new.title <> old.title
     or new.description is distinct from old.description
     or new.price_amount <> old.price_amount
     or new.currency <> old.currency
     or new.valid_until is distinct from old.valid_until
     or new.terms is distinct from old.terms
     or new.enquiry_id <> old.enquiry_id then
    raise exception 'Customers may only update quote status';
  end if;
  new.responded_at := now();
  return new;
end;
$$;

drop trigger if exists quotes_protect_customer_update on public.quotes;
create trigger quotes_protect_customer_update
before update on public.quotes
for each row execute function public.protect_quote_customer_update();

alter table public.quotes enable row level security;

drop policy if exists "quotes_select_own_or_staff" on public.quotes;
create policy "quotes_select_own_or_staff"
on public.quotes for select
to authenticated
using (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
);

drop policy if exists "quotes_insert_staff" on public.quotes;
create policy "quotes_insert_staff"
on public.quotes for insert
to authenticated
with check (public.is_staff());

drop policy if exists "quotes_update_own_or_staff" on public.quotes;
create policy "quotes_update_own_or_staff"
on public.quotes for update
to authenticated
using (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
)
with check (
  public.is_staff()
  or exists (select 1 from public.enquiries e where e.id = enquiry_id and e.user_id = auth.uid())
);

revoke all on public.quotes from anon, authenticated;
grant select, insert, update on public.quotes to authenticated;

insert into storage.buckets (id, name, public)
values ('enquiry-uploads', 'enquiry-uploads', false)
on conflict (id) do nothing;

drop policy if exists "enquiry_uploads_insert_own" on storage.objects;
create policy "enquiry_uploads_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'enquiry-uploads'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "enquiry_uploads_select_own_or_staff" on storage.objects;
create policy "enquiry_uploads_select_own_or_staff"
on storage.objects for select
to authenticated
using (
  bucket_id = 'enquiry-uploads'
  and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff())
);
