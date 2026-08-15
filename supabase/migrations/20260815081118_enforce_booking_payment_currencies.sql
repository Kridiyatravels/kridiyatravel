-- Payment records linked to a booking must use the booking's canonical sale or
-- supplier currency. This protects every write path, including direct API use.
create or replace function public.enforce_customer_payment_currency()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  expected_currency text;
begin
  new.currency := upper(new.currency);
  if new.booking_id is null then
    return new;
  end if;

  select upper(b.currency)
  into expected_currency
  from public.bookings b
  where b.id = new.booking_id;

  if expected_currency is null then
    raise exception 'Linked booking not found';
  end if;
  if new.currency <> expected_currency then
    raise exception 'Customer payment currency must match booking currency (%)', expected_currency;
  end if;
  return new;
end;
$function$;

create or replace function public.enforce_supplier_payment_currency()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  expected_currency text;
begin
  new.currency := upper(new.currency);

  select upper(coalesce(b.supplier_currency, b.currency))
  into expected_currency
  from public.bookings b
  where b.id = new.booking_id;

  if expected_currency is null then
    raise exception 'Linked booking not found';
  end if;
  if new.currency <> expected_currency then
    raise exception 'Supplier payment currency must match supplier currency (%)', expected_currency;
  end if;
  return new;
end;
$function$;

drop trigger if exists payments_enforce_booking_currency on public.payments;
create trigger payments_enforce_booking_currency
before insert or update of booking_id, currency on public.payments
for each row execute function public.enforce_customer_payment_currency();

drop trigger if exists supplier_payments_enforce_booking_currency on public.supplier_payments;
create trigger supplier_payments_enforce_booking_currency
before insert or update of booking_id, currency on public.supplier_payments
for each row execute function public.enforce_supplier_payment_currency();

revoke execute on function public.enforce_customer_payment_currency()
  from public, anon, authenticated;
revoke execute on function public.enforce_supplier_payment_currency()
  from public, anon, authenticated;
