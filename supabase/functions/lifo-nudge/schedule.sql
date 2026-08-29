-- Hourly schedule for lifo-nudge. NOT a migration, and deliberately so.
--
-- It needs two things a migration cannot carry: the project's own function URL,
-- which differs per environment, and the service role key, which must never be
-- committed. Run this once per project, from the SQL editor, after storing the
-- key in Vault.
--
-- Hourly rather than daily because the send hour is LOCAL. Every run selects
-- only the users whose own clock has just reached 8am, so a single daily run
-- would serve one timezone and miss every other.

-- 1. Extensions.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2. The key, in Vault rather than in this file.
--    select vault.create_secret('<service-role-key>', 'lifo_nudge_key');
--    select vault.create_secret('https://<ref>.supabase.co', 'lifo_project_url');

-- 3. The schedule. At minute zero of every hour.
select cron.schedule(
  'lifo-nudge-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'lifo_project_url')
           || '/functions/v1/lifo-nudge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'lifo_nudge_key')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);

-- To inspect or remove:
--   select * from cron.job where jobname = 'lifo-nudge-hourly';
--   select * from cron.job_run_details order by start_time desc limit 20;
--   select cron.unschedule('lifo-nudge-hourly');
