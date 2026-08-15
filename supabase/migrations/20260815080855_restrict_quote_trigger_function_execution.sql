-- Trigger functions are invoked by PostgreSQL and must not be callable through
-- the exposed API roles.
revoke execute on function public.protect_quote_customer_update()
  from public, anon, authenticated;
revoke execute on function public.sync_quote_response_lifecycle()
  from public, anon, authenticated;
