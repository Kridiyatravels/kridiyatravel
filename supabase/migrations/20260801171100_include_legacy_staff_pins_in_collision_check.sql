create or replace function public.staff_pin_in_use(p_pin text, p_exclude_user_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.staff_profiles sp
    join auth.users u on u.id = sp.user_id
    left join public.staff_pin_credentials pc on pc.user_id = sp.user_id
    where sp.active = true
      and (p_exclude_user_id is null or sp.user_id <> p_exclude_user_id)
      and (
        (pc.user_id is not null and pc.pin_hash = extensions.crypt(p_pin, pc.pin_hash))
        or
        (pc.user_id is null and u.encrypted_password = extensions.crypt(p_pin, u.encrypted_password))
      )
  );
$$;

revoke execute on function public.staff_pin_in_use(text, uuid) from public, anon, authenticated;
grant execute on function public.staff_pin_in_use(text, uuid) to service_role;
