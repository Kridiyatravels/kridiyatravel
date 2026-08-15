-- Customers may change only the response state. Comparing the remaining row
-- payload keeps future quote columns protected automatically.
create or replace function public.protect_quote_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if public.is_staff() then
    return new;
  end if;

  -- Internal updates made by the response lifecycle trigger (for example,
  -- expiring competing options) run at a deeper trigger level.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if old.status <> 'sent' or new.status not in ('accepted', 'declined') then
    raise exception 'Quotes can only be accepted or declined while status is sent';
  end if;

  if (to_jsonb(new) - array['status', 'responded_at', 'updated_at'])
     is distinct from
     (to_jsonb(old) - array['status', 'responded_at', 'updated_at']) then
    raise exception 'Customers may only update quote status';
  end if;

  new.responded_at := now();
  return new;
end;
$function$;

create or replace function public.sync_quote_response_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  linked_enquiry_id uuid := new.enquiry_id;
begin
  if old.status = 'sent' and new.status = 'accepted' then
    update public.quotes q
    set status = 'expired'
    where q.id <> new.id
      and q.status = 'sent'
      and (
        (new.booking_id is not null and q.booking_id = new.booking_id)
        or (linked_enquiry_id is not null and q.enquiry_id = linked_enquiry_id)
      );

    if linked_enquiry_id is not null then
      update public.enquiries
      set status = 'payment_pending',
          updated_at = now()
      where id = linked_enquiry_id
        and status in ('received', 'checking_availability', 'quote_sent');
    end if;

    update public.bookings b
    set status = 'payment_pending',
        selling_price = new.price_amount,
        amount = new.price_amount,
        currency = new.currency,
        updated_at = now()
    where b.archived_at is null
      and b.status in ('enquiry', 'quote_sent', 'payment_pending')
      and (
        b.id = new.booking_id
        or (linked_enquiry_id is not null and b.enquiry_id = linked_enquiry_id)
      );

    insert into public.audit_events (
      actor_user_id, event_type, entity_type, entity_id, metadata
    ) values (
      auth.uid(),
      'quote.accepted',
      'quote',
      new.id,
      jsonb_build_object(
        'enquiry_id', linked_enquiry_id,
        'booking_id', new.booking_id,
        'price_amount', new.price_amount,
        'currency', new.currency
      )
    );
  elsif old.status = 'sent' and new.status = 'declined' then
    insert into public.audit_events (
      actor_user_id, event_type, entity_type, entity_id, metadata
    ) values (
      auth.uid(),
      'quote.declined',
      'quote',
      new.id,
      jsonb_build_object(
        'enquiry_id', linked_enquiry_id,
        'booking_id', new.booking_id
      )
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists quotes_sync_response_lifecycle on public.quotes;
create trigger quotes_sync_response_lifecycle
after update of status on public.quotes
for each row
when (old.status is distinct from new.status)
execute function public.sync_quote_response_lifecycle();

revoke execute on function public.protect_quote_customer_update()
  from public, anon, authenticated;
revoke execute on function public.sync_quote_response_lifecycle()
  from public, anon, authenticated;
