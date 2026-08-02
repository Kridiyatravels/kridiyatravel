begin;

create table if not exists public.meta_conversion_requests (
  id bigint generated always as identity primary key,
  ip_hash text not null check (char_length(ip_hash) = 64),
  event_id text not null check (char_length(event_id) between 8 and 128),
  created_at timestamptz not null default now(),
  unique (event_id)
);
create index if not exists meta_conversion_requests_ip_time_idx
  on public.meta_conversion_requests (ip_hash, created_at desc);
alter table public.meta_conversion_requests enable row level security;
revoke all on public.meta_conversion_requests from public, anon, authenticated;
grant select, insert, delete on public.meta_conversion_requests to service_role;

create or replace function public.admit_meta_conversion(p_ip_hash text, p_event_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.meta_conversion_requests
      where ip_hash = p_ip_hash and created_at >= now() - interval '15 minutes') >= 30 then
    return 'rate_limited';
  end if;
  begin
    insert into public.meta_conversion_requests (ip_hash, event_id) values (p_ip_hash, p_event_id);
  exception when unique_violation then
    return 'duplicate';
  end;
  return 'allowed';
end;
$$;
revoke execute on function public.admit_meta_conversion(text, text) from public, anon, authenticated;
grant execute on function public.admit_meta_conversion(text, text) to service_role;

select cron.schedule(
  'cleanup-meta-conversion-requests',
  '43 * * * *',
  $$delete from public.meta_conversion_requests where created_at < now() - interval '24 hours'$$
);

commit;
