create or replace function public.grant_staff_by_email(target_email text, target_role public.staff_role default 'staff')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_id uuid;
begin
  if not public.is_staff() then
    raise exception 'Only staff can grant staff access';
  end if;

  select id into target_id from auth.users where lower(email) = lower(trim(target_email)) limit 1;

  if target_id is null then
    return 'not_found';
  end if;

  insert into public.staff_roles (user_id, role)
  values (target_id, target_role)
  on conflict (user_id) do update set role = excluded.role;

  return 'granted';
end;
$$;

create or replace function public.revoke_staff(target_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Only staff can revoke staff access';
  end if;
  if target_user_id = auth.uid() then
    return 'cannot_remove_self';
  end if;
  delete from public.staff_roles where user_id = target_user_id;
  return 'revoked';
end;
$$;

create or replace function public.list_staff()
returns table(user_id uuid, email text, role public.staff_role, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Only staff can view the staff list';
  end if;
  return query
    select sr.user_id, u.email, sr.role, sr.created_at
    from public.staff_roles sr
    join auth.users u on u.id = sr.user_id
    order by sr.created_at asc;
end;
$$;

revoke execute on function public.grant_staff_by_email(text, public.staff_role) from anon, authenticated;
revoke execute on function public.revoke_staff(uuid) from anon, authenticated;
revoke execute on function public.list_staff() from anon, authenticated;

grant execute on function public.grant_staff_by_email(text, public.staff_role) to authenticated;
grant execute on function public.revoke_staff(uuid) to authenticated;
grant execute on function public.list_staff() to authenticated;
