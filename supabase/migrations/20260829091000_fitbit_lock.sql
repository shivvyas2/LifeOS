-- Mutual exclusion around the token refresh.
--
-- This exists because Fitbit rotates the refresh token on every use: two
-- devices refreshing at once would each rotate it, and whichever finished
-- second would invalidate the first, signing the user out from their own
-- second phone.
--
-- Deliberately NOT `select ... for update`. A plpgsql function's transaction
-- ends when the function returns, so that lock would be released before the
-- Edge Function ever reaches Fitbit over HTTP, and would protect nothing at
-- all. The exclusion has to outlive a network round trip, so it is a lease
-- held in a column rather than a lock held in a transaction.
--
-- The claim is a single `update ... where`, which Postgres executes atomically:
-- of two concurrent callers exactly one matches the predicate and gets a row
-- back, and the other gets none and knows to wait.

alter table public.fitbit_connections
  add column refresh_lease_until timestamptz;

-- Claims the right to refresh this user's token for `p_lease_seconds`.
--
-- Returns the connection when the caller won the claim, and no row when
-- another sync is mid-refresh. The lease expires on its own, so a function
-- that crashes between claiming and writing does not lock the account out
-- forever: the next sync after the lease lapses simply claims it again.
create or replace function public.claim_fitbit_refresh(
  p_user_id uuid,
  p_lease_seconds int default 30
)
returns public.fitbit_connections
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.fitbit_connections;
begin
  update public.fitbit_connections
  set refresh_lease_until = now() + make_interval(secs => p_lease_seconds)
  where user_id = p_user_id
    and (refresh_lease_until is null or refresh_lease_until < now())
  returning * into claimed;

  return claimed;
end;
$$;

-- Reads the connection without claiming anything, for the common case where
-- the access token is still valid and no refresh is needed.
create or replace function public.read_fitbit_connection(p_user_id uuid)
returns public.fitbit_connections
language sql
security definer
set search_path = public
as $$
  select * from public.fitbit_connections where user_id = p_user_id;
$$;

-- Both are service-role only. They bypass RLS by being security definer, so
-- letting a signed-in client call them directly would hand any user another
-- user's health credential.
revoke all on function public.claim_fitbit_refresh(uuid, int) from public, anon, authenticated;
revoke all on function public.read_fitbit_connection(uuid) from public, anon, authenticated;
