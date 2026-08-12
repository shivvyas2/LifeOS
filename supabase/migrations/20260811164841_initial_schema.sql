-- Life OS initial schema.
--
-- Mirrors the SwiftData models in LifeOSKit/Sources/Persistence. The local
-- store is the source of truth for the UI; this is the sync target, so every
-- table carries the ownership column and the timestamps a pull needs.
--
-- Two rules govern this file:
--
--   1. Every metric column is nullable. A missing value and a zero must never
--      be representable as the same thing: in a health app a false zero is
--      worse than a blank. Only keys, ownership and timestamps are NOT NULL.
--
--   2. RLS is enabled on every table, without exception, and every policy
--      scopes to auth.uid(). This is what makes shipping the anon key in the
--      app safe.

-- Sets updated_at on write, so a client can never advance it past the server's
-- clock and win a conflict it should have lost.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- One row per calendar day, the join key for the entire app. HealthKit and
-- Whoop are both writers; the UI and the coach are readers.
create table public.daily_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- A calendar day, never a timestamp. `date` rather than `timestamptz` so a
  -- device in another timezone cannot silently write to the adjacent day.
  date date not null,

  weight_kg double precision,
  steps integer,
  active_energy_kcal double precision,
  exercise_minutes integer,
  sleep_minutes integer,
  water_ml double precision,
  resting_hr double precision,
  hrv_ms double precision,

  whoop_recovery_pct double precision,
  whoop_day_strain double precision,
  whoop_sleep_performance_pct double precision,

  updated_at timestamptz not null default now(),
  synced_at timestamptz,

  -- The local model is #Unique on date alone; here it is per user, because the
  -- same day belongs to a different row for a different account.
  unique (user_id, date)
);

-- Source records roll *up* into daily_metrics, which is derived state and
-- always safe to recompute from these.
create table public.workout_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- HealthKit's UUID or Whoop's activity id. Deduplicates re-ingestion.
  external_id text not null,
  started_at timestamptz not null,
  duration_minutes integer not null,
  activity_name text not null,
  energy_kcal double precision,

  updated_at timestamptz not null default now(),

  unique (user_id, external_id)
);

create table public.sleep_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  external_id text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,

  -- The day this sleep is attributed to: the morning you woke up. Stored
  -- rather than derived, because the attribution rule lives in the client and
  -- must not silently change meaning for rows already written.
  attributed_date date not null,

  updated_at timestamptz not null default now(),

  unique (user_id, external_id),
  constraint sleep_records_ends_after_start check (ended_at > started_at)
);

-- Unprocessed Whoop API payloads, retained so re-derivation never requires
-- re-fetching. Whoop rate-limits, and a derivation bug found six months from
-- now must be fixable without asking for the data again.
create table public.whoop_raw (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- 'recovery' | 'sleep' | 'workout' | 'cycle' is Whoop's collection name. Not
  -- an enum: a new collection should land as data, not as a failed insert.
  kind text not null,
  external_id text not null,
  payload jsonb not null,

  received_at timestamptz not null default now(),

  unique (user_id, kind, external_id)
);

-- One row per user per sync scope. Holds the cursor a pull resumes from.
create table public.sync_state (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- 'healthkit' | 'whoop' tells which ingestion this cursor belongs to.
  scope text not null,

  last_synced_at timestamptz,
  -- Opaque to the server: Whoop's next-page token, or a HealthKit anchor.
  cursor text,
  last_error text,

  updated_at timestamptz not null default now(),

  primary key (user_id, scope)
);


-- Indexes for the two access patterns the app actually has: "the last N days
-- for this user" and "everything changed since my last pull".
create index daily_metrics_user_date_idx on public.daily_metrics (user_id, date desc);
create index daily_metrics_user_updated_idx on public.daily_metrics (user_id, updated_at);
create index workout_records_user_started_idx on public.workout_records (user_id, started_at desc);
create index sleep_records_user_attributed_idx on public.sleep_records (user_id, attributed_date desc);
create index whoop_raw_user_received_idx on public.whoop_raw (user_id, received_at desc);


create trigger daily_metrics_touch before update on public.daily_metrics
  for each row execute function public.touch_updated_at();
create trigger workout_records_touch before update on public.workout_records
  for each row execute function public.touch_updated_at();
create trigger sleep_records_touch before update on public.sleep_records
  for each row execute function public.touch_updated_at();
create trigger sync_state_touch before update on public.sync_state
  for each row execute function public.touch_updated_at();


-- RLS. Enabled on every table, without exception.
--
-- Policies are split per operation rather than written as `for all`, so that
-- the WITH CHECK on insert and update is explicit: a client cannot write a row
-- owned by someone else even by supplying a forged user_id.
alter table public.daily_metrics enable row level security;
alter table public.workout_records enable row level security;
alter table public.sleep_records enable row level security;
alter table public.whoop_raw enable row level security;
alter table public.sync_state enable row level security;

create policy "own rows readable" on public.daily_metrics
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows insertable" on public.daily_metrics
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows updatable" on public.daily_metrics
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "own rows deletable" on public.daily_metrics
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy "own rows readable" on public.workout_records
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows insertable" on public.workout_records
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows updatable" on public.workout_records
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "own rows deletable" on public.workout_records
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy "own rows readable" on public.sleep_records
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows insertable" on public.sleep_records
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows updatable" on public.sleep_records
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "own rows deletable" on public.sleep_records
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy "own rows readable" on public.whoop_raw
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows insertable" on public.whoop_raw
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows updatable" on public.whoop_raw
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "own rows deletable" on public.whoop_raw
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy "own rows readable" on public.sync_state
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own rows insertable" on public.sync_state
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own rows updatable" on public.sync_state
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "own rows deletable" on public.sync_state
  for delete to authenticated using ((select auth.uid()) = user_id);
