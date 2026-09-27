-- Owner/admin dashboard (plan Phase 6): device registry for push, admin roles,
-- broadcast announcements, and aggregate-only stats.
--
-- Every table has RLS enabled and NO policies: the app never reads or writes
-- them directly. All access goes through the Edge Functions
-- `register-device` (any install) and `admin-api` (admins only, checked
-- server-side against `public.admins`), which use the service role.

-- ---------------------------------------------------------------------------
-- Devices: one row per app install. `id` is a random install id generated on
-- the device (not the vendor id). `user_id` is set only when the request
-- carried a valid signed-in session — never from the request body.
create table if not exists public.devices (
  id uuid primary key,
  user_id uuid references auth.users (id) on delete set null,
  apns_token text,
  apns_env text not null default 'production' check (apns_env in ('sandbox', 'production')),
  language text not null default 'en' check (language in ('en', 'he', 'ar')),
  app_version text,
  build text,
  os_version text,
  has_watch boolean not null default false,
  has_widget boolean not null default false,
  announcements_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists devices_last_seen_idx on public.devices (last_seen_at);
create index if not exists devices_user_idx on public.devices (user_id);
alter table public.devices enable row level security;

-- ---------------------------------------------------------------------------
-- Admins. Seeded by hand (see the commented step at the bottom).
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'admin' check (role in ('owner', 'admin')),
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

-- ---------------------------------------------------------------------------
-- Announcements. `title`/`body` are {"en": "...", "he": "...", "ar": "..."};
-- each device gets its own language, falling back to English.
-- `target` records how the audience was chosen, e.g.
--   {"kind": "all"} | {"kind": "language", "languages": ["ar"]}
--   {"kind": "version", "versions": ["1.4"]} | {"kind": "users", "emails": [...]}
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users (id) on delete set null,
  title jsonb not null,
  body jsonb not null,
  target jsonb not null default '{"kind": "all"}'::jsonb,
  push boolean not null default true,
  in_app boolean not null default true,
  recipients int not null default 0,
  push_sent int not null default 0,
  push_failed int not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days'
);
alter table public.announcements enable row level security;

-- Which devices an announcement was addressed to, and whether the in-app copy
-- has been shown (so each message appears once).
create table if not exists public.announcement_targets (
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  device_id uuid not null references public.devices (id) on delete cascade,
  seen_at timestamptz,
  primary key (announcement_id, device_id)
);
create index if not exists announcement_targets_device_idx
  on public.announcement_targets (device_id) where seen_at is null;
alter table public.announcement_targets enable row level security;

-- ---------------------------------------------------------------------------
-- Generic fixed-window rate limit for the Edge Functions.
create table if not exists public.request_rate_limit (
  bucket text not null,
  key text not null,
  window_start timestamptz not null default now(),
  count int not null default 0,
  primary key (bucket, key)
);
alter table public.request_rate_limit enable row level security;

create or replace function public.check_rate_limit(
  p_bucket text,
  p_key text,
  p_limit int,
  p_window_minutes int
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count int;
begin
  insert into public.request_rate_limit (bucket, key, window_start, count)
  values (p_bucket, p_key, now(), 1)
  on conflict (bucket, key) do update
    set count = case
                  when request_rate_limit.window_start < now() - make_interval(mins => p_window_minutes)
                  then 1
                  else request_rate_limit.count + 1
                end,
        window_start = case
                  when request_rate_limit.window_start < now() - make_interval(mins => p_window_minutes)
                  then now()
                  else request_rate_limit.window_start
                end
  returning count into current_count;

  return current_count <= p_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- Aggregate stats for the dashboard. Counts only — no per-user rows, wages or
-- shifts ever leave the database through this.
create or replace function public.admin_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'devices', (select count(*) from devices),
    'active1d', (select count(*) from devices where last_seen_at > now() - interval '1 day'),
    'active7d', (select count(*) from devices where last_seen_at > now() - interval '7 days'),
    'active30d', (select count(*) from devices where last_seen_at > now() - interval '30 days'),
    'accounts', (select count(*) from auth.users),
    'pushReachable', (select count(*) from devices
                      where apns_token is not null and announcements_enabled),
    'withWatch', (select count(*) from devices where has_watch),
    'withWidget', (select count(*) from devices where has_widget),
    'byLanguage', coalesce((select jsonb_object_agg(language, n)
                            from (select language, count(*) n from devices group by language) l), '{}'::jsonb),
    'byVersion', coalesce((select jsonb_object_agg(coalesce(app_version, '?'), n)
                           from (select app_version, count(*) n from devices
                                 group by app_version order by count(*) desc limit 12) v), '{}'::jsonb)
  );
$$;

-- Resolves account emails to user ids for "selected users" targeting.
create or replace function public.admin_user_ids_for_emails(p_emails text[])
returns table (user_id uuid, email text)
language sql
stable
security definer
set search_path = public
as $$
  select u.id, u.email::text
  from auth.users u
  where lower(u.email) = any (select lower(e) from unnest(p_emails) e);
$$;

revoke all on function public.check_rate_limit(text, text, int, int) from public, anon, authenticated;
revoke all on function public.admin_stats() from public, anon, authenticated;
revoke all on function public.admin_user_ids_for_emails(text[]) from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, text, int, int) to service_role;
grant execute on function public.admin_stats() to service_role;
grant execute on function public.admin_user_ids_for_emails(text[]) to service_role;

-- ---------------------------------------------------------------------------
-- Owner seed — run once by hand after confirming the owner's account email:
--
--   insert into public.admins (user_id, role)
--   select id, 'owner' from auth.users where lower(email) = lower('<owner email>')
--   on conflict (user_id) do update set role = 'owner';
