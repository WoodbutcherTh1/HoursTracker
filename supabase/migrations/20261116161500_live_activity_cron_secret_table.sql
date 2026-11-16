-- Fixes the previous migration's approach: `alter database postgres set
-- app.settings.cron_secret = '...'` is not permitted on managed Supabase
-- Postgres (ERROR 42501, permission denied to set a custom database-level
-- parameter — that requires superuser, which the `postgres` role doesn't have
-- here). A one-row table does the same job without needing any special grant:
-- pg_cron jobs scheduled via `cron.schedule()` run as the scheduling role
-- (`postgres`, confirmed via `select username from cron.job`), which owns
-- this table and therefore bypasses its RLS automatically — no policy, no
-- SECURITY DEFINER wrapper needed.
--
-- The secret value itself is still never committed: it's set once by hand
-- (see the deployment notes) via `insert into public.app_secrets ...`.

create table if not exists public.app_secrets (
  name text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'live-activity-push-tick'),
  command := $$
    select net.http_post(
      url := 'https://rocjprrvrvmtisxnvopg.supabase.co/functions/v1/live-activity-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select value from public.app_secrets where name = 'cron_secret')
      ),
      body := jsonb_build_object('action', 'tick')
    );
  $$
)
where exists (select 1 from cron.job where jobname = 'live-activity-push-tick');
