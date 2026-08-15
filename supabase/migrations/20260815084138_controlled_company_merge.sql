create or replace function public.merge_company_records(
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
declare
  source_company public.corporate_accounts%rowtype;
  target_company public.corporate_accounts%rowtype;
  moved_bookings integer;
  moved_contacts integer;
  moved_members integer;
  moved_payments integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Permission denied';
  end if;
  if p_source_company_id = p_target_company_id then
    raise exception 'Source and target companies must be different';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'A merge reason of at least 10 characters is required';
  end if;
  if p_source_expected_updated_at is null or p_target_expected_updated_at is null then
    raise exception 'Expected source and target versions are required';
  end if;

  perform id
  from public.corporate_accounts
  where id in (p_source_company_id, p_target_company_id)
  order by id
  for update;

  select * into source_company
  from public.corporate_accounts where id = p_source_company_id;
  select * into target_company
  from public.corporate_accounts where id = p_target_company_id;

  if source_company.id is null or source_company.archived_at is not null then
    raise exception 'Active source company not found';
  end if;
  if target_company.id is null or target_company.archived_at is not null then
    raise exception 'Active target company not found';
  end if;
  if source_company.updated_at <> p_source_expected_updated_at
     or target_company.updated_at <> p_target_expected_updated_at then
    raise exception 'Company changed after merge review. Reload both records.';
  end if;

  if public.normalize_company_registration(source_company.trade_license_no) is not null
     and public.normalize_company_registration(target_company.trade_license_no) is not null
     and public.normalize_company_registration(source_company.trade_license_no)
       <> public.normalize_company_registration(target_company.trade_license_no) then
    raise exception 'Companies have conflicting trade licence numbers';
  end if;
  if public.normalize_company_registration(source_company.trn) is not null
     and public.normalize_company_registration(target_company.trn) is not null
     and public.normalize_company_registration(source_company.trn)
       <> public.normalize_company_registration(target_company.trn) then
    raise exception 'Companies have conflicting tax registration numbers';
  end if;

  if exists (
    select 1
    from public.corporate_portal_members source_member
    join public.corporate_portal_members target_member
      on target_member.user_id = source_member.user_id
     and target_member.corporate_account_id = p_target_company_id
    where source_member.corporate_account_id = p_source_company_id
  ) then
    raise exception 'A portal user belongs to both companies. Resolve that membership before merging.';
  end if;

  update public.bookings
  set corporate_account_id = p_target_company_id, updated_at = now()
  where corporate_account_id = p_source_company_id;
  get diagnostics moved_bookings = row_count;

  update public.corporate_contacts
  set corporate_account_id = p_target_company_id, updated_at = now()
  where corporate_account_id = p_source_company_id;
  get diagnostics moved_contacts = row_count;

  update public.corporate_portal_members
  set corporate_account_id = p_target_company_id, updated_at = now()
  where corporate_account_id = p_source_company_id;
  get diagnostics moved_members = row_count;

  update public.payments
  set corporate_account_id = p_target_company_id, updated_at = now()
  where corporate_account_id = p_source_company_id;
  get diagnostics moved_payments = row_count;

  update public.corporate_accounts
  set trade_license_no = coalesce(target_company.trade_license_no, source_company.trade_license_no),
      trn = coalesce(target_company.trn, source_company.trn),
      billing_email = coalesce(target_company.billing_email, source_company.billing_email),
      accounts_email = coalesce(target_company.accounts_email, source_company.accounts_email),
      phone = coalesce(target_company.phone, source_company.phone),
      address = coalesce(target_company.address, source_company.address),
      notes = trim(both from concat_ws(
        E'\n',
        nullif(target_company.notes, ''),
        case when nullif(source_company.notes, '') is not null
          then 'Merged company note: ' || source_company.notes end
      )),
      updated_at = now()
  where id = p_target_company_id;

  update public.corporate_accounts
  set status = 'inactive',
      archived_at = now(),
      notes = trim(both from concat_ws(
        E'\n',
        nullif(source_company.notes, ''),
        'Merged into company ' || p_target_company_id::text || ': ' || trim(p_reason)
      )),
      updated_at = now()
  where id = p_source_company_id;

  insert into public.audit_events (
    actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    auth.uid(),
    'company.merged',
    'corporate_account',
    p_target_company_id,
    jsonb_build_object(
      'source_company_id', p_source_company_id,
      'target_company_id', p_target_company_id,
      'reason', trim(p_reason),
      'moved_bookings', moved_bookings,
      'moved_contacts', moved_contacts,
      'moved_portal_members', moved_members,
      'moved_payments', moved_payments
    )
  );

  return jsonb_build_object(
    'ok', true,
    'source_company_id', p_source_company_id,
    'target_company_id', p_target_company_id,
    'moved_bookings', moved_bookings,
    'moved_contacts', moved_contacts,
    'moved_portal_members', moved_members,
    'moved_payments', moved_payments
  );
end;
$function$;

revoke execute on function public.merge_company_records(
  uuid,uuid,timestamptz,timestamptz,text
) from public, anon;
grant execute on function public.merge_company_records(
  uuid,uuid,timestamptz,timestamptz,text
) to authenticated, service_role;
