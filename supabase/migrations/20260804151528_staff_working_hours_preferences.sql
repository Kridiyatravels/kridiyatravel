begin;

alter table public.staff_notification_preferences
  add column if not exists workday_start time not null default '09:00',
  add column if not exists workday_end time not null default '18:00',
  add column if not exists working_days smallint[] not null default array[1,2,3,4,5,6]::smallint[];

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'staff_notification_preferences_workday_check') then
    alter table public.staff_notification_preferences add constraint staff_notification_preferences_workday_check
      check (workday_start < workday_end);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'staff_notification_preferences_working_days_check') then
    alter table public.staff_notification_preferences add constraint staff_notification_preferences_working_days_check
      check (working_days <@ array[0,1,2,3,4,5,6]::smallint[] and cardinality(working_days) > 0);
  end if;
end $$;

commit;
