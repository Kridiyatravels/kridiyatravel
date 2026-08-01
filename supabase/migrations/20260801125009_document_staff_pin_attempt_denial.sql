-- Explicit deny policy documents that browser roles cannot access the
-- staff PIN rate-limit table. Table grants are also revoked separately.

begin;

drop policy if exists "staff_pin_attempts_deny_public"
  on public.staff_pin_login_attempts;
create policy "staff_pin_attempts_deny_public"
on public.staff_pin_login_attempts for all
to anon, authenticated
using (false)
with check (false);

commit;
