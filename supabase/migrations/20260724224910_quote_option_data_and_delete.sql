-- Flexible per-service field store for quote options (so flight, visa,
-- hotel, etc. can each keep their own fields without new columns each time).
alter table public.quotes
  add column if not exists option_data jsonb not null default '{}'::jsonb;

-- Allow staff to remove an option they added (needed for the +/remove flow).
drop policy if exists quotes_delete_staff on public.quotes;
create policy "quotes_delete_staff" on public.quotes
  for delete to authenticated using (public.is_staff());
