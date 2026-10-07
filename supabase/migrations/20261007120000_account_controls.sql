-- Account controls: deletion scheduled 30 days ahead, carried out by a daily
-- job, and a record of deleted ids that phones ask about before wiping what
-- they kept. Nothing here holds content.

alter table public.profiles add column if not exists deletion_scheduled_for timestamptz;

create table if not exists public.deleted_accounts (
  user_id uuid primary key,
  deleted_at timestamptz not null default now()
);
-- No policies: only the functions, with the service role, read or write it.
alter table public.deleted_accounts enable row level security;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Reads the project URL and the purge secret from Vault, so neither is in
-- the migration. The owner adds both secrets once (see the spec's steps).
select cron.schedule(
  'account-purge-daily',
  '0 3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/account-purge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
