-- Account controls: deletion scheduled 30 days ahead, carried out by a daily
-- job (scheduled separately), and a record of deleted ids that phones ask about before wiping what
-- they kept. Nothing here holds content.

alter table public.profiles add column if not exists deletion_scheduled_for timestamptz;

create table if not exists public.deleted_accounts (
  user_id uuid primary key,
  deleted_at timestamptz not null default now()
);
-- No policies: only the functions, with the service role, read or write it.
alter table public.deleted_accounts enable row level security;

-- The daily purge's schedule is not here: it needs this project's function
-- URL and a secret, which differ per environment and must not be committed.
-- See supabase/functions/account-purge/schedule.sql, run once per project,
-- as lifo-nudge's is.
