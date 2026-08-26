-- One row per user per day: how many tokens LIFO has spent for them.
-- The ledger is the budget guardrail; the cap itself lives in the Edge
-- Function so changing it is a deploy, not a migration.
create table public.lifo_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null default current_date,
  tokens bigint not null default 0,
  primary key (user_id, day)
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner: usage is bookkeeping between the Edge Function
-- and the model provider, and the service role is the only reader.
alter table public.lifo_usage enable row level security;

-- Upsert-and-add in one statement, so two concurrent turns cannot both read
-- the same starting balance and each write their own. Returns the new total
-- so the caller can log it without a second round trip.
create function public.lifo_debit(p_user uuid, p_tokens bigint)
returns bigint
language sql
security definer
set search_path = public
as $$
  insert into lifo_usage (user_id, day, tokens)
  values (p_user, current_date, p_tokens)
  on conflict (user_id, day)
  do update set tokens = lifo_usage.tokens + excluded.tokens
  returning tokens;
$$;

-- Only the service role may spend; definer or not, keep the front door shut.
revoke execute on function public.lifo_debit from public, anon, authenticated;

-- Revoking PUBLIC above strips the default grant. Explicit grant to service_role
-- so the Edge Function can actually call this.
grant execute on function public.lifo_debit(uuid, bigint) to service_role;
