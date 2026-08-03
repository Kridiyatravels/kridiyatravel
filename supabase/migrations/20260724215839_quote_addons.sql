-- Optional paid extras per flight option (extra baggage, seat, meal,
-- insurance...). Stored as [{name, price}] so they can be shown and
-- totalled in the customer quote.
alter table public.quotes
  add column if not exists addons jsonb not null default '[]'::jsonb;
