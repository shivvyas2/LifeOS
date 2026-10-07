# Clear a conversation, clear data, delete the account

Decided 2026-10-07 with the owner, who asked to clear one account's
conversations and then for these to be things anyone can do themselves:
"add that too on the coach screen as well as in settings add an option to
delete the account as well as clear data". Account deletion is item 7 of the
privacy plan, and Apple requires it in apps that let people sign up.

Decisions, in the order they were made:

- **Clear data lets the person pick what to clear**, phone and server, and
  keeps the account.
- **Deleting the account takes 30 days and can be undone** by signing back
  in before the date.
- **At the request the phone signs out and keeps that account's local data**
  until the deletion goes through, so keeping the account brings back
  health and money history too, which only ever lived on the phone. After
  the date the app wipes it the next time it opens.
- **Groups a deleted account owns pass to their longest-standing member**;
  a group with no one else is deleted.

Everything follows the rules already set: paper, ink, hairlines, quiet ink,
the accent only for today and anything live, every button
`.editorial(role)`, fonts only from `LifeOSType` and `Editorial`, and the
operator never reads the content being deleted (functions log counts, never
rows).

## 1. Clear the coach's conversation

The coach's top-bar menu gains `Clear conversation`. A confirmation dialog,
`Clear this conversation? LIFO forgets it on this phone.`, with `Clear`
(destructive) and `Cancel`. It deletes every `ChatMessage` whose
`conversationID` is the coach's (`coach.conversationID` in the account's
defaults), writes a new conversation ID, and empties the screen. The
calendar assistant's conversations, in the same store, are untouched.

`ChatStore.deleteConversation(_ id: UUID)` is the tested rule in
`Persistence`.

## 2. Clear data

`Settings › Your data › Clear data…` opens a sheet titled `Clear data` with
one row per category, a checkbox each, and a quiet line saying where it
lives:

| Category | On this phone | On the server |
|---|---|---|
| Notes and journal | pages, folders and the task index | `note_documents`, `note_folders` |
| Habits and goals | plan entries and their ticks | nothing |
| Health history | metrics, workouts, sleep, Whoop and Fitbit samples | old copies in `daily_metrics`, `sleep_records`, `workout_records`, `whoop_raw` |
| Money history | transactions and budgets | nothing; the bank connection stays (Disconnect is its own button) |
| AI chats | the coach's and the assistant's conversations | nothing (the daily usage count stays, it holds no text) |
| Messages | nothing | direct messages you sent or received; group messages you sent |

Under Messages: `Clearing a conversation clears it for the other person
too: it is one message, not two copies.`

`Clear selected…` (`.editorial(.destructive)`, disabled with nothing
ticked) asks for `CLEAR` typed into a field, then:

1. The server categories go first, through `account-data` (§4), so a phone
   that loses its connection halfway never shows data the server still
   holds as gone. A failure stops here with `Could not clear. Nothing was
   removed from this phone.`
2. The phone categories are deleted through the existing stores
   (`NotesStore`, `PlanStore`, `MetricsStore`, `MoneyStore`, `ChatStore`),
   each gaining a tested `deleteAll()`; Notes also resets its sync cursor so
   the next pull does not wait on a cursor past rows that no longer exist.
3. `Cleared.` and the sheet closes.

## 3. Delete the account

`Settings › Your data › Delete account…` pushes a page:

- What happens: your account and everything stored for it is deleted on
  `<date>`, 30 days from today; until then, signing back in with this
  number lets you keep it; groups you own pass to the member who has been
  in them longest; connected services are disconnected.
- A field: `Type DELETE to confirm`, and `Delete my account`
  (`.editorial(.destructive)`).

On confirm:

1. `account-data` `DELETE` stamps `profiles.deletion_scheduled_for` with now
   + 30 days and returns the date.
2. The GitHub token, which only this phone holds, is revoked through the
   existing `github-token` function and cleared from the Keychain.
3. The phone signs out the way it does today (push deregistered first), and
   adds the account's user ID to `accounts.pendingWipe` in standard
   defaults. The account's store folder, defaults suite and Keychain items
   stay on disk.

### Keeping the account

When a session is restored or a sign-in completes, the shell asks
`account-data` `GET`. With a scheduled date, a full-screen page replaces the
app: `Your account is set to be deleted on <date>.` with `Keep my account`
(`.editorial(.primary)`) and `Sign out` (`.editorial(.quiet)`). Keep sends
`PATCH {"keep": true}`, removes the ID from `accounts.pendingWipe`, and opens
the app as normal; nothing was lost. Nothing else in the app is reachable
while the page is up.

### The daily purge

`account-purge`, run by `pg_cron` at 03:00 UTC with `PURGE_SECRET`, takes
each profile whose `deletion_scheduled_for` has passed and, one account at a
time (a failure is logged by count and the run moves on):

1. **Groups first**, because `social_groups.owner_id` cascades: for each
   group it owns, the accepted member with the earliest `joined_at` becomes
   the owner; a group with no other accepted member is deleted.
2. **Connections**: Plaid items removed at Plaid (`/item/remove`); Whoop and
   Fitbit tokens revoked at the provider; their rows go with the cascade.
3. **Storage**: the account's objects in the avatars bucket.
4. **The login**: `auth.admin.deleteUser`, which cascades every row that
   references `auth.users`.
5. `deleted_accounts (user_id, deleted_at)` gets a row: no name, no number.

### Wiping the phone afterwards

At launch, if `accounts.pendingWipe` is not empty, the app asks
`account-data` `GET ?deleted=<ids>` (an anonymous call with the anon key;
the answer is only which of those IDs are in `deleted_accounts`). For each
deleted one it removes the account's store folder (`UserScope` directory),
its defaults suite, its Keychain items (session, Fitbit, GitHub, Whoop),
and its entry in `AccountStore`, then drops it from the list. Offline, it
tries again next launch.

## 4. The server

One migration:

- `profiles.deletion_scheduled_for timestamptz` (null when not scheduled).
- `deleted_accounts (user_id uuid primary key, deleted_at timestamptz not
  null default now())`, RLS on with no policies (only the functions read
  it).
- The `pg_cron` job calling `account-purge` daily with the secret
  (`net.http_post`), as the nudge job does.

`account-data` (every call but the deleted-IDs check needs a session;
`resolveUser` gates each one and every query is scoped to that ID):

| Call | Does |
|---|---|
| `POST {"clear": ["notes", "health", "messages"]}` | deletes the caller's rows for those server categories; unknown names are 400 |
| `DELETE` | schedules deletion in 30 days (idempotent: a second call keeps the first date); returns the date |
| `PATCH {"keep": true}` | clears the schedule |
| `GET` | `{ "deletion_scheduled_for": <date or null> }` |
| `GET ?deleted=<id,id>` | `{ "deleted": [<ids>] }`, no session needed, at most 20 IDs |

`account-purge` answers only a request carrying `PURGE_SECRET`; anything
else is 401.

Logic lives in `_shared/account.ts` with the handlers taking their
dependencies, as `github.ts` does, so every path is tested without the
network.

## 5. Where it sits in Settings

A `Your data` section above the sign-out button, two rows in the style of
the `At a glance` rows: `Clear data…` and `Delete account…` (the latter's
text in the destructive role's colour). Both push pages; neither is
reachable from anywhere else.

## 6. Verification

- Package tests: `ChatStore.deleteConversation` leaves other conversations;
  each store's `deleteAll()`; the pending-wipe list (add, remove, a wiped
  account's suite and folder gone, using a temporary directory).
- Deno tests for `account.ts`: 401 without a session on every
  session-bound call; clear deletes only the caller's rows per category and
  rejects unknown names; schedule is idempotent; keep clears it; the
  deleted-IDs check caps at 20 and returns only IDs in `deleted_accounts`;
  the purge hands a group to the earliest accepted member, deletes a group
  with no one else, revokes before deleting, continues past one account's
  failure, records the deletion, and refuses a wrong secret.
- UI tests on preview pages: the Clear data sheet enables `Clear selected…`
  only with a box ticked and runs only after `CLEAR`; the coach's `Clear
  conversation` empties the transcript; the keep-or-leave page's `Keep my
  account` dismisses it.
- `scripts/check-typography.sh` reports nothing new; the app and the
  package for macOS build.

## 7. Owner's steps

1. Run the migration (`supabase db push`), deploy `account-data` and
   `account-purge`.
2. `supabase secrets set PURGE_SECRET=<random>` and the same value in the
   cron job's header (the migration reads it from a Vault secret named
   `purge_secret`).
3. Enable the `pg_cron` and `pg_net` extensions in the dashboard if they are
   not on.

## Out of scope

- Exporting data before deleting.
- Removing other people's messages in a group, or other people's copies of
  anything.
- A web form or email confirmation for deletion.
- Shortening or lengthening the 30 days per account.
