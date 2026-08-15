create or replace function public.protect_quote_customer_update()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if public.is_staff() then return new; end if;
  if pg_trigger_depth()>1 then return new; end if;
  if coalesce(current_setting('kridiya.quote_decision_rpc',true),'off')<>'on' then raise exception 'Use the secured quote decision service'; end if;
  if old.status<>'sent' or new.status not in ('accepted','declined') then raise exception 'Quotes can only be accepted or declined while status is sent'; end if;
  if (to_jsonb(new)-array['status','responded_at','updated_at','quote_version']) is distinct from (to_jsonb(old)-array['status','responded_at','updated_at','quote_version']) then raise exception 'Customers may only update quote status'; end if;
  new.responded_at:=now(); return new;
end $$;

revoke execute on function public.protect_quote_customer_update() from public,anon,authenticated;
grant execute on function public.protect_quote_customer_update() to service_role;
