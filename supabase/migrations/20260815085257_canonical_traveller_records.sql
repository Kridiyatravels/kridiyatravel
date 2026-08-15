create table if not exists public.travellers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  corporate_account_id uuid references public.corporate_accounts(id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) >= 2),
  date_of_birth date,
  nationality text,
  passport_number text,
  passport_expiry date,
  notes text,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint travellers_owner_required check (
    customer_id is not null or corporate_account_id is not null
  )
);

comment on table public.travellers is
  'Canonical staff-controlled traveller identity. Booking passenger rows remain immutable trip snapshots and may link here.';
comment on column public.travellers.passport_number is
  'Sensitive identity data; direct table access is restricted to authorized staff.';

create or replace function public.normalize_traveller_identity(value text)
returns text
language sql
immutable
set search_path = public
as $function$
  select nullif(regexp_replace(lower(trim(coalesce(value, ''))), '[^a-z0-9]', '', 'g'), '')
$function$;

create index if not exists travellers_customer_idx
on public.travellers (customer_id)
where archived_at is null;

create index if not exists travellers_corporate_account_idx
on public.travellers (corporate_account_id)
where archived_at is null;

create index if not exists travellers_normalized_passport_idx
on public.travellers (public.normalize_traveller_identity(passport_number))
where archived_at is null and passport_number is not null;

create index if not exists travellers_name_dob_idx
on public.travellers (public.normalize_traveller_identity(full_name), date_of_birth)
where archived_at is null;

alter table public.travellers enable row level security;

drop policy if exists travellers_select_staff on public.travellers;
create policy travellers_select_staff
on public.travellers for select to authenticated
using (
  public.has_staff_permission('view_customers')
  or public.has_staff_permission('edit_customers')
  or public.has_staff_permission('edit_bookings')
);

drop policy if exists travellers_insert_staff on public.travellers;
create policy travellers_insert_staff
on public.travellers for insert to authenticated
with check (
  public.has_staff_permission('edit_customers')
  or public.has_staff_permission('edit_bookings')
);

drop policy if exists travellers_update_staff on public.travellers;
create policy travellers_update_staff
on public.travellers for update to authenticated
using (
  public.has_staff_permission('edit_customers')
  or public.has_staff_permission('edit_bookings')
)
with check (
  public.has_staff_permission('edit_customers')
  or public.has_staff_permission('edit_bookings')
);

revoke all on table public.travellers from public, anon;
grant select, insert, update on table public.travellers to authenticated;
grant all on table public.travellers to service_role;

drop trigger if exists set_travellers_updated_at on public.travellers;
create trigger set_travellers_updated_at
before update on public.travellers
for each row execute function public.set_updated_at();

alter table public.booking_passengers
add column if not exists traveller_id uuid
references public.travellers(id) on delete set null;

create index if not exists booking_passengers_traveller_idx
on public.booking_passengers (traveller_id)
where traveller_id is not null;

alter table public.booking_travellers
add column if not exists traveller_id uuid
references public.travellers(id) on delete set null;

create index if not exists booking_travellers_traveller_idx
on public.booking_travellers (traveller_id)
where traveller_id is not null;

create or replace function public.find_traveller_duplicate_candidates(
  p_full_name text default null,
  p_date_of_birth date default null,
  p_passport_number text default null,
  p_customer_id uuid default null,
  p_corporate_account_id uuid default null,
  p_exclude_traveller_id uuid default null
)
returns table (
  traveller_id uuid,
  full_name text,
  date_of_birth date,
  nationality text,
  passport_number text,
  customer_id uuid,
  corporate_account_id uuid,
  match_reasons text[],
  match_score integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_staff_permission('view_customers')
    or public.has_staff_permission('edit_customers')
    or public.has_staff_permission('edit_bookings')
  ) then raise exception 'Permission denied'; end if;

  return query
  select
    t.id,
    t.full_name,
    t.date_of_birth,
    t.nationality,
    t.passport_number,
    t.customer_id,
    t.corporate_account_id,
    array_remove(array[
      case when public.normalize_traveller_identity(p_passport_number) is not null
             and public.normalize_traveller_identity(t.passport_number)
               = public.normalize_traveller_identity(p_passport_number)
        then 'passport' end,
      case when public.normalize_traveller_identity(p_full_name) is not null
             and p_date_of_birth is not null
             and public.normalize_traveller_identity(t.full_name)
               = public.normalize_traveller_identity(p_full_name)
             and t.date_of_birth = p_date_of_birth
        then 'name_and_date_of_birth' end,
      case when p_customer_id is not null and t.customer_id = p_customer_id
        then 'same_customer' end,
      case when p_corporate_account_id is not null
             and t.corporate_account_id = p_corporate_account_id
        then 'same_company' end
    ], null)::text[] as match_reasons,
    (case when public.normalize_traveller_identity(p_passport_number) is not null
             and public.normalize_traveller_identity(t.passport_number)
               = public.normalize_traveller_identity(p_passport_number) then 100 else 0 end)
    + (case when public.normalize_traveller_identity(p_full_name) is not null
             and p_date_of_birth is not null
             and public.normalize_traveller_identity(t.full_name)
               = public.normalize_traveller_identity(p_full_name)
             and t.date_of_birth = p_date_of_birth then 80 else 0 end)
    + (case when p_customer_id is not null and t.customer_id = p_customer_id then 10 else 0 end)
    + (case when p_corporate_account_id is not null
             and t.corporate_account_id = p_corporate_account_id then 10 else 0 end),
    t.updated_at
  from public.travellers t
  where t.archived_at is null
    and (p_exclude_traveller_id is null or t.id <> p_exclude_traveller_id)
    and (
      (public.normalize_traveller_identity(p_passport_number) is not null
       and public.normalize_traveller_identity(t.passport_number)
         = public.normalize_traveller_identity(p_passport_number))
      or
      (public.normalize_traveller_identity(p_full_name) is not null
       and p_date_of_birth is not null
       and public.normalize_traveller_identity(t.full_name)
         = public.normalize_traveller_identity(p_full_name)
       and t.date_of_birth = p_date_of_birth)
    )
  order by match_score desc, t.updated_at desc, t.id;
end;
$function$;

revoke execute on function public.find_traveller_duplicate_candidates(
  text,date,text,uuid,uuid,uuid
) from public, anon;
grant execute on function public.find_traveller_duplicate_candidates(
  text,date,text,uuid,uuid,uuid
) to authenticated, service_role;

create or replace function public.merge_traveller_records(
  p_source_traveller_id uuid,
  p_target_traveller_id uuid,
  p_source_expected_updated_at timestamptz,
  p_target_expected_updated_at timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  source_traveller public.travellers%rowtype;
  target_traveller public.travellers%rowtype;
  moved_passenger_snapshots integer;
  moved_retail_snapshots integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_staff_permission('edit_customers')
    or public.has_staff_permission('edit_bookings')
  ) then raise exception 'Permission denied'; end if;
  if p_source_traveller_id = p_target_traveller_id then
    raise exception 'Source and target travellers must be different';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'A merge reason of at least 10 characters is required';
  end if;
  if p_source_expected_updated_at is null or p_target_expected_updated_at is null then
    raise exception 'Expected source and target versions are required';
  end if;

  perform id from public.travellers
  where id in (p_source_traveller_id, p_target_traveller_id)
  order by id for update;

  select * into source_traveller from public.travellers
  where id = p_source_traveller_id;
  select * into target_traveller from public.travellers
  where id = p_target_traveller_id;

  if source_traveller.id is null or source_traveller.archived_at is not null then
    raise exception 'Active source traveller not found';
  end if;
  if target_traveller.id is null or target_traveller.archived_at is not null then
    raise exception 'Active target traveller not found';
  end if;
  if source_traveller.updated_at <> p_source_expected_updated_at
     or target_traveller.updated_at <> p_target_expected_updated_at then
    raise exception 'Traveller changed after merge review. Reload both records.';
  end if;
  if source_traveller.customer_id is not null
     and target_traveller.customer_id is not null
     and source_traveller.customer_id <> target_traveller.customer_id then
    raise exception 'Travellers belong to different customers and cannot be merged';
  end if;
  if source_traveller.corporate_account_id is not null
     and target_traveller.corporate_account_id is not null
     and source_traveller.corporate_account_id <> target_traveller.corporate_account_id then
    raise exception 'Travellers belong to different companies and cannot be merged';
  end if;
  if public.normalize_traveller_identity(source_traveller.passport_number) is not null
     and public.normalize_traveller_identity(target_traveller.passport_number) is not null
     and public.normalize_traveller_identity(source_traveller.passport_number)
       <> public.normalize_traveller_identity(target_traveller.passport_number) then
    raise exception 'Travellers have conflicting passport numbers';
  end if;

  update public.booking_passengers
  set traveller_id = p_target_traveller_id, updated_at = now()
  where traveller_id = p_source_traveller_id;
  get diagnostics moved_passenger_snapshots = row_count;

  update public.booking_travellers
  set traveller_id = p_target_traveller_id
  where traveller_id = p_source_traveller_id;
  get diagnostics moved_retail_snapshots = row_count;

  update public.travellers
  set customer_id = coalesce(target_traveller.customer_id, source_traveller.customer_id),
      corporate_account_id = coalesce(
        target_traveller.corporate_account_id, source_traveller.corporate_account_id
      ),
      date_of_birth = coalesce(target_traveller.date_of_birth, source_traveller.date_of_birth),
      nationality = coalesce(target_traveller.nationality, source_traveller.nationality),
      passport_number = coalesce(
        target_traveller.passport_number, source_traveller.passport_number
      ),
      passport_expiry = coalesce(
        target_traveller.passport_expiry, source_traveller.passport_expiry
      ),
      notes = trim(both from concat_ws(
        E'\n', nullif(target_traveller.notes, ''),
        case when nullif(source_traveller.notes, '') is not null
          then 'Merged traveller note: ' || source_traveller.notes end
      )),
      updated_at = now()
  where id = p_target_traveller_id;

  update public.travellers
  set active = false,
      archived_at = now(),
      notes = trim(both from concat_ws(
        E'\n', nullif(source_traveller.notes, ''),
        'Merged into traveller ' || p_target_traveller_id::text || ': ' || trim(p_reason)
      )),
      updated_at = now()
  where id = p_source_traveller_id;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(), 'traveller.merged', 'traveller', p_target_traveller_id,
    jsonb_build_object(
      'source_traveller_id', p_source_traveller_id,
      'target_traveller_id', p_target_traveller_id,
      'reason', trim(p_reason),
      'moved_booking_passengers', moved_passenger_snapshots,
      'moved_booking_travellers', moved_retail_snapshots
    )
  );

  return jsonb_build_object(
    'ok', true,
    'source_traveller_id', p_source_traveller_id,
    'target_traveller_id', p_target_traveller_id,
    'moved_booking_passengers', moved_passenger_snapshots,
    'moved_booking_travellers', moved_retail_snapshots
  );
end;
$function$;

revoke execute on function public.merge_traveller_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_traveller_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;
