-- Staff booking status edits must be based on the version they loaded. This
-- prevents a stale browser tab from overwriting a newer operational update.
create or replace function public.update_operations_booking_status_v2(
  p_booking_id uuid,
  p_status public.booking_status,
  p_payment_status text,
  p_document_status text,
  p_expected_updated_at timestamptz,
  p_supplier_reference text default null::text,
  p_staff_notes text default null::text
)
returns timestamptz
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ref text;
  v_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_bookings') then
    raise exception 'Permission denied';
  end if;
  if p_expected_updated_at is null then
    raise exception 'Expected booking version is required';
  end if;

  update public.bookings
  set status = p_status,
      payment_status = p_payment_status,
      document_status = p_document_status,
      supplier_reference = nullif(trim(coalesce(p_supplier_reference, '')), ''),
      staff_notes = nullif(trim(coalesce(p_staff_notes, '')), ''),
      updated_at = clock_timestamp()
  where id = p_booking_id
    and updated_at = p_expected_updated_at
  returning booking_reference, updated_at into v_ref, v_updated_at;

  if v_ref is null then
    if exists (select 1 from public.bookings where id = p_booking_id) then
      raise exception 'Booking changed after this page was loaded. Reload and review the latest values.';
    end if;
    raise exception 'Booking not found';
  end if;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(),
    'booking.status_updated',
    'booking',
    p_booking_id,
    jsonb_build_object(
      'reference', v_ref,
      'status', p_status,
      'payment_status', p_payment_status,
      'document_status', p_document_status,
      'expected_updated_at', p_expected_updated_at,
      'updated_at', v_updated_at
    )
  );

  return v_updated_at;
end;
$function$;

revoke execute on function public.update_operations_booking_status_v2(
  uuid,public.booking_status,text,text,timestamptz,text,text
) from public, anon;
grant execute on function public.update_operations_booking_status_v2(
  uuid,public.booking_status,text,text,timestamptz,text,text
) to authenticated, service_role;

-- Staff browsers must use the version-checked function. Retain service-role
-- access to the legacy function only for controlled backend compatibility.
revoke execute on function public.update_operations_booking_status(
  uuid,public.booking_status,text,text,text,text
) from authenticated;
