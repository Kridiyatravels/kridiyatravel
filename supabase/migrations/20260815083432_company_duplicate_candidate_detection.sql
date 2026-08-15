create or replace function public.normalize_company_name(raw_name text)
returns text
language sql
immutable
set search_path = public
as $function$
  select nullif(lower(regexp_replace(trim(coalesce(raw_name, '')), '\s+', ' ', 'g')), '');
$function$;

create or replace function public.normalize_company_registration(raw_value text)
returns text
language sql
immutable
set search_path = public
as $function$
  select nullif(upper(regexp_replace(coalesce(raw_value, ''), '[^0-9A-Za-z]', '', 'g')), '');
$function$;

create index if not exists corporate_accounts_normalized_name_idx
on public.corporate_accounts (public.normalize_company_name(company_name))
where archived_at is null;

create index if not exists corporate_accounts_normalized_trade_license_idx
on public.corporate_accounts (
  public.normalize_company_registration(trade_license_no)
)
where archived_at is null
  and public.normalize_company_registration(trade_license_no) is not null;

create index if not exists corporate_accounts_normalized_trn_idx
on public.corporate_accounts (public.normalize_company_registration(trn))
where archived_at is null
  and public.normalize_company_registration(trn) is not null;

create or replace function public.find_company_duplicate_candidates(
  p_company_name text default null,
  p_trade_license_no text default null,
  p_trn text default null,
  p_exclude_company_id uuid default null
)
returns table (
  company_id uuid,
  company_name text,
  trade_license_no text,
  trn text,
  status text,
  match_reasons text[],
  linked_booking_count bigint,
  portal_member_count bigint,
  created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $function$
declare
  normalized_name text := public.normalize_company_name(p_company_name);
  normalized_license text := public.normalize_company_registration(p_trade_license_no);
  normalized_trn text := public.normalize_company_registration(p_trn);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('view_corporates') then
    raise exception 'Permission denied';
  end if;
  if normalized_name is null and normalized_license is null and normalized_trn is null then
    return;
  end if;

  return query
  select
    ca.id,
    ca.company_name,
    ca.trade_license_no,
    ca.trn,
    ca.status,
    array_remove(array[
      case when normalized_name is not null
        and public.normalize_company_name(ca.company_name) = normalized_name
        then 'company_name' end,
      case when normalized_license is not null
        and public.normalize_company_registration(ca.trade_license_no) = normalized_license
        then 'trade_license_no' end,
      case when normalized_trn is not null
        and public.normalize_company_registration(ca.trn) = normalized_trn
        then 'trn' end
    ], null)::text[],
    counts.booking_count,
    counts.member_count,
    ca.created_at
  from public.corporate_accounts ca
  cross join lateral (
    select
      (select count(*) from public.bookings b where b.corporate_account_id = ca.id) as booking_count,
      (select count(*) from public.corporate_portal_members cpm where cpm.corporate_account_id = ca.id) as member_count
  ) counts
  where ca.archived_at is null
    and (p_exclude_company_id is null or ca.id <> p_exclude_company_id)
    and (
      (normalized_name is not null
        and public.normalize_company_name(ca.company_name) = normalized_name)
      or (normalized_license is not null
        and public.normalize_company_registration(ca.trade_license_no) = normalized_license)
      or (normalized_trn is not null
        and public.normalize_company_registration(ca.trn) = normalized_trn)
    )
  order by counts.booking_count desc, counts.member_count desc, ca.created_at asc;
end;
$function$;

revoke execute on function public.normalize_company_name(text)
  from public, anon, authenticated;
revoke execute on function public.normalize_company_registration(text)
  from public, anon, authenticated;
revoke execute on function public.find_company_duplicate_candidates(text,text,text,uuid)
  from public, anon;
grant execute on function public.find_company_duplicate_candidates(text,text,text,uuid)
  to authenticated, service_role;
