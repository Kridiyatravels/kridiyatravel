create or replace function public.list_my_travellers()
returns table (
  id uuid,
  full_name text,
  date_of_birth date,
  nationality text,
  passport_masked text,
  has_passport boolean,
  passport_expiry date,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $function$
  select t.id, t.full_name, t.date_of_birth, t.nationality,
    case when public.normalize_traveller_identity(t.passport_number) is null then null
      else '**** ' || right(public.normalize_traveller_identity(t.passport_number), 4) end,
    public.normalize_traveller_identity(t.passport_number) is not null,
    t.passport_expiry, t.updated_at
  from public.travellers t
  join public.customers c on c.id=t.customer_id
  where auth.uid() is not null
    and c.auth_user_id=auth.uid()
    and c.archived_at is null
    and t.archived_at is null
  order by t.full_name,t.date_of_birth nulls last,t.id;
$function$;

revoke execute on function public.list_my_travellers() from public, anon;
grant execute on function public.list_my_travellers() to authenticated, service_role;
