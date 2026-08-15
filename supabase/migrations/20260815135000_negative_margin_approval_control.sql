-- Stage 3: prevent below-cost bookings without an accountable, recent owner/finance approval.
alter table public.bookings
  add column if not exists margin_exception_approved_by uuid references auth.users(id) on delete set null,
  add column if not exists margin_exception_approved_at timestamptz,
  add column if not exists margin_exception_reason text;

create or replace function public.enforce_booking_margin_approval()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_changed boolean := tg_op = 'INSERT';
  v_reason text;
begin
  if tg_op = 'UPDATE' then
    v_changed := new.selling_price is distinct from old.selling_price
      or new.supplier_cost is distinct from old.supplier_cost;
  end if;

  if new.selling_price is not null and new.supplier_cost is not null
     and new.selling_price < new.supplier_cost then
    if v_changed or new.margin_exception_approved_by is null or new.margin_exception_approved_at is null then
      if (select auth.uid()) is null then raise exception 'Authenticated approval is required for a negative-margin booking'; end if;
      perform public.require_recent_auth(1800);
      if not public.has_staff_permission('approve_discounts') then
        raise exception 'Owner/discount approval is required when selling price is below supplier cost';
      end if;
      v_reason := nullif(trim(coalesce(new.margin_exception_reason, new.staff_notes, '')), '');
      if v_reason is null or length(v_reason) < 10 then
        raise exception 'A written negative-margin exception reason of at least 10 characters is required';
      end if;
      new.margin_exception_approved_by := (select auth.uid());
      new.margin_exception_approved_at := now();
      new.margin_exception_reason := v_reason;
      insert into public.audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
      values ((select auth.uid()), 'booking.negative_margin_approved', 'booking', new.id,
        jsonb_build_object(
          'booking_reference', new.booking_reference,
          'selling_price', new.selling_price,
          'supplier_cost', new.supplier_cost,
          'negative_margin', new.selling_price - new.supplier_cost,
          'currency', new.currency,
          'reason', v_reason
        ));
    end if;
  elsif v_changed then
    new.margin_exception_approved_by := null;
    new.margin_exception_approved_at := null;
    new.margin_exception_reason := null;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_margin_approval_guard on public.bookings;
create trigger bookings_margin_approval_guard
before insert or update of selling_price, supplier_cost, margin_exception_approved_by, margin_exception_approved_at, margin_exception_reason
on public.bookings
for each row execute function public.enforce_booking_margin_approval();

-- Booking mutations use the audited workflow RPCs, not direct browser table writes.
revoke insert, update, delete on public.bookings from anon, authenticated;
drop policy if exists bookings_insert_staff on public.bookings;
drop policy if exists bookings_update_staff on public.bookings;
