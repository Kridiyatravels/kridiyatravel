create or replace function public.keep_customer_payment_proof_pending()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if new.proof_source='customer' and old.status='pending' and new.status='proof_received' then
    new.status:='pending';
    new.received_at:=null;
  end if;
  return new;
end $$;

drop trigger if exists payments_keep_customer_proof_pending on public.payments;
create trigger payments_keep_customer_proof_pending before update on public.payments
for each row execute function public.keep_customer_payment_proof_pending();

revoke execute on function public.keep_customer_payment_proof_pending() from public,anon,authenticated;
grant execute on function public.keep_customer_payment_proof_pending() to service_role;

comment on function public.keep_customer_payment_proof_pending() is 'Prevents unverified customer-uploaded proof from being counted as cleared payment money.';
