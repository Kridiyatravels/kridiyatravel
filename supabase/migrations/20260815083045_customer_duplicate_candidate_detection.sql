create or replace function public.normalize_customer_email(raw_email text)
returns text
language sql
immutable
set search_path = public
as $function$
  select nullif(lower(trim(coalesce(raw_email, ''))), '');
$function$;

create or replace function public.normalize_customer_phone(raw_phone text)
returns text
language sql
immutable
set search_path = public
as $function$
  select nullif(regexp_replace(coalesce(raw_phone, ''), '[^0-9]', '', 'g'), '');
$function$;

create index if not exists customers_normalized_email_idx
on public.customers (public.normalize_customer_email(email))
where archived_at is null and public.normalize_customer_email(email) is not null;

create index if not exists customers_normalized_phone_idx
on public.customers (
  public.normalize_customer_phone(coalesce(phone, whatsapp))
)
where archived_at is null
  and public.normalize_customer_phone(coalesce(phone, whatsapp)) is not null;

create or replace function public.find_customer_duplicate_candidates(
  p_email text default null,
  p_phone text default null,
  p_exclude_customer_id uuid default null
)
returns table (
  customer_id uuid,
  full_name text,
  email text,
  phone text,
  whatsapp text,
  match_reasons text[],
  linked_booking_count bigint,
  created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $function$
declare
  normalized_email text := public.normalize_customer_email(p_email);
  normalized_phone text := public.normalize_customer_phone(p_phone);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('view_customers') then
    raise exception 'Permission denied';
  end if;
  if normalized_email is null and normalized_phone is null then
    return;
  end if;

  return query
  select
    c.id,
    c.full_name,
    c.email,
    c.phone,
    c.whatsapp,
    array_remove(array[
      case when normalized_email is not null
        and public.normalize_customer_email(c.email) = normalized_email
        then 'email' end,
      case when normalized_phone is not null
        and public.normalize_customer_phone(coalesce(c.phone, c.whatsapp)) = normalized_phone
        then 'phone' end
    ], null)::text[],
    (select count(*) from public.bookings b where b.customer_id = c.id),
    c.created_at
  from public.customers c
  where c.archived_at is null
    and (p_exclude_customer_id is null or c.id <> p_exclude_customer_id)
    and (
      (normalized_email is not null
        and public.normalize_customer_email(c.email) = normalized_email)
      or (normalized_phone is not null
        and public.normalize_customer_phone(coalesce(c.phone, c.whatsapp)) = normalized_phone)
    )
  order by
    (select count(*) from public.bookings b where b.customer_id = c.id) desc,
    c.created_at asc;
end;
$function$;

revoke execute on function public.normalize_customer_email(text)
  from public, anon, authenticated;
revoke execute on function public.normalize_customer_phone(text)
  from public, anon, authenticated;
revoke execute on function public.find_customer_duplicate_candidates(text,text,uuid)
  from public, anon;
grant execute on function public.find_customer_duplicate_candidates(text,text,uuid)
  to authenticated, service_role;
