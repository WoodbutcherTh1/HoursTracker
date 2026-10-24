-- Support chat: who is writing, and reply notifications.
--
-- The base support tables (support_threads, support_messages,
-- support_auto_replies, app_config) were created directly on the live project
-- when the chat shipped; the `create table if not exists` blocks below only
-- record them in the repo and are no-ops where they already exist. The
-- `alter table ... add column if not exists` statements are the real change.
--
-- RLS stays enabled with NO policies: only the Edge Functions `support-chat`
-- (users) and `support-admin` (admins) touch these tables, with the service role.

create table if not exists public.support_threads (
  id uuid primary key default gen_random_uuid(),
  device_id text not null unique,
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  unread_admin boolean not null default true,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);
alter table public.support_threads enable row level security;

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads (id),
  sender text not null check (sender in ('user', 'admin', 'auto')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.support_messages enable row level security;

-- Who the conversation is with. `user_id` / `user_email` come from the signed-in
-- session token on the server (never from the request body); they stay null for
-- an install with no account. The device fields are what the app reports.
alter table public.support_threads
  add column if not exists user_id uuid references auth.users (id) on delete set null,
  add column if not exists user_email text,
  add column if not exists device_model text,
  add column if not exists os_version text,
  add column if not exists app_version text,
  add column if not exists build text,
  add column if not exists locale text,
  add column if not exists language text,
  -- True while an admin reply is waiting for the user to open the chat.
  add column if not exists unread_user boolean not null default false,
  add column if not exists last_admin_reply_at timestamptz;

-- The same facts frozen on each user message, so the owner still sees who wrote
-- it after the user signs in/out or updates the app.
alter table public.support_messages
  add column if not exists context jsonb;

create index if not exists support_threads_user_idx on public.support_threads (user_id);
create index if not exists support_threads_unread_user_idx
  on public.support_threads (device_id) where unread_user;

-- Account deletion removes the account's link and email from the inbox but keeps
-- the conversation text the owner may still need. (user_id is already
-- `on delete set null`; this clears the email copy.)
create or replace function public.support_forget_user(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.support_threads set user_email = null, user_id = null where user_id = p_user_id;
$$;
revoke all on function public.support_forget_user(uuid) from public, anon, authenticated;
grant execute on function public.support_forget_user(uuid) to service_role;
