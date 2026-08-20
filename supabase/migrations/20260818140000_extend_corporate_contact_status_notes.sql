-- Extend corporate contact editing to include active status and internal notes.
-- Drop the prior signature first so PostgREST never sees overloaded RPCs.

drop function if exists public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, timestamptz
);

create or replace function public.update_operations_corporate_contact(
  p_corporate_contact_id uuid,
  p_full_name text,
  p_job_title text,
  p_email text,
  p_phone text,
  p_whatsapp text,
  p_is_authorized_contact boolean,
  p_is_accounts_contact boolean,
  p_active boolean,
  p_notes text,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_before public.corporate_contacts%rowtype;
  v_after public.corporate_contacts%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not public.has_staff_permission('edit_corporates') then
    raise exception 'Permission denied';
  end if;

  if p_corporate_contact_id is null then
    raise exception 'Corporate contact is required';
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected corporate contact version is required';
  end if;

  if char_length(trim(coalesce(p_full_name, ''))) not between 2 and 160 then
    raise exception 'Contact name must be between 2 and 160 characters';
  end if;

  if nullif(trim(coalesce(p_email, '')), '') is not null
     and char_length(trim(p_email)) > 320 then
    raise exception 'Email must not exceed 320 characters';
  end if;

  if nullif(trim(coalesce(p_phone, '')), '') is not null
     and char_length(trim(p_phone)) > 40 then
    raise exception 'Phone must not exceed 40 characters';
  end if;

  if nullif(trim(coalesce(p_whatsapp, '')), '') is not null
     and char_length(trim(p_whatsapp)) > 40 then
    raise exception 'WhatsApp must not exceed 40 characters';
  end if;

  if p_is_authorized_contact is null or p_is_accounts_contact is null then
    raise exception 'Corporate contact role flags are required';
  end if;

  if p_active is null then
    raise exception 'Corporate contact status is required';
  end if;

  select cc.*
  into v_before
  from public.corporate_contacts cc
  where cc.id = p_corporate_contact_id;

  if not found then
    raise exception 'Corporate contact not found';
  end if;

  update public.corporate_contacts cc
  set
    full_name = trim(p_full_name),
    job_title = nullif(trim(coalesce(p_job_title, '')), ''),
    email = nullif(lower(trim(coalesce(p_email, ''))), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    whatsapp = nullif(trim(coalesce(p_whatsapp, '')), ''),
    is_authorized_contact = p_is_authorized_contact,
    is_accounts_contact = p_is_accounts_contact,
    active = p_active,
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    updated_at = clock_timestamp()
  where cc.id = p_corporate_contact_id
    and cc.updated_at = p_expected_updated_at
  returning cc.* into v_after;

  if not found then
    raise exception 'Corporate contact changed after this page was loaded. Reload and review the latest values.';
  end if;

  -- Corporate contacts are mirrored into customers when created. Keep the linked
  -- customer identity fields synchronized so bookings do not retain stale details.
  if v_after.customer_id is not null then
    update public.customers c
    set
      full_name = v_after.full_name,
      email = v_after.email,
      phone = v_after.phone,
      whatsapp = v_after.whatsapp,
      updated_at = v_after.updated_at
    where c.id = v_after.customer_id
      and c.customer_type = 'corporate_contact'
      and c.archived_at is null;
  end if;

  insert into public.audit_events (
    actor_user_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor,
    'corporate_contact.details_updated',
    'corporate_contact',
    v_after.id,
    jsonb_build_object(
      'corporate_account_id', v_after.corporate_account_id,
      'linked_customer_id', v_after.customer_id,
      'before', to_jsonb(v_before),
      'after', to_jsonb(v_after)
    )
  );

  return v_after.updated_at;
end;
$function$;

revoke execute on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, boolean, text, timestamptz
) from public, anon;

grant execute on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, boolean, text, timestamptz
) to authenticated, service_role;

comment on function public.update_operations_corporate_contact(
  uuid, text, text, text, text, text, boolean, boolean, boolean, text, timestamptz
) is 'Permission-gated corporate contact detail, role, active-status, and notes update with optimistic locking, linked-customer synchronization, and audit logging.';

notify pgrst, 'reload schema';
