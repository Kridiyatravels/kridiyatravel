-- staff_email_for_pin(pin): resolves which active staff member a 6-digit
-- PIN belongs to by matching it against their stored bcrypt password hash.
-- Returns the email ONLY when the PIN is correct, so it cannot be used to
-- enumerate staff emails. Used by the staff-pin-login Edge Function, which
-- can no longer rely on the project's (disabled) legacy service-role key.
create or replace function public.staff_email_for_pin(p_pin text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text;
begin
  if p_pin is null or p_pin !~ '^\d{6}$' then
    return null;
  end if;

  select u.email
    into v_email
  from public.staff_profiles sp
  join auth.users u on u.id = sp.user_id
  where sp.active = true
    and u.encrypted_password = extensions.crypt(p_pin, u.encrypted_password)
  limit 1;

  return v_email;
end;
$$;

revoke execute on function public.staff_email_for_pin(text) from public;
grant execute on function public.staff_email_for_pin(text) to anon, authenticated;
