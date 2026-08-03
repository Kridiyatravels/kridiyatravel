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
  ) order by bp.portal_name), '[]'::jsonb)
  from public.b2b_portals bp
  where bp.status = 'active'
    and public.is_staff();
$function$;

create or replace function public.create_b2b_portal(
  p_portal_name text,
  p_website_url text,
  p_service_scope text default 'all',
  p_username_hint text default null,
  p_password_location text default 'Password manager',
  p_owner_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('manage_portals') then
    raise exception 'Portal management permission required';
  end if;

  insert into public.b2b_portals (
    portal_name,
    website_url,
    service_scope,
    username_hint,
    password_location,
    owner_notes,
    created_by
  ) values (
    trim(p_portal_name),
    trim(p_website_url),
    coalesce(nullif(trim(coalesce(p_service_scope, '')), ''), 'all'),
    nullif(trim(coalesce(p_username_hint, '')), ''),
    coalesce(nullif(trim(coalesce(p_password_location, '')), ''), 'Password manager'),
    nullif(trim(coalesce(p_owner_notes, '')), ''),
    auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$function$;

revoke execute on function public.list_b2b_portals() from public, anon;
revoke execute on function public.create_b2b_portal(text, text, text, text, text, text) from public, anon;
grant execute on function public.list_b2b_portals() to authenticated, service_role;
grant execute on function public.create_b2b_portal(text, text, text, text, text, text) to authenticated, service_role;
