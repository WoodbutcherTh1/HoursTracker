-- Per-IP rate limit for the submit-feedback Edge Function. HoursTracker has
-- no user accounts, so this is the only abuse control between the public
-- internet and the Telegram Bot API credentials held as function secrets.
create table if not exists public.feedback_rate_limit (
  ip inet primary key,
  window_start timestamptz not null default now(),
  count int not null default 0
);

alter table public.feedback_rate_limit enable row level security;
-- No policies: only the service role (used inside the Edge Function) can
-- read or write this table.

create or replace function public.check_feedback_rate_limit(
  client_ip inet,
  limit_count int,
  window_minutes int
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count int;
begin
  insert into public.feedback_rate_limit (ip, window_start, count)
  values (client_ip, now(), 1)
  on conflict (ip) do update
    set count = case
                  when feedback_rate_limit.window_start < now() - make_interval(mins => window_minutes)
                  then 1
                  else feedback_rate_limit.count + 1
                end,
        window_start = case
                  when feedback_rate_limit.window_start < now() - make_interval(mins => window_minutes)
                  then now()
                  else feedback_rate_limit.window_start
                end
  returning count into current_count;

  return current_count <= limit_count;
end;
$$;

revoke all on function public.check_feedback_rate_limit(inet, int, int) from public;
grant execute on function public.check_feedback_rate_limit(inet, int, int) to service_role;
