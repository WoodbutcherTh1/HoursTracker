-- Apple refresh tokens: stored right after a native Sign in with Apple, since
-- the one-time authorization code it came from expires in minutes and can
-- only be exchanged once — it is no longer usable by the time an account is
-- deleted. delete-account reads this row to call Apple's /auth/revoke
-- endpoint before removing the account (App Store Review Guideline 5.1.1(v)).
--
-- RLS enabled, no policies: only the service role (apple-token-exchange,
-- delete-account) ever touches this table, same pattern as every other
-- service-role-only table in this project.
create table if not exists public.apple_refresh_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);
alter table public.apple_refresh_tokens enable row level security;
