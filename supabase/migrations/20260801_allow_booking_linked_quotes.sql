begin;

-- Corporate portal bookings can receive quote options directly from a booking.
-- Older enquiry quotes still keep enquiry_id; booking-created quotes use booking_id.
alter table public.quotes
  add column if not exists booking_id uuid references public.bookings(id) on delete set null;

alter table public.quotes
  alter column enquiry_id drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quotes_enquiry_or_booking_check'
      and conrelid = 'public.quotes'::regclass
  ) then
    alter table public.quotes
      add constraint quotes_enquiry_or_booking_check
      check (enquiry_id is not null or booking_id is not null)
      not valid;
  end if;
end $$;

alter table public.quotes
  validate constraint quotes_enquiry_or_booking_check;

create index if not exists quotes_booking_id_idx
  on public.quotes(booking_id);

commit;
