create index customer_support_requests_customer_record_idx on public.customer_support_requests(customer_id) where customer_id is not null;
create index customer_support_requests_assigned_idx on public.customer_support_requests(assigned_to) where assigned_to is not null;
create index customer_support_requests_task_idx on public.customer_support_requests(task_id) where task_id is not null;
