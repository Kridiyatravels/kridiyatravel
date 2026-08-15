-- Prevent direct booking edits from claiming document milestones that are not
-- supported by the linked booking_documents rows.
create or replace function public.validate_booking_document_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  has_documents boolean;
  has_visible_documents boolean;
begin
  if new.document_status = old.document_status then
    return new;
  end if;

  select
    exists (
      select 1 from public.booking_documents bd where bd.booking_id = new.id
    ),
    exists (
      select 1 from public.booking_documents bd
      where bd.booking_id = new.id and bd.visible_to_customer = true
    )
  into has_documents, has_visible_documents;

  if new.document_status = 'sent' and not has_visible_documents then
    raise exception 'Document status sent requires a customer-visible document';
  end if;
  if new.document_status = 'generated' and not has_documents then
    raise exception 'Document status generated requires a linked document';
  end if;
  if new.document_status = 'not_started' and has_documents then
    raise exception 'Document status not_started is invalid while documents exist';
  end if;

  return new;
end;
$function$;

drop trigger if exists bookings_validate_document_status on public.bookings;
create trigger bookings_validate_document_status
before update of document_status on public.bookings
for each row execute function public.validate_booking_document_status();

revoke execute on function public.validate_booking_document_status()
  from public, anon, authenticated;
