-- One connected Fitbit account per user.
--
-- The tokens live here rather than in the device Keychain, which is where the
-- Whoop tokens live, and the reason is specific to Fitbit: its refresh tokens
-- rotate and are single use. A new refresh token is returned with every access
-- token, and the old one stops working. Two devices sharing one credential
-- would therefore invalidate each other on every sync, and the user would be
-- signed out by their own second phone.
--
-- A single server-side row with a lock around it is the only arrangement where
-- exactly one writer rotates the token.
create table public.fitbit_connections (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,

  -- Fitbit's own id for the account, so a reconnect to a different Fitbit
  -- account is distinguishable from a refresh of the same one.
  fitbit_user_id text,

  -- SECURITY: stored in plaintext, matching plaid_items. Anyone holding the
  -- service-role key can read every user's health credential. Accepted for a
  -- first release on the same terms, and to be revisited with Supabase Vault
  -- before this carries a second person's data.
  access_token text not null,

  -- The rotating half. Single use: every refresh replaces it.
  refresh_token text not null,

  -- Fitbit access tokens last 8 hours. Stored so the function refreshes on
  -- expiry rather than discovering it through a 401.
  access_expires_at timestamptz not null,

  -- Space-separated, as Fitbit returns them. Kept so the app can tell a
  -- missing collection caused by a declined scope from one caused by a device
  -- that has no such sensor.
  scopes text not null default '',

  -- Set when a refresh is refused with invalid_grant. The credential is dead
  -- and only the user signing in again can replace it, so the card must say
  -- Reconnect rather than retrying forever.
  needs_reauth boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner, which is the intent: the access token must never
-- reach a device. The service role bypasses RLS and is the only reader, from
-- inside an Edge Function that has already resolved the caller.
alter table public.fitbit_connections enable row level security;
