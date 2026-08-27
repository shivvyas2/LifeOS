# Friends and Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find people, add them as friends, and message them — from the profile screen, on the existing Supabase project, with no third-party chat service.

**Architecture:** Three tables (`profiles`, `friendships`, `messages`) with RLS doing all the authorization; a thin `SocialAPI` in `Integrations` speaking PostgREST with the user's access token; a Friends screen pushed from the profile (search, requests, list) and a chat screen per friend that polls while open. Signed-out users see the sign-in door, not a broken screen.

**Tech Stack:** Supabase (PostgREST + RLS), Swift 6, SwiftUI, Swift Testing. No SDKs — the same hand-rolled REST idiom `SupabaseAuth` established.

**Spec:** This plan is its own spec; user direction: "search profiles and add friends as well as message them", Supabase-native chosen over a chat SDK for cost. Cost ceiling: backend stays ~free at this scale.

## Global Constraints

- All authorization lives in RLS. The client never filters for privacy, only for display; a leaked query must return nothing it should not.
- The anon key + user access token is the only credential the app holds (`SupabaseAuth` idiom, no SDK).
- Message send/read requires an ACCEPTED friendship, enforced in RLS on `messages`.
- Guests (no session) get an explanatory state with the existing sign-in path, never a request that 401s into a blank screen.
- UI follows the house language: `SoftCard`/`GlassPanel` glass, pastel icon bubbles, `CapsuleButton`, eyebrows, `LifeOSType` scale.
- Kit stays macOS-buildable; `SocialAPI` is pure Foundation.
- Polling is gentle: chat refreshes every 5 seconds only while the chat screen is open; friends refresh on appear and after actions.
- Commits conventional, no em dashes, no trailers; branch work in a worktree.

---

### Task 1: The schema and its rules

**Files:**
- Create: `supabase/migrations/20260827130000_friends_and_messages.sql`

**Interfaces:**
- Produces the three tables Task 2's API calls, exactly as below.

- [ ] **Step 1: Write the migration**

```sql
-- Who can be found. One row per account, written by its owner, readable by
-- any signed-in user because search is the point. Nothing sensitive lives
-- here: a display name and nothing else.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  updated_at timestamptz not null default now()
);

create index profiles_display_name on public.profiles
  using gin (to_tsvector('simple', display_name));

alter table public.profiles enable row level security;

create policy "profiles are searchable by the signed in"
  on public.profiles for select to authenticated using (true);
create policy "own profile insert"
  on public.profiles for insert to authenticated
  with check (user_id = auth.uid());
create policy "own profile update"
  on public.profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A friendship is one row, whoever asked first. `pending` until the
-- addressee accepts. The unique pair constraint is on the ordered pair,
-- and the API guards the reverse direction before inserting.
create table public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  unique (requester, addressee),
  check (requester <> addressee)
);

create index friendships_addressee on public.friendships (addressee, status);
create index friendships_requester on public.friendships (requester, status);

alter table public.friendships enable row level security;

create policy "participants see their friendships"
  on public.friendships for select to authenticated
  using (auth.uid() in (requester, addressee));
create policy "ask for a friendship"
  on public.friendships for insert to authenticated
  with check (requester = auth.uid() and status = 'pending');
create policy "addressee answers"
  on public.friendships for update to authenticated
  using (addressee = auth.uid())
  with check (addressee = auth.uid() and status = 'accepted');
create policy "either side may end it"
  on public.friendships for delete to authenticated
  using (auth.uid() in (requester, addressee));

-- Plain text messages between accepted friends. No edits, no deletes in v1:
-- a message is a fact once sent.
create table public.messages (
  id bigint generated always as identity primary key,
  sender uuid not null references auth.users (id) on delete cascade,
  recipient uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  check (sender <> recipient)
);

create index messages_conversation on public.messages
  (least(sender, recipient), greatest(sender, recipient), created_at);

alter table public.messages enable row level security;

create policy "participants read their conversation"
  on public.messages for select to authenticated
  using (auth.uid() in (sender, recipient));
create policy "friends may message"
  on public.messages for insert to authenticated
  with check (
    sender = auth.uid()
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester = sender and f.addressee = recipient)
          or (f.requester = recipient and f.addressee = sender))
    )
  );
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db push --linked` (answer yes). Then verify RLS bites with the anon key alone:
`curl -s "https://abxwxpwhkcqtotjqsmxb.supabase.co/rest/v1/profiles" -H "apikey: <anon>"` → expect `[]` or a 401-style refusal, never data. (Anon without a user JWT is not `authenticated`, so an empty/denied answer proves the policies hold.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations
git commit -m "feat(social): profiles, friendships, and messages with RLS doing the guarding"
```

---

### Task 2: SocialAPI in Integrations

**Files:**
- Create: `LifeOSKit/Sources/Integrations/SocialAPI.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/SocialAPITests.swift`

**Interfaces:**
- Consumes: nothing from other tasks; `URLSession` injected like `SupabaseAuth`.
- Produces, exactly:

```swift
public struct SocialProfile: Codable, Sendable, Equatable, Identifiable {
    public let userID: UUID
    public let displayName: String
    public var id: UUID { userID }
}

public enum FriendshipStatus: String, Codable, Sendable { case pending, accepted }

public struct Friendship: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let requester: UUID
    public let addressee: UUID
    public let status: FriendshipStatus
}

public struct SocialMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let sender: UUID
    public let recipient: UUID
    public let body: String
    public let createdAt: Date
}

public struct SocialAPI: Sendable {
    public init(baseURL: URL, anonKey: String, session: URLSession = .shared)

    public func upsertMyProfile(accessToken: String, userID: UUID, displayName: String) async throws
    public func search(_ query: String, accessToken: String) async throws -> [SocialProfile]
    public func friendships(accessToken: String) async throws -> [Friendship]
    public func profiles(ids: [UUID], accessToken: String) async throws -> [SocialProfile]
    public func request(from myUserID: UUID, to userID: UUID, accessToken: String) async throws
    public func accept(friendshipID: Int, accessToken: String) async throws
    public func remove(friendshipID: Int, accessToken: String) async throws
    public func messages(with userID: UUID, accessToken: String) async throws -> [SocialMessage]
    public func send(_ body: String, to userID: UUID, accessToken: String) async throws
}
```

Implementation notes, binding:
- Every request: `apikey: anonKey`, `Authorization: Bearer <accessToken>`, `Content-Type: application/json`; PostgREST paths under `rest/v1/`.
- Column names are snake_case: decode with explicit `CodingKeys` (`user_id`, `display_name`, `created_at`); dates via `ISO8601DateFormatter` with fractional seconds (PostgREST emits them).
- `upsertMyProfile`: POST `/rest/v1/profiles` with `Prefer: resolution=merge-duplicates`.
- `search`: GET `/rest/v1/profiles?display_name=ilike.*<escaped>*&limit=20` (ilike, not the tsvector index — fine at this scale; escape `%` and `*` out of the user text).
- `messages(with:)`: GET `/rest/v1/messages?or=(and(sender.eq.<me is implied by RLS>...))` — simpler and RLS-safe: `?or=(sender.eq.<them>,recipient.eq.<them>)&order=created_at.asc&limit=200`. RLS already restricts rows to the caller's own conversations, so filtering by the other party is enough.
- `request(to:)` POSTs `{requester: <not sent>, addressee, status}` — requester must equal `auth.uid()` per RLS, and PostgREST needs the column: send `requester` explicitly (caller passes own userID via accessToken subject; add `myUserID: UUID` parameter to `request` — adjust the signature to `request(from: UUID, to: UUID, accessToken: String)`).
- Non-2xx → throw `SocialAPIError.status(Int)` (define in the file).

Tests (no network; decode + URL construction):
- Each DTO decodes from a realistic PostgREST JSON fixture (snake_case, fractional-second timestamps).
- `search` escapes wildcard characters out of the query text.
- A 403 response body maps to `SocialAPIError.status(403)` (use a stubbed `URLProtocol` the way the suite fakes fetches elsewhere, or refactor request-building into an internal pure function and assert on the `URLRequest` it yields — the internal-function route is simpler and preferred).

- [ ] Steps: failing tests → implement → `swift test --filter SocialAPITests` green → full suite green → commit `feat(social): a thin PostgREST client for friends and messages`.

---

### Task 3: Friends screen

**Files:**
- Create: `LIfeOS/Features/Social/ViewModel/FriendsViewModel.swift`
- Create: `LIfeOS/Features/Social/View/FriendsScreen.swift`
- Modify: `LIfeOS/Features/Settings/View/ProfileScreen.swift` (a Friends entry beside the gear, pushing the screen)

**Interfaces:**
- Consumes: `SocialAPI` (Task 2), `KeychainAuthSessionStore` + `AppConfig` (existing) for the token, `ProfileStore` for the local display name.
- Produces: `FriendsScreen` (pushed in the profile's `NavigationStack`), and a route Task 4 extends (`navigationDestination` for a chat).

Design, binding:
- On appear (signed in): upsert my profile (`displayName` from `ProfileStore`), then load friendships + the profiles behind them.
- Layout on `GradientCanvas(hue: .habits)`: a search field styled like the library's; "REQUESTS" eyebrow with accept rows (only when any); "FRIENDS" eyebrow with friend rows (pastel initial-letter bubble, name, chevron → chat); search results replace the list while a query is active, each row with an Add (`CapsuleButton`) or a quiet "Requested"/"Friends" state.
- Guest state: the screen renders one sentence ("Sign in to find friends and message them.") and nothing else — the profile already owns the sign-in journey via settings.
- Errors are quiet inline sentences, never alerts.
- Entry point: in `ProfileScreen`, a third control joins the pill row — a `person.2.fill` glass circle (52pt, matching the gear) that pushes `FriendsScreen` via `navigationDestination(isPresented:)`.

- [ ] Steps: build view model (plain @Observable, async funcs, `private(set)` state) → screen → wire profile → `xcodebuild` green → commit `feat(social): find people and keep friends from the profile`.

---

### Task 4: Chat

**Files:**
- Create: `LIfeOS/Features/Social/ViewModel/ChatViewModel.swift`
- Create: `LIfeOS/Features/Social/View/FriendChatScreen.swift`
- Modify: `LIfeOS/Features/Social/View/FriendsScreen.swift` (push the chat for a friend)

**Interfaces:**
- Consumes: `SocialAPI.messages/send`, Task 3's routing.
- Produces: UI only.

Design, binding:
- Bubbles echo the assistant sheet: my messages right-aligned in `accentSoft`, theirs left in `.ultraThinMaterial`; timestamps as quiet captions on day boundaries only.
- Composer identical in shape to the assistant's (capsule field + accent send).
- Poll: `.task` loop `while !Task.isCancelled { refresh; sleep 5s }` — cancels automatically when the screen closes; also refresh immediately after send.
- Sending appends optimistically, then reconciles on the next refresh; a failed send drops the optimistic row and shows one inline sentence.
- Empty conversation: "Say hi to <name>." centered, secondary.

- [ ] Steps: view model → screen → wire → `xcodebuild` green, full kit suite green → commit `feat(social): message a friend, plainly`.

---

## Out of scope (v1, recorded)

- Push notifications and background delivery (polling only while the chat is open).
- Realtime websockets, typing indicators, read receipts.
- Profile photos in search (initial-letter bubbles for now; photos need storage + moderation thought).
- Blocking. Removing a friendship severs messaging both ways via RLS, which is the v1 story.
- Group chats.
