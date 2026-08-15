-- Financial milestone labels must be supported by payment records. Corporate
-- approval/LPO states remain manually controllable and are intentionally not
-- constrained here.
create or replace function public.validate_booking_payment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  sale_total numeric := coalesce(new.selling_price, new.amount);
  received_total numeric;
  supplier_fully_paid boolean;
  refund_open boolean;
  refund_completed boolean;
begin
  if new.payment_status = old.payment_status then
    return new;
  end if;

  select coalesce(sum(p.amount), 0)
  into received_total
  from public.payments p
  where p.booking_id = new.id
    and p.payment_direction = 'customer_in'
    and p.status = 'received';

  select exists (
    select 1 from public.supplier_payments sp
    where sp.booking_id = new.id
      and sp.status = 'paid'
      and sp.amount_paid >= sp.amount_payable
  ) into supplier_fully_paid;

  select
    exists (
      select 1 from public.payments p
      where p.booking_id = new.id
        and p.status in ('refund_pending', 'refund_approved')
    ),
    exists (
      select 1 from public.payments p
      where p.booking_id = new.id and p.status = 'refunded'
    )
  into refund_open, refund_completed;

  if new.payment_status = 'paid'
     and (sale_total is null or sale_total <= 0 or received_total < sale_total) then
    raise exception 'Paid status requires customer receipts covering the booking total';
  end if;
  if new.payment_status = 'partially_paid'
     and (received_total <= 0 or (sale_total is not null and received_total >= sale_total)) then
    raise exception 'Partially paid status requires a positive outstanding customer balance';
  end if;
  if new.payment_status = 'supplier_paid' and not supplier_fully_paid then
    raise exception 'Supplier paid status requires a fully paid supplier record';
  end if;
  if new.payment_status = 'refund_pending' and not refund_open then
    raise exception 'Refund pending status requires an open payment refund';
  end if;
  if new.payment_status = 'refunded' and not refund_completed then
    raise exception 'Refunded status requires a completed payment refund';
  end if;

  return new;
end;
$function$;

drop trigger if exists bookings_validate_payment_status on public.bookings;
create trigger bookings_validate_payment_status
before update of payment_status on public.bookings
for each row execute function public.validate_booking_payment_status();

revoke execute on function public.validate_booking_payment_status()
  from public, anon, authenticated;
