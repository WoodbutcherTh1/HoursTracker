-- Owner dashboard "live now" counts (aggregate only).
--
-- devices.on_shift is a bare yes/no each install reports with its registration
-- (clock in / out re-registers at once). No shift times or pay are stored.
-- A device that hasn't checked in for 16 hours no longer counts as on a shift,
-- so an app that was deleted mid-shift doesn't stay "on shift" forever.

alter table public.devices
  add column if not exists on_shift boolean not null default false;

create or replace function public.admin_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'devices', (select count(*) from devices),
    'activeNow', (select count(*) from devices where last_seen_at > now() - interval '15 minutes'),
    'onShiftNow', (select count(*) from devices
                   where on_shift and last_seen_at > now() - interval '16 hours'),
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

revoke all on function public.admin_stats() from public, anon, authenticated;
grant execute on function public.admin_stats() to service_role;
