alter table public.payments
  drop constraint if exists payments_payment_link_https;
alter table public.payments
  add constraint payments_payment_link_https
  check (payment_link is null or (char_length(payment_link) <= 2048 and payment_link ~* '^https://[^[:space:]]+$'));

create or replace function public.get_my_payment_receipt(p_payment_id uuid)
returns table(
  receipt_number text,
  payment_reference text,
  booking_reference text,
  booking_title text,
  route_or_destination text,
  amount numeric,
  currency text,
  payment_method text,
  received_at timestamptz,
  issued_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.document_number, p.payment_reference, b.booking_reference, b.title,
         b.route_or_destination, p.amount, p.currency, p.method,
         coalesce(p.received_at, p.created_at), d.created_at
  from public.payments p
  join public.bookings b on b.id = p.booking_id
  join public.documents d on d.id = p.receipt_document_id and d.document_type = 'receipt'
  where p.id = p_payment_id
    and auth.uid() is not null
    and b.user_id = auth.uid()
    and p.payment_direction = 'customer_in'
    and p.status = 'received'
  limit 1
$$;

revoke execute on function public.get_my_payment_receipt(uuid) from public, anon;
grant execute on function public.get_my_payment_receipt(uuid) to authenticated, service_role;
