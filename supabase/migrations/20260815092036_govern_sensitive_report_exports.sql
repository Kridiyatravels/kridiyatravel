create or replace function public.authorize_sensitive_export(
  p_export_type text,
  p_row_count integer,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  export_type text := lower(trim(coalesce(p_export_type, '')));
  event_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.require_recent_auth(1800);
  if not public.has_staff_permission('export_reports') then
    raise exception 'Report export permission required';
  end if;
  if export_type not in (
    'accounting_report', 'owner_review', 'owner_finance_summary',
    'bookings', 'payments', 'corporate_accounts', 'documents',
    'sharepoint_folder_map', 'staff', 'activity', 'backup_pack'
  ) then raise exception 'Unsupported export type'; end if;
  if p_row_count is null or p_row_count < 0 or p_row_count > 100000 then
    raise exception 'Invalid export row count';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'An export purpose of at least 10 characters is required';
  end if;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, metadata
  ) values (
    auth.uid(), 'report.export_authorized', 'report_export',
    jsonb_build_object(
      'export_type', export_type,
      'row_count', p_row_count,
      'reason', trim(p_reason),
      'authorized_at', now()
    )
  ) returning id into event_id;

  return event_id;
end;
$function$;

revoke execute on function public.authorize_sensitive_export(text,integer,text)
from public, anon;
grant execute on function public.authorize_sensitive_export(text,integer,text)
to authenticated, service_role;
