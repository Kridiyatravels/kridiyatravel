-- Refund RPCs use these intermediate states before a payment becomes refunded.
-- Keep the table constraint aligned with the implemented approval workflow.
alter table public.payments
  drop constraint if exists payments_status_check;

alter table public.payments
  add constraint payments_status_check
  check (
    status = any (
      array[
        'draft'::text,
        'pending'::text,
        'proof_received'::text,
        'received'::text,
        'failed'::text,
        'cancelled'::text,
        'refund_pending'::text,
        'refund_approved'::text,
        'refunded'::text
      ]
    )
  );
