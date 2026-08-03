-- Add admin-only staff monitoring summary for operational oversight.
-- Applied to project jmvqqpughlzeqrcyavwz on 2026-07-24.

create or replace function public.staff_monitoring_summary(days_back integer default 30)
returns table(
  user_id uuid,
  full_name text,
  email text,
  role public.staff_role,
  active boolean,
  bookings_created integer,
  tasks_open integer,
  tasks_completed integer,
  payments_recorded integer,
  documents_recorded integer,
  activity_events integer,
  last_activity_at timestamp with time zone
)
language sql
security definer
set search_path to 'public'
as $function$
  select
    sp.user_id,
    sp.full_name,
    au.email,
    coalesce(sr.role, 'staff'::public.staff_role) as role,
    sp.active,
    count(distinct b.id)::integer as bookings_created,
    count(distinct t_open.id)::integer as tasks_open,
    count(distinct t_done.id)::integer as tasks_completed,
    count(distinct p.id)::integer as payments_recorded,
    count(distinct bd.id)::integer as documents_recorded,
    count(distinct ae.id)::integer as activity_events,
    max(ae.created_at) as last_activity_at
  from public.staff_profiles sp
  left join auth.users au on au.id = sp.user_id
  left join public.staff_roles sr on sr.user_id = sp.user_id
  left join public.bookings b on b.created_by = sp.user_id
    and b.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.tasks_reminders t_open on t_open.assigned_to = sp.user_id
    and t_open.status <> 'completed'
  left join public.tasks_reminders t_done on t_done.assigned_to = sp.user_id
    and t_done.status = 'completed'
    and t_done.completed_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.payments p on p.created_by = sp.user_id
    and p.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.booking_documents bd on bd.created_by = sp.user_id
    and bd.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  left join public.audit_events ae on ae.actor_user_id = sp.user_id
    and ae.created_at >= now() - make_interval(days => greatest(1, least(days_back, 365)))
  where public.is_admin()
  group by sp.user_id, sp.full_name, au.email, sr.role, sp.active
  order by sp.active desc, activity_events desc, sp.full_name;
$function$;

revoke execute on function public.staff_monitoring_summary(integer) from public;
revoke execute on function public.staff_monitoring_summary(integer) from anon;
grant execute on function public.staff_monitoring_summary(integer) to authenticated;
