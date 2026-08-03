-- Allow corporate portal requests to create booking rows.
-- The portal RPC inserts bookings.source = 'corporate_portal', so this value
-- must be accepted by the existing bookings_source_check constraint.

alter table public.bookings
drop constraint if exists bookings_source_check;

alter table public.bookings
add constraint bookings_source_check
check (
  source is null
  or source in (
    'website',
    'main_site',
    'corporate',
    'corporate_site',
    'corporate_portal',
    'admin',
    'staff',
    'whatsapp',
    'email',
    'phone',
    'walk_in',
    'referral',
    'manual',
    'import',
    'other'
  )
);
