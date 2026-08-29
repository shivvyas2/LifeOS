-- Proactive LIFO: where a push goes, what has already been said, and the
-- separate budget a nudge spends from.
--
-- Follows the rules the initial schema set: RLS on every table, every client
-- policy scoped to auth.uid(). The nudge job runs as the service role, which
-- bypasses RLS; the policies here exist for the device, which registers and
-- deregisters its own token and nothing else.

-- ---------------------------------------------------------------------------
-- Where a push goes
-- ---------------------------------------------------------------------------

-- The token is the primary key, not (user_id, token).
--
-- This is the account-switching requirement, expressed as a constraint rather
-- than as client discipline. Commit df18113 let several accounts share one
-- device; a token left registered under account A while the device is showing
-- account B would push A's sleep data onto B's lock screen. With the token as
-- the key, registering under B *replaces* A's row in a single upsert, and the
-- wrong-account push is not merely unlikely, it is unrepresentable.
create table public.device_tokens (
  token text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- 'ios' today. Stated rather than assumed so a second platform lands as
  -- data instead of as a column.
  platform text not null default 'ios',

  -- An IANA name, e.g. 'America/New_York'. The send hour is local, so a row
  -- without a usable zone is a row that never sends: a nudge at the wrong
  -- hour is worse than no nudge.
  timezone text not null,

  updated_at timestamptz not null default now()
);

-- The hourly job selects every token, so this is the index it actually uses.
create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

create policy "own tokens are readable" on public.device_tokens
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "own tokens are writable" on public.device_tokens
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own tokens are updatable" on public.device_tokens
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
-- Signing out deletes the row rather than orphaning it, so this one is load
-- bearing rather than symmetry for its own sake.
create policy "own tokens are deletable" on public.device_tokens
  for delete to authenticated using ((select auth.uid()) = user_id);

create trigger device_tokens_touch before update on public.device_tokens
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- What has already been said
-- ---------------------------------------------------------------------------

-- Structured columns only. No message text is written here, which is what
-- keeps the promise in lifo-agent/index.ts true for the proactive path too.
create table public.nudge_log (
  user_id uuid not null references auth.users on delete cascade,
  -- The user's LOCAL day, supplied by the job. Not current_date: the server
  -- is in UTC and "one per day" has to mean one per the day the person is
  -- actually living in, or a user in Auckland gets two.
  day date not null,
  trigger text not null,
  sent_at timestamptz not null default now(),

  -- One per day, enforced here rather than in logic. This is what makes two
  -- overlapping cron runs safe: the job inserts before it sends, and a second
  -- run that has already been beaten to it conflicts and stops.
  primary key (user_id, day)
);

-- The seven day per-trigger cooldown reads back over this.
create index nudge_log_cooldown_idx on public.nudge_log (user_id, sent_at desc);

-- Deliberately no policies, like lifo_usage. RLS with zero policies denies
-- every client: this is bookkeeping between the job and Apple, and the audit
-- trail for "why did it say that". The service role is the only reader.
alter table public.nudge_log enable row level security;

-- ---------------------------------------------------------------------------
-- The budget a nudge spends from
-- ---------------------------------------------------------------------------

-- lifo_usage gains `kind` in its primary key.
--
-- Without this a heavy chat evening silently eats the next morning's nudge,
-- and someone who spent their budget at 11pm wakes up to nothing. The two
-- allowances are separate because they are spent by different things: chat
-- costs money only for an engaged user, a nudge costs money for every user on
-- every eventful day.
alter table public.lifo_usage
  add column kind text not null default 'chat';

alter table public.lifo_usage drop constraint lifo_usage_pkey;
alter table public.lifo_usage add primary key (user_id, day, kind);

-- Replaced rather than overloaded: the old two-argument signature would still
-- resolve and would debit whichever kind the default happened to be, which is
-- exactly the silent miscounting this migration exists to remove.
drop function if exists public.lifo_debit(uuid, bigint);

create function public.lifo_debit(p_user uuid, p_tokens bigint, p_kind text default 'chat')
returns bigint
language sql
security definer
set search_path = public
as $$
  insert into lifo_usage (user_id, day, kind, tokens)
  values (p_user, current_date, p_kind, p_tokens)
  on conflict (user_id, day, kind)
  do update set tokens = lifo_usage.tokens + excluded.tokens
  returning tokens;
$$;

revoke execute on function public.lifo_debit from public, anon, authenticated;
grant execute on function public.lifo_debit(uuid, bigint, text) to service_role;
