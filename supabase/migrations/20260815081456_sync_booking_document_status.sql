-- Derive booking.document_status from actual document visibility while
-- preserving an explicit archived state.
create or replace function public.refresh_booking_document_status(target_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  update public.bookings b
  set document_status = case
        when exists (
          select 1 from public.booking_documents bd
          where bd.booking_id = target_booking_id
            and bd.visible_to_customer = true
        ) then 'sent'
        when exists (
          select 1 from public.booking_documents bd
          where bd.booking_id = target_booking_id
        ) then 'generated'
        else 'not_started'
      end,
      updated_at = now()
  where b.id = target_booking_id
    and b.document_status <> 'archived';
end;
$function$;

create or replace function public.sync_booking_document_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_booking_document_status(old.booking_id);
    return old;
  end if;

  perform public.refresh_booking_document_status(new.booking_id);
  if tg_op = 'UPDATE' and old.booking_id is distinct from new.booking_id then
    perform public.refresh_booking_document_status(old.booking_id);
  end if;
  return new;
end;
$function$;

drop trigger if exists booking_documents_sync_booking_status
  on public.booking_documents;
create trigger booking_documents_sync_booking_status
after insert or update of booking_id, visible_to_customer or delete
on public.booking_documents
for each row execute function public.sync_booking_document_status();

do $repair$
declare
  booking_row record;
begin
  for booking_row in
    select id from public.bookings where document_status <> 'archived'
  loop
    perform public.refresh_booking_document_status(booking_row.id);
  end loop;
end;
$repair$;

revoke execute on function public.refresh_booking_document_status(uuid)
  from public, anon, authenticated;
revoke execute on function public.sync_booking_document_status()
  from public, anon, authenticated;
