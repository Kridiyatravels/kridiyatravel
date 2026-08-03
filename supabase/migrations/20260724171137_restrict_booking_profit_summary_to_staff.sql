-- Profit data must never be readable by anonymous website visitors.
-- Only authenticated staff (via the admin app) may call this function.
REVOKE EXECUTE ON FUNCTION public.booking_profit_summary() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.booking_profit_summary() TO authenticated;
