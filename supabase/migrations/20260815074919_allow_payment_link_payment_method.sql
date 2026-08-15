-- Keep the payments contract aligned with the payment method offered by the
-- staff booking-detail form.
alter table public.payments
  drop constraint if exists payments_method_check;

alter table public.payments
  add constraint payments_method_check
  check (
    method = any (
      array[
        'bank_transfer'::text,
        'cash'::text,
        'stripe'::text,
        'tabby'::text,
        'tamara'::text,
        'paypal'::text,
        'card_machine'::text,
        'payment_link'::text,
        'other'::text
      ]
    )
  );
