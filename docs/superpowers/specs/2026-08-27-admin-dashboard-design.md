# Admin dashboard: see who signed up, and whether their data is syncing

**Date:** 2026-08-27
**Status:** Approved direction; awaiting implementation plan

## What this is

There is currently no way to answer "did that signup work, and is their
health data arriving" without opening the Supabase table editor. This spec
adds a web dashboard that answers it, modelled on the existing
`~/trashee-admin` build, and the one piece of app work it depends on.

The dashboard is a testing instrument first. Its centre of gravity is
`sync_state`, not vanity metrics.

Decisions made with the app's owner:

| Decision | Choice |
|---|---|
| Profile photos | Add Storage upload to the app first, so the dashboard can show them |
| Avatar bucket | Private, read through short-lived signed URLs |
| Dashboard home | New sibling repo at `~/lifeos-admin`, not nested in the Xcode project |
| Palette | LifeOS accent `#F0572E` on bone `#F2F1EE`, replacing Trashee's teal |

## Two sub-projects, in order

**A. Avatar sync.** iOS plus one migration. Gets profile photos off the
device and into Supabase Storage.

**B. `lifeos-admin`.** The Next.js dashboard, which reads what A produces.

B depends on A only for the photo column. Everything else B needs already
exists on the server today.

## What is already observable

Worth stating plainly, because it shaped the scope. `finishProfile` in
`OnboardingViewModel` calls `auth.updateProfile`, which writes first name,
last name, country, birth date, height and gender into `user_metadata` on
`auth.users`. All of it is readable with the service role. Email, phone and
`created_at` sit on the same row.

The photo is the sole exception, and `ProfilePhotoStore` explains why: the
`user_metadata` payload rides inside the JWT on every authenticated request,
so a base64 avatar would be paid for on every call the app makes. It is
written to the app support directory instead, and its own comment names the
consequence: the photo does not follow the account to a second device.

Sub-project A removes that limitation, which is worth doing on its own merits
independent of the dashboard.

## Sub-project A: avatar sync

### A leak this uncovered

`df18113 feat(auth): give every account its own store` isolated the SwiftData
store, the keychain session, sync cursors, Whoop straps and bank connections
per account. It missed the two stores in `ProfilePhotoStore.swift`:
`ProfilePhotoStore` writes to one fixed path, and `ProfileStore` to one
`UserDefaults` key.

So on a device with two accounts, the second sees the first account's face,
name, height, birth date and gender. That is exactly the leak `df18113` set
out to close.

It has to be fixed as part of this work regardless, because everything below
keys by user id. Both stores move into `Integrations` beside
`KeychainAuthSessionStore`, which already does this per-account job and owns
the account key they need.

### Migration

`supabase/migrations/<timestamp>_avatars_bucket.sql`

- Create a **private** bucket `avatars`.
- Four policies on `storage.objects`, all scoped to the owning user, for
  select, insert, update and delete. The scope test is that the first path
  segment equals `auth.uid()::text`.
- Path convention is `{user_id}/avatar.jpg`. Deterministic, so no column
  anywhere needs to record where a photo lives, and no migration is needed
  to find one later.

Cache invalidation uses the object's own `updated_at` from Storage, so
replacing a photo does not serve a stale image from a URL that never
changes.

### Client

`LifeOSKit/Sources/Integrations/SupabaseStorage.swift`, beside
`SupabaseAuth` and following its shape: an actor holding `baseURL`,
`anonKey` and a `URLSession`, with requests built by static functions so
they stay testable without a network.

```
func upload(_ data: Data, accessToken: String) async throws
func signedURL(accessToken: String, expiresIn: Int) async throws -> URL
func download(accessToken: String) async throws -> Data?
```

Signed URLs are minted on demand and never persisted. A persisted signed URL
is a URL that works until it silently does not.

### Wiring

**`finishProfile`** uploads after the existing `updateProfile` call
succeeds. The upload is wrapped so that a Storage failure is logged and
swallowed, exactly as the surrounding profile-write failure already is. The
rule that code encodes must survive this change: the account exists either
way, and nothing at the last step of signup may strand a user who already
has a working account.

**`ProfileEditSheet`** makes the same call on save.

**`ProfilePhotoStore`** keeps its present job as the local cache and gains
`fetchIfMissing(accessToken:)`, called on launch. This is what makes a photo
follow an account onto a second device.

### Tests

`LifeOSKit/Tests/IntegrationsTests/`, against the stub `URLProtocol` pattern
the auth tests already use:

- upload builds the expected request, path and content type
- a failing upload does not throw out of the signup path
- `signedURL` parses the response and returns a usable URL
- `fetchIfMissing` is a no-op when a local photo already exists

## Sub-project B: `lifeos-admin`

### Stack

Ported from `trashee-admin` with its architecture intact: Next.js 16 App
Router, TypeScript, Tailwind 4, Recharts, `@supabase/ssr`. Server components
read through a service-role client in `lib/supabase/admin.ts`. The service
key is server-only and never reaches the browser.

`components/{ui,shell,table,overview}` port across essentially unchanged.
`lib/data/*` is rewritten. The palette is swapped.

### Routes

| Route | Purpose |
|---|---|
| `/` | Signups over time, channel split, users syncing, users erroring |
| `/users` | Every signup: email or phone, channel, name, country, joined, avatar |
| `/users/[id]` | One user: profile fields, photo, sync per scope, recent metrics, workouts, sleep |
| `/sync` | The testing view. Every `sync_state` row, newest first, `last_error` surfaced |
| `/health` | Recent `daily_metrics` across all users, to eyeball whether numbers look sane |

`/sync` is the page this project exists for. `last_error` gets its own
column at full width rather than being truncated into a tooltip, because a
truncated error is an error nobody reads.

### The one real departure from Trashee

Trashee reads a plain `public.users` table. LifeOS has no such table:
`public.profiles` carries only `user_id`, `display_name` and `updated_at`.
Identity lives in `auth.users`.

So `lib/data/users.ts` reads through the **admin auth API**
(`auth.admin.listUsers`), which returns email, phone, `created_at` and the
whole `raw_user_meta_data` blob, then joins to `daily_metrics` and
`sync_state` by `user_id` in a second query. Pagination follows the auth
API's page semantics rather than PostgREST's `range`.

**Channel is derived, never stored.** A populated `phone` means they came
through the phone door, a populated `email` means the email one. There is no
column to read, and `otp_events` cannot help: it stores a hash of the phone
precisely so that a database dump is not a directory of users, which means
it can count attempts but cannot be joined back to a person.

**Search is the cost of this choice.** `auth.admin.listUsers` takes `page`
and `perPage` and nothing else: there is no `ilike`, so the server-side
search Trashee performs on its `users` table is not available. At testing
scale the answer is to filter in the route handler over the fetched page and
leave it there. If the user count ever outgrows that, the fix is a
`security definer` view over `auth.users` exposing only the columns the
dashboard reads, which is a schema change and deliberately not in this
spec.

### Avatars

Server-side, the dashboard mints a signed URL per user with the service role
and passes it to the client as a plain `img` source. Signed URLs are
requested per render rather than cached, so a replaced photo is never stale.

### Theme

Same token structure as `trashee-admin/src/app/globals.css`, values taken
from `LifeOSKit/Sources/DesignSystem/Tokens.swift`:

```css
--color-brand: #f0572e;   /* LifeOSTokens.accent */
--color-surface: #f2f1ee; /* canvas, light */
--color-ink: #141414;     /* primaryText, light */
--color-muted: #737373;   /* secondaryText, light */
--color-card: #ffffff;    /* cardSurface, light */
```

Charts use the six sector colours as the categorical palette: body
`#0F8C87`, activity `#EBAD29`, recovery `#3B82ED`, nutrition `#7D5CEB`,
money `#2E9E5C`, habits `#F06B33`. No green anywhere except the money
sector, where green means money.

### Access

Trashee gates on `users.role = 'admin'`. LifeOS has no roles table and does
not need one for a testing tool. The gate is an allowlist of admin user IDs
in `ADMIN_USER_IDS`, checked in middleware after the Supabase session
resolves. Sign-in reuses the existing email OTP.

Adding a `role` column later is a strictly larger change and buys nothing
until there is a second admin.

### Environment

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (sessions only)
- `SUPABASE_SERVICE_ROLE_KEY` (server-side data access, never exposed)
- `ADMIN_USER_IDS` (comma separated)

## What this concentrates

The dashboard puts real emails, phone numbers, health records and faces
behind a single admin login. That is normal for a testing instrument and the
Trashee pattern already gets the load-bearing part right by keeping the
service role key server-side. This spec carries that over rather than
inventing anything looser, and the avatar bucket is private for the same
reason.

Nothing here weakens the app's own posture: RLS stays on every table, every
policy stays scoped to `auth.uid()`, and the dashboard's reach comes from
the service role rather than from any loosening of those policies.

## Out of scope

- Mutating user data from the dashboard. It reads. Anything destructive
  belongs behind a deliberate later decision, not in a testing tool.
- A roles table.
- Pinterest, mood boards, and anything else from adjacent conversations.
