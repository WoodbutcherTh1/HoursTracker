-- Live Activity push updates (v1.12): the Dynamic Island/Lock Screen banner was
-- going stale for hours in the background because the app's only refresh
-- mechanism was an in-process 60s loop that freezes the moment iOS suspends the
-- app. This adds a server-driven path: the app forwards its ActivityKit push
-- token and its own already-computed ContentState (no business logic duplicated
-- server-side); a 60s pg_cron tick re-delivers that same state via APNs so
-- SpringBoard keeps recompositing the Live Activity, and the client's own
-- `Text(timerInterval:)` keeps doing the actual visual ticking.
--
-- RLS stays enabled with NO policies: only the `live-activity-push` Edge
-- Function (service role) and the cron job touch this table.

create table if not exists public.live_activity_tokens (
  device_id uuid primary key references public.devices (id) on delete cascade,
  push_token text not null,
  apns_env text not null default 'production' check (apns_env in ('sandbox', 'production')),
  -- The exact ContentState payload the app last computed for this activity —
  -- re-sent as-is by the cron tick, never recomputed server-side. Starts
  -- empty: the push token and the first real state can arrive as two
  -- separate calls (token observation vs. the regular update loop), and the
  -- tick action skips any row that's still empty.
  content_state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.live_activity_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- Scheduled delivery. pg_cron's minimum granularity is one minute, which is
-- exactly the 60s cadence wanted here.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- The tick action is authenticated by a shared secret (not a user session, not
-- the publishable key) read from this Postgres setting rather than embedded in
-- the migration. Run this once by hand after deploying the Edge Function,
-- using the SAME value as the `CRON_SECRET` function secret
-- (`supabase secrets set CRON_SECRET=...`) — never commit the real value:
--
--   alter database postgres set app.settings.cron_secret = '<same value as CRON_SECRET>';
--
-- Until that's set, current_setting(...) below returns null, the header won't
-- match, and the cron tick is a harmless no-op (the function just 401s it).
select
  cron.schedule(
    'live-activity-push-tick',
    '* * * * *',
    $$
    select net.http_post(
      url := 'https://rocjprrvrvmtisxnvopg.supabase.co/functions/v1/live-activity-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', current_setting('app.settings.cron_secret', true)
      ),
      body := jsonb_build_object('action', 'tick')
    );
    $$
  )
where not exists (
  select 1 from cron.job where jobname = 'live-activity-push-tick'
);
