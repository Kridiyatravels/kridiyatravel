create or replace function public.list_b2b_portals()
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bp.id,
    'portal_name', bp.portal_name,
    'website_url', bp.website_url,
    'service_scope', bp.service_scope,
    'username_hint', bp.username_hint,
    'password_location', bp.password_location,
    'owner_notes', bp.owner_notes,
    'status', bp.status,
    'created_at', bp.created_at,
    'updated_at', bp.updated_at
  ) order by case when bp.status = 'active' then 0 else 1 end, bp.portal_name), '[]'::jsonb)
  from public.b2b_portals bp
  where public.is_staff();
$function$;

create or replace function public.update_b2b_portal(
  p_portal_id uuid,
  p_portal_name text,
  p_website_url text,
  p_service_scope text default 'all',
  p_username_hint text default null,
  p_password_location text default 'Password manager',
  p_owner_notes text default null,
  p_status text default 'active'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_portals') then
    raise exception 'Portal management permission required';
  end if;

  update public.b2b_portals
     set portal_name = trim(p_portal_name),
         website_url = trim(p_website_url),
         service_scope = coalesce(nullif(trim(coalesce(p_service_scope, '')), ''), 'all'),
         username_hint = nullif(trim(coalesce(p_username_hint, '')), ''),
         password_location = coalesce(nullif(trim(coalesce(p_password_location, '')), ''), 'Password manager'),
         owner_notes = nullif(trim(coalesce(p_owner_notes, '')), ''),
         status = case when lower(coalesce(p_status, 'active')) = 'inactive' then 'inactive' else 'active' end,
         updated_at = now()
   where id = p_portal_id;

  if not found then
    raise exception 'Portal not found';
  end if;

  return p_portal_id;
end;
$function$;

create or replace function public.set_b2b_portal_status(p_portal_id uuid, p_status text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_portals') then
    raise exception 'Portal management permission required';
  end if;

  update public.b2b_portals
     set status = case when lower(coalesce(p_status, 'active')) = 'inactive' then 'inactive' else 'active' end,
         updated_at = now()
   where id = p_portal_id;

  if not found then
    raise exception 'Portal not found';
  end if;

  return p_portal_id;
end;
$function$;

create or replace function public.delete_b2b_portal(p_portal_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_portals') then
    raise exception 'Portal management permission required';
  end if;

  delete from public.b2b_portals where id = p_portal_id;

  if not found then
    raise exception 'Portal not found';
  end if;

  return p_portal_id;
end;
$function$;

revoke execute on function public.update_b2b_portal(uuid, text, text, text, text, text, text, text) from public, anon;
revoke execute on function public.set_b2b_portal_status(uuid, text) from public, anon;
revoke execute on function public.delete_b2b_portal(uuid) from public, anon;
grant execute on function public.update_b2b_portal(uuid, text, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.set_b2b_portal_status(uuid, text) to authenticated, service_role;
grant execute on function public.delete_b2b_portal(uuid) to authenticated, service_role;
