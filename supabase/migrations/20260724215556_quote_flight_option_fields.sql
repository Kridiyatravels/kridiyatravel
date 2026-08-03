-- Richer flight-quote options: each quote row is one option with its own
-- airline, stops, timings and baggage, so staff can send several options
-- per enquiry and compile them into one customer message.
alter table public.quotes
  add column if not exists airline text,
  add column if not exists stops text,
  add column if not exists outbound text,
  add column if not exists inbound text,
  add column if not exists baggage text;
