-- Daily schedule for account-purge. NOT a migration, and deliberately so:
-- it needs this project's function URL and the purge secret, which differ per
-- environment and must never be committed. Run once per project from the SQL
-- editor.

-- 1. Extensions.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2. Secrets, in Vault rather than in this file. `lifo_project_url` already
--    exists if the nudge job was set up; create it only if it does not.
--    select vault.create_secret('https://<ref>.supabase.co', 'lifo_project_url');
--    select vault.create_secret('<same value as the PURGE_SECRET function secret>', 'purge_secret');

-- 3. The schedule: 03:00 UTC daily. The timeout lets job_run_details record
--    the function's answer ({"deleted": n, "failed": n}).
select cron.schedule(
  'account-purge-daily',
  '0 3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'lifo_project_url')
           || '/functions/v1/account-purge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);
