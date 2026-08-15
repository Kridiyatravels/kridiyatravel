create or replace function public.require_recent_auth(max_age_seconds integer default 1800)
returns void
language plpgsql
stable
security invoker
set search_path = public
as $function$
declare
  issued_at_epoch numeric;
  auth_age_seconds numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if max_age_seconds < 60 or max_age_seconds > 86400 then
    raise exception 'Invalid recent-auth window';
  end if;

  begin
    issued_at_epoch := nullif(auth.jwt()->>'iat', '')::numeric;
  exception when others then
    issued_at_epoch := null;
  end;
  if issued_at_epoch is null then
    raise exception 'Recent authentication required. Sign in again to continue.';
  end if;

  auth_age_seconds := extract(epoch from now()) - issued_at_epoch;
  if auth_age_seconds < -60 or auth_age_seconds > max_age_seconds then
    raise exception 'Recent authentication required. Sign in again to continue.';
  end if;
end;
$function$;

revoke execute on function public.require_recent_auth(integer) from public, anon;
grant execute on function public.require_recent_auth(integer) to authenticated, service_role;

alter function public.approve_payment_refund(uuid,text)
rename to approve_payment_refund_internal_20260815;
revoke execute on function public.approve_payment_refund_internal_20260815(uuid,text)
from public, anon, authenticated, service_role;

create function public.approve_payment_refund(
  p_payment_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.approve_payment_refund_internal_20260815(p_payment_id, p_note);
end;
$function$;

revoke execute on function public.approve_payment_refund(uuid,text) from public, anon;
grant execute on function public.approve_payment_refund(uuid,text) to authenticated, service_role;

alter function public.complete_payment_refund(uuid,text,text,text)
rename to complete_payment_refund_internal_20260815;
revoke execute on function public.complete_payment_refund_internal_20260815(uuid,text,text,text)
from public, anon, authenticated, service_role;

create function public.complete_payment_refund(
  p_payment_id uuid,
  p_refund_method text,
  p_refund_reference text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.complete_payment_refund_internal_20260815(
    p_payment_id, p_refund_method, p_refund_reference, p_note
  );
end;
$function$;

revoke execute on function public.complete_payment_refund(uuid,text,text,text)
from public, anon;
grant execute on function public.complete_payment_refund(uuid,text,text,text)
to authenticated, service_role;

alter function public.merge_customer_records(uuid,uuid,timestamptz,timestamptz,text)
rename to merge_customer_records_internal_20260815;
revoke execute on function public.merge_customer_records_internal_20260815(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon, authenticated, service_role;

create function public.merge_customer_records(
  p_source_customer_id uuid,
  p_target_customer_id uuid,
  p_source_expected_updated_at timestamptz,
  p_target_expected_updated_at timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.merge_customer_records_internal_20260815(
    p_source_customer_id, p_target_customer_id,
    p_source_expected_updated_at, p_target_expected_updated_at, p_reason
  );
end;
$function$;

revoke execute on function public.merge_customer_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_customer_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;

alter function public.merge_company_records(uuid,uuid,timestamptz,timestamptz,text)
rename to merge_company_records_internal_20260815;
revoke execute on function public.merge_company_records_internal_20260815(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon, authenticated, service_role;

create function public.merge_company_records(
  p_source_company_id uuid,
  p_target_company_id uuid,
  p_source_expected_updated_at timestamptz,
  p_target_expected_updated_at timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.merge_company_records_internal_20260815(
    p_source_company_id, p_target_company_id,
    p_source_expected_updated_at, p_target_expected_updated_at, p_reason
  );
end;
$function$;

revoke execute on function public.merge_company_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_company_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;

alter function public.merge_traveller_records(uuid,uuid,timestamptz,timestamptz,text)
rename to merge_traveller_records_internal_20260815;
revoke execute on function public.merge_traveller_records_internal_20260815(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon, authenticated, service_role;

create function public.merge_traveller_records(
  p_source_traveller_id uuid,
  p_target_traveller_id uuid,
  p_source_expected_updated_at timestamptz,
  p_target_expected_updated_at timestamptz,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.require_recent_auth(1800);
  return public.merge_traveller_records_internal_20260815(
    p_source_traveller_id, p_target_traveller_id,
    p_source_expected_updated_at, p_target_expected_updated_at, p_reason
  );
end;
$function$;

revoke execute on function public.merge_traveller_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_traveller_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;
