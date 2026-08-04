begin;

-- Staff-originated leads enter the same enquiry pipeline as website leads,
-- but are created through a dedicated authenticated function so source and
-- audit metadata cannot be impersonated by an anonymous form submission.
create or replace function public.create_staff_enquiry(
  p_full_name text,
  p_phone text,
  p_email text,
  p_service_type text,
  p_source text,
  p_summary text,
  p_internal_note text default null
)
returns public.enquiries
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_reference text;
  v_enquiry public.enquiries;
begin
  if auth.uid() is null or not public.is_staff() then
    raise exception 'Staff access required' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_full_name, '')), '') is null then
    raise exception 'Customer name is required' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_phone, '')), '') is null
     and nullif(trim(coalesce(p_email, '')), '') is null then
    raise exception 'Phone or email is required' using errcode = '22023';
  end if;
  if p_service_type not in ('flight', 'hotel', 'holiday', 'visa', 'umrah', 'cruise', 'other') then
    raise exception 'Invalid service type' using errcode = '22023';
  end if;
  if p_source not in ('phone', 'whatsapp', 'email', 'referral', 'manual', 'other') then
    raise exception 'Invalid enquiry source' using errcode = '22023';
  end if;

  v_reference := 'KD-MNL-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

  insert into public.enquiries (
    reference, user_id, service_type, status, full_name, email, phone,
    summary, details, first_touch_source, first_touch_medium,
    last_touch_source, last_touch_medium, traffic_type, source_basis,
    source_confidence, self_reported_source, marketing_consent
  ) values (
    v_reference,
    null,
    p_service_type,
    'received',
    trim(p_full_name),
    coalesce(nullif(lower(trim(coalesce(p_email, ''))), ''), lower(v_reference) || '@phone.invalid'),
    nullif(trim(coalesce(p_phone, '')), ''),
    trim(p_summary),
    jsonb_build_object(
      'source', p_source,
      'created_by_staff', auth.uid(),
      'contact_email_provided', nullif(trim(coalesce(p_email, '')), '') is not null
    ),
    p_source,
    'staff',
    p_source,
    'staff',
    case when p_source = 'referral' then 'referral' else 'direct' end,
    'staff_recorded',
    'high',
    p_source,
    false
  )
  returning * into v_enquiry;

  if nullif(trim(coalesce(p_internal_note, '')), '') is not null then
    insert into public.enquiry_notes (enquiry_id, note, created_by)
    values (v_enquiry.id, trim(p_internal_note), auth.uid());
  end if;

  return v_enquiry;
end;
$$;

revoke all on function public.create_staff_enquiry(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.create_staff_enquiry(text, text, text, text, text, text, text) to authenticated, service_role;

comment on function public.create_staff_enquiry(text, text, text, text, text, text, text) is
  'Creates a staff-originated phone, WhatsApp, email, referral, manual, or other enquiry with consent disabled by default.';

commit;
