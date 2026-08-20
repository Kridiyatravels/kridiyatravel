-- PostgreSQL cannot change a TABLE-returning function's OUT row type with
-- CREATE OR REPLACE. Production's captured function snapshot replaced both
-- signatures, so a fresh rebuild must remove the earlier shapes first.

drop function if exists public.list_operations_bookings(integer);
drop function if exists public.list_operations_payments(integer);
