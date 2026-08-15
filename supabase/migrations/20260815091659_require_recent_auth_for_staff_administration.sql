alter function public.update_staff_permissions(uuid,jsonb)
rename to update_staff_permissions_internal_20260815;
revoke execute on function public.update_staff_permissions_internal_20260815(uuid,jsonb)
from public, anon, authenticated, service_role;

create function public.update_staff_permissions(target_user_id uuid, permissions jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.update_staff_permissions_internal_20260815(target_user_id, permissions);
end;
$function$;

revoke execute on function public.update_staff_permissions(uuid,jsonb) from public, anon;
grant execute on function public.update_staff_permissions(uuid,jsonb)
to authenticated, service_role;

alter function public.update_staff_profile(
  uuid,text,text,text,text,public.staff_role,boolean,text,timestamptz
)
rename to update_staff_profile_internal_20260815;
revoke execute on function public.update_staff_profile_internal_20260815(
  uuid,text,text,text,text,public.staff_role,boolean,text,timestamptz
) from public, anon, authenticated, service_role;

create function public.update_staff_profile(
  target_user_id uuid,
  full_name text,
  department text default null,
  job_title text default null,
  phone text default null,
  role public.staff_role default 'staff'::public.staff_role,
  active boolean default true,
  notes text default null,
  hold_until timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.update_staff_profile_internal_20260815(
    target_user_id, full_name, department, job_title, phone,
    role, active, notes, hold_until
  );
end;
$function$;

revoke execute on function public.update_staff_profile(
  uuid,text,text,text,text,public.staff_role,boolean,text,timestamptz
) from public, anon;
grant execute on function public.update_staff_profile(
  uuid,text,text,text,text,public.staff_role,boolean,text,timestamptz
) to authenticated, service_role;
