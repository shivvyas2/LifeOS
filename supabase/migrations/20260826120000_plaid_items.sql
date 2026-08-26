-- One connected bank per row. The only server-side state this feature keeps.
--
-- Transactions deliberately do not live here. The Edge Function hands each
-- sync delta straight back to the device, which is the source of truth, so a
-- compromise of this database exposes the credential but not a ledger of
-- where someone shops.
create table public.plaid_items (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,

  -- Plaid's item_id. One per connected institution.
  item_id text not null,

  -- A live, non-expiring credential to a bank account.
  --
  -- SECURITY: stored in plaintext. Anyone holding the service-role key or
  -- direct database access can read every user's bank credential. That is an
  -- accepted trade for a single-user first release and MUST be revisited
  -- before a second person connects an account. The upgrade path is Supabase
  -- Vault, which keeps the secret out of the table and out of backups.
  access_token text not null,

  institution_id text,
  institution_name text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Composite, so a second bank is a second row rather than a schema change.
  primary key (user_id, item_id)
);

-- Deliberately no policies. RLS with zero policies denies every client,
-- including the row's owner, which is the intent: the access token must never
-- reach a device. The service role bypasses RLS and is the only reader, from
-- inside an Edge Function that has already resolved the caller.
alter table public.plaid_items enable row level security;

-- The one access pattern: "this user's connected banks".
create index plaid_items_user_idx on public.plaid_items (user_id);

-- Backstops the Edge Function's check-then-insert duplicate guard, which is
-- otherwise a race: two concurrent exchanges can both pass the lookup before
-- either writes. Postgres treats NULL as distinct from any other NULL for
-- uniqueness purposes, so rows with no institution_id (which is nullable, so
-- this stays possible) are deliberately not constrained by this and can
-- repeat.
alter table public.plaid_items
  add constraint plaid_items_user_institution_key unique (user_id, institution_id);

-- No sync_state row is created for Plaid. The sync cursor lives on the device,
-- because a server-advanced cursor would permanently lose a page of
-- transactions to an app that crashed mid-ingest. See the design spec, 6.1.
