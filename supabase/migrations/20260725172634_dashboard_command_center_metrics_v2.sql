create or replace function public.staff_dashboard_summary()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'enquiries_open', (select count(*) from public.enquiries where status <> 'closed'),
    'enquiries_today', (select count(*) from public.enquiries where created_at::date = current_date),
    'bookings_open', (select count(*) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'bookings_confirmed_unpaid', (select count(*) from public.bookings where archived_at is null and status in ('confirmed', 'ticketed', 'paid') and payment_status not in ('paid', 'received', 'payment_received', 'completed')),
    'documents_pending', (select count(*) from public.bookings where archived_at is null and document_status in ('not_started', 'pending', 'missing', 'requested')),
    'payments_pending', (select count(*) from public.payments where status in ('pending', 'proof_received')),
    'payment_proofs_received', (select count(*) from public.payments where status = 'proof_received' or proof_storage_path is not null),
    'supplier_payments_pending', (select count(*) from public.supplier_payments where status in ('pending', 'partial')),
    'refunds_pending', (select count(*) from public.payments where status in ('refund_pending', 'refund_approved')),
    'refund_value_pending', (select coalesce(sum(coalesce(refund_amount, amount)), 0) from public.payments where status in ('refund_pending', 'refund_approved')),
    'sales_value_open', (select coalesce(sum(coalesce(selling_price, amount)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'supplier_cost_open', (select coalesce(sum(coalesce(supplier_cost, 0)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'gross_profit_open', (select coalesce(sum(coalesce(selling_price, amount, 0) - coalesce(supplier_cost, 0)), 0) from public.bookings where archived_at is null and status not in ('completed', 'cancelled', 'refunded')),
    'received_value_30d', (select coalesce(sum(amount), 0) from public.payments where status = 'received' and created_at >= now() - interval '30 days'),
    'net_collected_30d', (select coalesce(sum(case when status = 'received' then amount when status = 'refunded' then -coalesce(refund_amount, amount) else 0 end), 0) from public.payments where created_at >= now() - interval '30 days'),
    'tasks_due', (select count(*) from public.tasks_reminders where status = 'open' and due_at <= now()),
    'tasks_overdue', (select count(*) from public.tasks_reminders where status = 'open' and due_at < now()),
    'tasks_today', (select count(*) from public.tasks_reminders where status = 'open' and due_at::date = current_date),
    'documents_generated', (select count(*) from public.documents),
    'recent_activity', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (select event_type, entity_type, entity_id, metadata, created_at from public.audit_events order by created_at desc limit 10) x)
  )
  where public.is_staff();
$$;

revoke execute on function public.staff_dashboard_summary() from public;
revoke execute on function public.staff_dashboard_summary() from anon;
grant execute on function public.staff_dashboard_summary() to authenticated, service_role;
