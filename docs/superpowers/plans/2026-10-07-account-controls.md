# Account controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The coach can clear its conversation; Settings can clear chosen kinds of data (phone and server) and schedule the account's deletion in 30 days, undone by signing back in; a daily server job carries deletions out and phones wipe what they kept.

**Architecture:** `Persistence` gains the tested phone side: `ChatStore.deleteConversation`, `DataCategory` and `LocalDataEraser` (which models each category owns, and the per-account keys it resets), and `PendingAccountWipe` (the list of signed-out accounts awaiting deletion, and wiping one's folder and defaults). The server side is one migration and `_shared/account.ts`, whose handlers take their storage and providers as dependencies so every path is tested in Deno; `account-data` and `account-purge` are thin `Deno.serve` wrappers. The app adds an `AccountDataClient`, the coach's menu item, a `Your data` section with Clear data and Delete account pages, a keep-or-leave page in the shell, and a launch-time wipe.

**Tech Stack:** SwiftData (`ModelContext.delete(model:)`), SwiftUI, Swift Testing, Deno with `jsr:@std/assert`, Postgres (`pg_cron`, `pg_net`, Vault), XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-07-account-controls-design.md`

## Global Constraints

- Categories and their keys: `notes` Notes and journal, `habits` Habits and goals, `health` Health history, `money` Money history, `chats` AI chats, `messages` Messages.
- Server tables per category: `notes` → `note_documents`, `note_folders` (by `user_id`); `health` → `daily_metrics`, `sleep_records`, `workout_records`, `whoop_raw` (by `user_id`); `messages` → `messages` where `sender` or `recipient` is the caller, `group_messages` where `sender` is the caller. `habits`, `money`, `chats` have no server rows.
- Phone models per category: `notes` → `NoteDocument`, `NoteFolder`, `NoteTask`, `NoteLink`, and the defaults key `notes.sync.cursor` removed; `habits` → `PlanEntry`, `HabitTick`; `health` → `DailyMetrics`, `WorkoutRecord`, `SleepRecord`, `WhoopRawRecord`; `money` → `MoneyEntry`, `SpendBucket`; `chats` → `ChatMessage`, and `coach.conversationID` removed.
- Deletion is scheduled for exactly 30 days after the request; a second request keeps the first date.
- Copy, verbatim: `Clear conversation`, `Clear this conversation? LIFO forgets it on this phone.`, `Your data`, `Clear data…`, `Delete account…`, `Clear selected…`, `Type CLEAR to confirm`, `Cleared.`, `Could not clear. Nothing was removed from this phone.`, `Clearing a conversation clears it for the other person too: it is one message, not two copies.`, `Type DELETE to confirm`, `Delete my account`, `Your account is set to be deleted on <date>.`, `Keep my account`, `Sign out`.
- Functions log counts and error kinds, never row contents or tokens. `account-purge` answers only `x-purge-secret` equal to `PURGE_SECRET`.
- Paper and ink, `.editorial(role)` buttons (destructive role for the two irreversible actions), fonts from `LifeOSType`/`Editorial`; `scripts/check-typography.sh` reports nothing new.
- `LifeOSKit` builds for macOS: no UIKit in `Persistence`.
- Commits conventional, no em dashes, no Claude attribution. Worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/account-controls` on `feat/account-controls` from main 83f31f1; simulator `B192EA65-BAA2-4814-A298-94A2F0C8FC87`; DerivedData `~/Library/Developer/Xcode/DerivedData/account-controls`.

## Review Focus

1. Clearing one category must never touch another's models (Notes clearing must leave habits, health, money and chats): `LocalDataEraserTests.eachCategoryClearsOnlyItsOwn` in Task 1.
2. The coach's clear must leave the calendar assistant's conversation in the same store: `ChatStoreTests.clearingOneConversationLeavesTheOthers` in Task 1.
3. A clear request with a category name the server does not know must change nothing and say 400, never a partial delete: `account_test.ts` "an unknown category clears nothing" in Task 2.
4. The purge must hand a group over before deleting the login (the owner column cascades), and one account's failure must not stop the rest: `account_test.ts` "groups move before the login goes" and "one failure does not stop the run" in Task 2.
5. A pending wipe for an account that is not yet deleted must leave its store alone (offline, or kept): `PendingAccountWipeTests.onlyConfirmedDeletionsAreWiped` in Task 1.

---

### Task 0: Worktree and baselines

- [ ] `(cd LifeOSKit && swift test 2>&1 | grep "Test run with" | tail -1)`; `(cd supabase/functions/_shared && deno test --allow-env 2>&1 | tail -1)`; the typography baseline into `$W/typo-base.txt`; commit this plan (`docs(plans): account controls`).

---

### Task 1: The phone side, in Persistence

**Files:** Modify `LifeOSKit/Sources/Persistence/ChatMessage.swift`; Create `LifeOSKit/Sources/Persistence/AccountData.swift`; Test `LifeOSKit/Tests/PersistenceTests/AccountDataTests.swift`.

**Interfaces — Produces:** `ChatStore.deleteConversation(_ id: UUID) throws`; `enum DataCategory: String, CaseIterable, Codable, Sendable { case notes, habits, health, money, chats, messages }` with `title`, `hasServerRows: Bool`; `struct LocalDataEraser { init(context: ModelContext, defaults: UserDefaults); func erase(_ categories: Set<DataCategory>) throws }`; `struct PendingAccountWipe { init(defaults: UserDefaults = .standard); var ids: [String]; func add(_:); func remove(_:); func wipe(_ id: String, base: URL) throws }` (wipe removes the account directory under `base` and the account's defaults suite, then removes the id).

- [ ] **Step 1: Failing tests** (`AccountDataTests.swift`):

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct AccountDataTests {
    private func context() throws -> ModelContext { ModelContext(try LifeOSContainer.make(inMemory: true)) }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "account.data.\(UUID().uuidString)")! }

    @Test func clearingOneConversationLeavesTheOthers() throws {
        let context = try context()
        let chats = ChatStore(context: context)
        let coach = UUID(), assistant = UUID()
        try chats.append(conversationID: coach, role: .user, text: "How did I sleep?")
        try chats.append(conversationID: assistant, role: .user, text: "Move standup")
        try chats.deleteConversation(coach)
        #expect(try chats.recent(conversationID: coach).isEmpty)
        #expect(try chats.recent(conversationID: assistant).count == 1)
    }

    @Test func eachCategoryClearsOnlyItsOwn() throws {
        let context = try context()
        let store = defaults()
        let notes = NotesStore(context: context)
        _ = try notes.createDocument(title: "Plan", bucket: .projects)
        context.insert(PlanEntry(kind: .habit, title: "Run"))
        try ChatStore(context: context).append(conversationID: UUID(), role: .user, text: "hi")
        store.set(Date(), forKey: "notes.sync.cursor")
        store.set(UUID().uuidString, forKey: "coach.conversationID")
        try context.save()

        try LocalDataEraser(context: context, defaults: store).erase([.notes])
        #expect(try context.fetchCount(FetchDescriptor<NoteDocument>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 1)
        #expect(store.object(forKey: "notes.sync.cursor") == nil)
        #expect(store.string(forKey: "coach.conversationID") != nil)

        try LocalDataEraser(context: context, defaults: store).erase([.habits, .chats])
        #expect(try context.fetchCount(FetchDescriptor<PlanEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 0)
        #expect(store.string(forKey: "coach.conversationID") == nil)
    }

    @Test func categoriesKnowWhereTheyLive() {
        #expect(DataCategory.allCases.filter(\.hasServerRows) == [.notes, .health, .messages])
        #expect(DataCategory.chats.title == "AI chats")
    }

    @Test func onlyConfirmedDeletionsAreWiped() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let list = defaults()
        let kept = UserScope(id: "kept-user"), gone = UserScope(id: "gone-user")
        for scope in [kept, gone] {
            try FileManager.default.createDirectory(at: scope.directory(base: base), withIntermediateDirectories: true)
            UserDefaults(suiteName: scope.defaultsSuiteName)!.set(true, forKey: "marker")
        }
        var wipe = PendingAccountWipe(defaults: list)
        wipe.add(kept.id); wipe.add(gone.id); wipe.add(gone.id)
        #expect(wipe.ids == [kept.id, gone.id])
        try wipe.wipe(gone.id, base: base)
        #expect(!FileManager.default.fileExists(atPath: gone.directory(base: base).path))
        #expect(FileManager.default.fileExists(atPath: kept.directory(base: base).path))
        #expect(UserDefaults(suiteName: gone.defaultsSuiteName)!.object(forKey: "marker") == nil)
        #expect(PendingAccountWipe(defaults: list).ids == [kept.id])
        wipe = PendingAccountWipe(defaults: list)
        wipe.remove(kept.id)
        #expect(wipe.ids.isEmpty)
    }
}
```

(Read `PlanEntry`'s initialiser first, `grep -n "public init" LifeOSKit/Sources/Persistence/PlanEntry.swift`, and use its real parameters.)

- [ ] **Step 2:** `swift test --filter AccountData` fails to build.

- [ ] **Step 3: Implement.** In `ChatStore`:

```swift
    /// Forgets one conversation; the others in the store stay.
    public func deleteConversation(_ id: UUID) throws {
        try context.delete(model: ChatMessage.self, where: #Predicate { $0.conversationID == id })
        try context.save()
    }
```

`AccountData.swift`:

```swift
import Foundation
import SwiftData

/// What a person can clear, and where each kind lives.
public enum DataCategory: String, CaseIterable, Codable, Sendable {
    case notes, habits, health, money, chats, messages

    public var title: String {
        switch self {
        case .notes: "Notes and journal"
        case .habits: "Habits and goals"
        case .health: "Health history"
        case .money: "Money history"
        case .chats: "AI chats"
        case .messages: "Messages"
        }
    }

    /// Whether the server holds rows for it, which must go first.
    public var hasServerRows: Bool { [.notes, .health, .messages].contains(self) }
}

/// Deletes this phone's copy of the chosen categories.
@MainActor
public struct LocalDataEraser {
    private let context: ModelContext
    private let defaults: UserDefaults

    public init(context: ModelContext, defaults: UserDefaults) {
        self.context = context
        self.defaults = defaults
    }

    public func erase(_ categories: Set<DataCategory>) throws {
        for category in DataCategory.allCases where categories.contains(category) {
            switch category {
            case .notes:
                try context.delete(model: NoteDocument.self)
                try context.delete(model: NoteFolder.self)
                try context.delete(model: NoteTask.self)
                try context.delete(model: NoteLink.self)
                // The next pull starts from nothing, not from a cursor past
                // rows that no longer exist.
                defaults.removeObject(forKey: "notes.sync.cursor")
            case .habits:
                try context.delete(model: PlanEntry.self)
                try context.delete(model: HabitTick.self)
            case .health:
                try context.delete(model: DailyMetrics.self)
                try context.delete(model: WorkoutRecord.self)
                try context.delete(model: SleepRecord.self)
                try context.delete(model: WhoopRawRecord.self)
            case .money:
                try context.delete(model: MoneyEntry.self)
                try context.delete(model: SpendBucket.self)
            case .chats:
                try context.delete(model: ChatMessage.self)
                defaults.removeObject(forKey: "coach.conversationID")
            case .messages:
                break   // nothing on the phone
            }
        }
        try context.save()
    }
}

/// Accounts signed out by a deletion request, whose stores stay on this
/// phone until the server confirms the deletion.
public struct PendingAccountWipe {
    private let defaults: UserDefaults
    private static let key = "accounts.pendingWipe"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var ids: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func add(_ id: String) {
        guard !ids.contains(id) else { return }
        defaults.set(ids + [id], forKey: Self.key)
    }

    public func remove(_ id: String) {
        defaults.set(ids.filter { $0 != id }, forKey: Self.key)
    }

    /// The account's store folder and defaults suite go; then it leaves the list.
    public func wipe(_ id: String, base: URL) throws {
        let scope = UserScope(id: id)
        let directory = scope.directory(base: base)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        UserDefaults(suiteName: scope.defaultsSuiteName)?.removePersistentDomain(forName: scope.defaultsSuiteName)
        UserDefaults.standard.removePersistentDomain(forName: scope.defaultsSuiteName)
        remove(id)
    }
}
```

If `removePersistentDomain` on the suite leaves the key readable in the test (suites are cached per process), also clear each key: `UserDefaults(suiteName:)?.dictionaryRepresentation().keys.forEach { suite.removeObject(forKey: $0) }`; ledger which.

- [ ] **Step 4:** filter passes; whole suite; `swift build`.
- [ ] **Step 5:** `git commit -m "feat(persistence): clear a conversation, erase chosen data, and wipe a deleted account's store"`

---

### Task 2: The server

**Files:** Create `supabase/migrations/20261007120000_account_controls.sql`, `supabase/functions/_shared/account.ts`, `supabase/functions/_shared/account_test.ts`, `supabase/functions/account-data/index.ts`, `supabase/functions/account-purge/index.ts`; Modify `supabase/config.toml` (`[functions.account-purge] verify_jwt = false`; `account-data` keeps `verify_jwt = false` too because its deleted-IDs check is anonymous, and every other call is gated by `resolveUser`).

**Interfaces — Produces:** `ServerCategory = "notes" | "health" | "messages"`; `type AccountStore = { clear(user: string, categories: ServerCategory[]): Promise<void>; schedule(user: string, at: Date): Promise<Date>; cancel(user: string): Promise<void>; scheduledFor(user: string): Promise<Date | null>; deletedAmong(ids: string[]): Promise<string[]> }`; `handleAccountData(req, { resolveUser, store, now })`; `type PurgeDeps = { due(now: Date): Promise<string[]>; ownedGroups(user): Promise<string[]>; heirOf(group, user): Promise<string | null>; transfer(group, heir): Promise<void>; deleteGroup(group): Promise<void>; revokeConnections(user): Promise<void>; removeAvatars(user): Promise<void>; deleteUser(user): Promise<void>; recordDeleted(user): Promise<void>; log(line: string): void }`; `runPurge(deps, now): Promise<{ deleted: number; failed: number }>`; `handleAccountPurge(req, { secret, run })`.

- [ ] **Step 1: The migration.**

```sql
-- Account controls: deletion scheduled 30 days ahead, carried out by a daily
-- job, and a record of deleted ids that phones ask about before wiping what
-- they kept. Nothing here holds content.

alter table public.profiles add column if not exists deletion_scheduled_for timestamptz;

create table if not exists public.deleted_accounts (
  user_id uuid primary key,
  deleted_at timestamptz not null default now()
);
-- No policies: only the functions, with the service role, read or write it.
alter table public.deleted_accounts enable row level security;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Reads the project URL and the purge secret from Vault, so neither is in
-- the migration. The owner adds both secrets once (see the spec's steps).
select cron.schedule(
  'account-purge-daily',
  '0 3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/account-purge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

- [ ] **Step 2: Failing tests** (`account_test.ts`):

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { type AccountStore, handleAccountData, handleAccountPurge, type PurgeDeps, runPurge } from "./account.ts";

function fakeStore() {
  const calls: string[] = [];
  let scheduled: Date | null = null;
  const store: AccountStore = {
    clear: (u, c) => { calls.push(`clear ${u} ${c.join(",")}`); return Promise.resolve(); },
    schedule: (u, at) => { scheduled ??= at; calls.push(`schedule ${u}`); return Promise.resolve(scheduled); },
    cancel: (u) => { scheduled = null; calls.push(`cancel ${u}`); return Promise.resolve(); },
    scheduledFor: () => Promise.resolve(scheduled),
    deletedAmong: (ids) => Promise.resolve(ids.filter((id) => id.startsWith("gone"))),
  };
  return { store, calls };
}
const now = new Date("2026-10-07T12:00:00Z");
const signedIn = () => Promise.resolve("u1");
const req = (method: string, body?: unknown, query = "", auth = true) =>
  new Request(`http://x/account-data${query}`, {
    method, headers: auth ? { Authorization: "Bearer jwt" } : {}, body: body ? JSON.stringify(body) : undefined,
  });

Deno.test("every account call but the deleted check needs a session", async () => {
  const { store } = fakeStore();
  for (const r of [req("POST", { clear: ["notes"] }, "", false), req("DELETE", undefined, "", false), req("PATCH", { keep: true }, "", false), req("GET", undefined, "", false)]) {
    assertEquals((await handleAccountData(r, { resolveUser: () => Promise.resolve(null), store, now })).status, 401);
  }
});

Deno.test("clear deletes the caller's chosen server categories", async () => {
  const { store, calls } = fakeStore();
  const res = await handleAccountData(req("POST", { clear: ["notes", "messages", "habits"] }), { resolveUser: signedIn, store, now });
  assertEquals(res.status, 200);
  assertEquals(calls, ["clear u1 notes,messages"]);
});

Deno.test("an unknown category clears nothing", async () => {
  const { store, calls } = fakeStore();
  const res = await handleAccountData(req("POST", { clear: ["notes", "everything"] }), { resolveUser: signedIn, store, now });
  assertEquals(res.status, 400);
  assertEquals(calls, []);
});

Deno.test("deletion is scheduled thirty days out, once, and keep cancels it", async () => {
  const { store } = fakeStore();
  const first = await (await handleAccountData(req("DELETE"), { resolveUser: signedIn, store, now })).json();
  assertEquals(first.deletion_scheduled_for, "2026-11-06T12:00:00.000Z");
  const later = new Date("2026-10-10T12:00:00Z");
  const second = await (await handleAccountData(req("DELETE"), { resolveUser: signedIn, store, now: later })).json();
  assertEquals(second.deletion_scheduled_for, "2026-11-06T12:00:00.000Z");
  await handleAccountData(req("PATCH", { keep: true }), { resolveUser: signedIn, store, now });
  const status = await (await handleAccountData(req("GET"), { resolveUser: signedIn, store, now })).json();
  assertEquals(status.deletion_scheduled_for, null);
});

Deno.test("the deleted check is anonymous, capped, and names only deleted ids", async () => {
  const { store } = fakeStore();
  const ok = await handleAccountData(req("GET", undefined, "?deleted=gone-1,kept-2", false), { resolveUser: () => Promise.resolve(null), store, now });
  assertEquals((await ok.json()).deleted, ["gone-1"]);
  const many = Array.from({ length: 21 }, (_, i) => `gone-${i}`).join(",");
  const tooMany = await handleAccountData(req("GET", undefined, `?deleted=${many}`, false), { resolveUser: () => Promise.resolve(null), store, now });
  assertEquals(tooMany.status, 400);
});

function purgeDeps(over: Partial<PurgeDeps> = {}) {
  const steps: string[] = [];
  const deps: PurgeDeps = {
    due: () => Promise.resolve(["a", "b"]),
    ownedGroups: (u) => Promise.resolve(u === "a" ? ["g-shared", "g-alone"] : []),
    heirOf: (g) => Promise.resolve(g === "g-shared" ? "c" : null),
    transfer: (g, h) => { steps.push(`transfer ${g} ${h}`); return Promise.resolve(); },
    deleteGroup: (g) => { steps.push(`delete-group ${g}`); return Promise.resolve(); },
    revokeConnections: (u) => { steps.push(`revoke ${u}`); return Promise.resolve(); },
    removeAvatars: (u) => { steps.push(`avatars ${u}`); return Promise.resolve(); },
    deleteUser: (u) => { steps.push(`delete-user ${u}`); return Promise.resolve(); },
    recordDeleted: (u) => { steps.push(`record ${u}`); return Promise.resolve(); },
    log: () => {},
    ...over,
  };
  return { deps, steps };
}

Deno.test("groups move before the login goes", async () => {
  const { deps, steps } = purgeDeps({ due: () => Promise.resolve(["a"]) });
  const result = await runPurge(deps, now);
  assertEquals(steps, ["transfer g-shared c", "delete-group g-alone", "revoke a", "avatars a", "delete-user a", "record a"]);
  assertEquals(result, { deleted: 1, failed: 0 });
});

Deno.test("one failure does not stop the run", async () => {
  const { deps, steps } = purgeDeps({
    revokeConnections: (u) => u === "a" ? Promise.reject(new Error("boom")) : Promise.resolve(),
  });
  const result = await runPurge(deps, now);
  assertEquals(result, { deleted: 1, failed: 1 });
  assertEquals(steps.includes("delete-user a"), false);
  assertEquals(steps.includes("record b"), true);
});

Deno.test("the purge answers only its secret", async () => {
  let ran = false;
  const run = () => { ran = true; return Promise.resolve({ deleted: 0, failed: 0 }); };
  const wrong = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "nope" } }), { secret: "s3", run });
  assertEquals(wrong.status, 401);
  assertEquals(ran, false);
  const unset = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "" } }), { secret: "", run });
  assertEquals(unset.status, 401);
  const right = await handleAccountPurge(new Request("http://x", { method: "POST", headers: { "x-purge-secret": "s3" } }), { secret: "s3", run });
  assertEquals(right.status, 200);
  assertEquals(ran, true);
});
```

- [ ] **Step 3:** `deno test --allow-env account_test.ts` fails (module missing).

- [ ] **Step 4: Implement `account.ts`:**

```ts
// The account's own controls: clearing chosen data, scheduling and cancelling
// deletion, and the daily purge that carries deletions out. Handlers take
// their storage as dependencies so every path is tested without a database.
// Logs carry counts and kinds, never content.

import { json } from "./supabase.ts";

export type ServerCategory = "notes" | "health" | "messages";
const SERVER: readonly string[] = ["notes", "health", "messages"];
const LOCAL_ONLY: readonly string[] = ["habits", "money", "chats"];
const GRACE_DAYS = 30;

export type AccountStore = {
  clear(user: string, categories: ServerCategory[]): Promise<void>;
  schedule(user: string, at: Date): Promise<Date>;
  cancel(user: string): Promise<void>;
  scheduledFor(user: string): Promise<Date | null>;
  deletedAmong(ids: string[]): Promise<string[]>;
};

export async function handleAccountData(
  req: Request,
  deps: { resolveUser: (req: Request) => Promise<string | null>; store: AccountStore; now: Date },
): Promise<Response> {
  const url = new URL(req.url);
  const asked = url.searchParams.get("deleted");
  if (req.method === "GET" && asked !== null) {
    const ids = asked.split(",").map((id) => id.trim()).filter(Boolean);
    if (ids.length === 0 || ids.length > 20) return json({ error: "invalid_ids" }, 400);
    return json({ deleted: await deps.store.deletedAmong(ids) }, 200);
  }

  const user = await deps.resolveUser(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  switch (req.method) {
    case "POST": {
      let body: { clear?: unknown };
      try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }
      if (!Array.isArray(body.clear)) return json({ error: "invalid_body" }, 400);
      const names = body.clear.map(String);
      if (names.some((n) => !SERVER.includes(n) && !LOCAL_ONLY.includes(n))) {
        return json({ error: "unknown_category" }, 400);
      }
      const server = names.filter((n) => SERVER.includes(n)) as ServerCategory[];
      if (server.length) await deps.store.clear(user, server);
      return json({ cleared: server }, 200);
    }
    case "DELETE": {
      const at = new Date(deps.now.getTime() + GRACE_DAYS * 86_400_000);
      const date = await deps.store.schedule(user, at);
      return json({ deletion_scheduled_for: date.toISOString() }, 200);
    }
    case "PATCH": {
      let body: { keep?: unknown };
      try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }
      if (body.keep !== true) return json({ error: "invalid_body" }, 400);
      await deps.store.cancel(user);
      return json({ deletion_scheduled_for: null }, 200);
    }
    case "GET": {
      const date = await deps.store.scheduledFor(user);
      return json({ deletion_scheduled_for: date ? date.toISOString() : null }, 200);
    }
    default:
      return json({ error: "method_not_allowed" }, 405);
  }
}

export type PurgeDeps = {
  due(now: Date): Promise<string[]>;
  ownedGroups(user: string): Promise<string[]>;
  heirOf(group: string, user: string): Promise<string | null>;
  transfer(group: string, heir: string): Promise<void>;
  deleteGroup(group: string): Promise<void>;
  revokeConnections(user: string): Promise<void>;
  removeAvatars(user: string): Promise<void>;
  deleteUser(user: string): Promise<void>;
  recordDeleted(user: string): Promise<void>;
  log(line: string): void;
};

/// Each due account in turn: groups first (the owner column cascades), then
/// the connections, the photos, the login, and the record.
export async function runPurge(deps: PurgeDeps, now: Date): Promise<{ deleted: number; failed: number }> {
  let deleted = 0, failed = 0;
  for (const user of await deps.due(now)) {
    try {
      for (const group of await deps.ownedGroups(user)) {
        const heir = await deps.heirOf(group, user);
        if (heir) await deps.transfer(group, heir); else await deps.deleteGroup(group);
      }
      await deps.revokeConnections(user);
      await deps.removeAvatars(user);
      await deps.deleteUser(user);
      await deps.recordDeleted(user);
      deleted += 1;
    } catch (error) {
      failed += 1;
      deps.log(`purge failed: ${error instanceof Error ? error.name : "unknown"}`);
    }
  }
  deps.log(`purge done: ${deleted} deleted, ${failed} failed`);
  return { deleted, failed };
}

export async function handleAccountPurge(
  req: Request,
  deps: { secret: string; run: () => Promise<{ deleted: number; failed: number }> },
): Promise<Response> {
  const given = req.headers.get("x-purge-secret") ?? "";
  if (!deps.secret || given !== deps.secret) return json({ error: "unauthorized" }, 401);
  return json(await deps.run(), 200);
}
```

- [ ] **Step 5: The two functions** (real dependencies over `serviceClient()`):

`account-data/index.ts`:

```ts
import { resolveUser, serviceClient } from "../_shared/supabase.ts";
import { type AccountStore, handleAccountData, type ServerCategory } from "../_shared/account.ts";

const TABLES: Record<ServerCategory, string[]> = {
  notes: ["note_documents", "note_folders"],
  health: ["daily_metrics", "sleep_records", "workout_records", "whoop_raw"],
  messages: [],
};

function store(): AccountStore {
  const db = serviceClient();
  return {
    async clear(user, categories) {
      for (const category of categories) {
        for (const table of TABLES[category]) {
          const { error } = await db.from(table).delete().eq("user_id", user);
          if (error) throw new Error(`clear_${table}`);
        }
        if (category === "messages") {
          const direct = await db.from("messages").delete().or(`sender.eq.${user},recipient.eq.${user}`);
          if (direct.error) throw new Error("clear_messages");
          const group = await db.from("group_messages").delete().eq("sender", user);
          if (group.error) throw new Error("clear_group_messages");
        }
      }
    },
    async schedule(user, at) {
      const { data } = await db.from("profiles").select("deletion_scheduled_for").eq("id", user).maybeSingle();
      if (data?.deletion_scheduled_for) return new Date(data.deletion_scheduled_for);
      const { error } = await db.from("profiles").update({ deletion_scheduled_for: at.toISOString() }).eq("id", user);
      if (error) throw new Error("schedule_failed");
      return at;
    },
    async cancel(user) {
      const { error } = await db.from("profiles").update({ deletion_scheduled_for: null }).eq("id", user);
      if (error) throw new Error("cancel_failed");
    },
    async scheduledFor(user) {
      const { data } = await db.from("profiles").select("deletion_scheduled_for").eq("id", user).maybeSingle();
      return data?.deletion_scheduled_for ? new Date(data.deletion_scheduled_for) : null;
    },
    async deletedAmong(ids) {
      const { data } = await db.from("deleted_accounts").select("user_id").in("user_id", ids);
      return (data ?? []).map((row: { user_id: string }) => row.user_id);
    },
  };
}

Deno.serve((req) => handleAccountData(req, { resolveUser, store: store(), now: new Date() }));
```

Check the profiles table's key column name first (`grep -n "create table public.profiles" -A6 supabase/migrations/*.sql`); use `user_id` instead of `id` if that is the key. Check each health table's owner column the same way. A health table that does not exist in production makes `delete` error: ignore error code `42P01` (undefined table) for those four, since the privacy plan may already have dropped them.

`account-purge/index.ts`: `Deno.serve((req) => handleAccountPurge(req, { secret: Deno.env.get("PURGE_SECRET") ?? "", run: () => runPurge(deps(), new Date()) }))` with `deps()` built on `serviceClient()`:
- `due`: `profiles` where `deletion_scheduled_for <= now`, ids;
- `ownedGroups`: `social_groups` ids where `owner_id = user`;
- `heirOf`: `group_members` where `group_id = g`, `status = 'accepted'`, `user_id <> user`, ordered by `joined_at`, first `user_id`;
- `transfer`: update `social_groups.owner_id`; `deleteGroup`: delete the group;
- `revokeConnections`: for each `plaid_items` row call `callPlaid("/item/remove", { access_token })` (from `_shared/plaid.ts`, ignoring `ITEM_NOT_FOUND`); Whoop: `DELETE https://api.prod.whoop.com/developer/v2/user/access` with the stored access token, best effort; Fitbit: `POST https://api.fitbit.com/oauth2/revoke` with basic auth `FITBIT_CLIENT_ID:FITBIT_CLIENT_SECRET` and `token=<access>`, best effort; a provider's refusal is logged by kind and does not throw (the rows go with the login anyway);
- `removeAvatars`: `storage.from("avatars").list(user)` then `remove` those paths;
- `deleteUser`: `db.auth.admin.deleteUser(user)`;
- `recordDeleted`: insert into `deleted_accounts`;
- `log`: `console.log`.

- [ ] **Step 6:** `deno test --allow-env account_test.ts` passes (9); the whole `_shared` suite; `deno check` both `index.ts`; add the two `verify_jwt = false` blocks to `config.toml` with a comment each. Commit `feat(supabase): account data controls and a daily purge that hands groups over first`.

---

### Task 3: The client and the coach

**Files:** Modify `LIfeOS/Features/Settings/Model/AppConfig.swift` (`accountDataEndpoint`), `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift`, `LIfeOS/Features/Coach/View/LifoCoachScreen.swift`; Create `LIfeOS/Features/Settings/Model/AccountDataClient.swift`.

**Interfaces — Produces:** `struct AccountDataClient { func clear(_ categories: Set<DataCategory>) async throws; func scheduleDeletion() async throws -> Date; func keep() async throws; func scheduledDeletion() async throws -> Date?; func deleted(among ids: [String]) async throws -> [String] }` (Supabase bearer from `KeychainAuthSessionStore().load()`, anon key for `deleted(among:)`); `CoachViewModel.clearConversation()`.

- [ ] **Step 1: The client**, URLSession over `AppConfig.supabaseURL` + `functions/v1/account-data`, decoding `{"deletion_scheduled_for": ISO or null}` and `{"deleted": [..]}`; non-2xx throws `AccountDataError.failed(status)`.
- [ ] **Step 2: The coach.** `clearConversation()`: `try? ChatStore(context:).deleteConversation(conversationID)`, a new `conversationID = UUID()` saved to `coach.conversationID`, `history = []`, stop speaking. In `LifoCoachScreen`'s top bar, a `Menu` (or the existing one) gains `Button("Clear conversation", role: .destructive)` behind a `confirmationDialog("Clear this conversation? LIFO forgets it on this phone.", ...)` with `Clear` (destructive) and `Cancel`.
- [ ] **Step 3:** Build; commit `feat(coach): clear the conversation`.

---

### Task 4: Clear data

**Files:** Create `LIfeOS/Features/Settings/View/ClearDataScreen.swift`; Modify `LIfeOS/Features/Settings/View/SettingsScreen.swift` (a `Your data` section above `signOutButton`).

- [ ] **Step 1:** `ClearDataScreen`: rows per `DataCategory.allCases` with a checkbox (`Image(systemName: selected ? "checkmark.square.fill" : "square")`), the title in `LifeOSType.rowTitle`, and its where-it-lives line in `LifeOSType.caption` quiet ink:
  - notes: `On this phone and in your synced notes.`
  - habits: `On this phone only.`
  - health: `On this phone, and older copies on our server.`
  - money: `On this phone only. Your bank stays connected.`
  - chats: `On this phone only.`
  - messages: `On our server. Clearing a conversation clears it for the other person too: it is one message, not two copies.`
  Then `HairlineField(placeholder: "Type CLEAR to confirm")` and `Button("Clear selected…")` `.editorial(.destructive, fullWidth: true)`, disabled unless something is ticked and the field reads `CLEAR`. Action: if any ticked category `hasServerRows`, `await client.clear(selected)`; on failure show `Could not clear. Nothing was removed from this phone.` and stop; then `try LocalDataEraser(context:defaults: .currentAccount).erase(selected)`; then `Cleared.` and dismiss after a beat. The `notes` erase also calls `noteSync` nothing; the next pull refills from an empty server.
- [ ] **Step 2: Settings.** A `sectionLabel("Your data")` and an `AccountPanel` with two `NavigationLink`s, `Clear data…` → `ClearDataScreen()`, `Delete account…` → `DeleteAccountScreen(onDeleted: onSignOut)` (Task 5), styled like the `At a glance` rows; the second label in the destructive colour (`LifeOSTokens.alertText`).
- [ ] **Step 3:** Build; typography; commit `feat(settings): clear chosen data, here and on the server`.

---

### Task 5: Delete account, keep-or-leave, and the launch wipe

**Files:** Create `LIfeOS/Features/Settings/View/DeleteAccountScreen.swift`, `LIfeOS/App/KeepAccountScreen.swift`; Modify `LIfeOS/App/AppShell.swift`, `LIfeOS/Features/Settings/View/SettingsScreen.swift` (an `onDeleted` callback through to the shell's sign-out, the way `onSignOut` already flows), `LIfeOS/App/LIfeOSApp.swift` or `AppShell` (launch wipe).

- [ ] **Step 1: The page.** The three sentences from the spec with the date (`now + 30 days`, `.dateTime.month(.wide).day()`), `HairlineField(placeholder: "Type DELETE to confirm")`, `Button("Delete my account")` `.editorial(.destructive, fullWidth: true)` enabled only on `DELETE`. Action: `let date = try await client.scheduleDeletion()`; then the GitHub revoke (`github?.disconnect()` from the environment, already fire-and-forget); then `PendingAccountWipe().add(currentUserID)`; then `onDeleted()` (the existing sign-out path: push deregistered, integrations deactivated, session removed). A failure shows `Could not schedule the deletion. Nothing has changed.` and stays.
- [ ] **Step 2: Keep or leave.** In `AppShell`, after a session is restored or sign-in finishes (where `ProfileSync.pull()` runs), `if let date = try? await AccountDataClient().scheduledDeletion() { pendingDeletion = date }`. While `pendingDeletion` is set, an overlay `KeepAccountScreen(date:onKeep:onSignOut:)` covers everything: masthead `Your account is set to be deleted on <date>.`, a quiet line `Keep it and everything comes back as it was.`, `Keep my account` `.editorial(.primary, fullWidth: true)` → `try await client.keep()`, `PendingAccountWipe().remove(id)`, `pendingDeletion = nil`; `Sign out` `.editorial(.quiet)` → the sign-out path.
- [ ] **Step 3: The launch wipe.** In `AppShell`'s launch `.task`, before restoring: `let pending = PendingAccountWipe(); if !pending.ids.isEmpty, let gone = try? await AccountDataClient().deleted(among: pending.ids) { for id in gone { try? pending.wipe(id, base: <Application Support>); KeychainWhoopTokenStore(account: id).clear(); KeychainFitbitAuthStore(account: id).clearPending(); KeychainGitHubTokenStore(account: id).clear() } }` (read each store's real clearing API first; `AccountStore.remove` was already done at sign-out). The base URL is the same one `LIfeOSApp` uses for `UserScope.storeURL(base:)`; read it there.
- [ ] **Step 4:** Build; typography; commit `feat(account): delete in 30 days, keep by signing back in, and wipe what the phone kept`.

---

### Task 6: Previews, UI tests, captures

- [ ] **Pages:** `settings-clear-data` (`ClearDataScreen` with a stub client), `settings-delete-account`, `keep-account` (`KeepAccountScreen` with a fixed date), and the coach page with a few turns (`coach` exists). Inject the client through an `AccountDataClient` protocol `AccountDataClienting` with a `StubAccountDataClient` for previews.
- [ ] **UI tests** (`LIfeOSUITests/AccountControlsUITests.swift`, added with the `xcodeproj` gem): `Clear selected…` disabled until a box is ticked and `CLEAR` typed, then enabled; the coach's `Clear conversation` empties the transcript (the coach preview's first answer gone); `Keep my account` dismisses the keep page.
- [ ] **Captures:** the three pages and the coach menu, light and dark.
- [ ] Run all UI tests; commit `test(account): preview pages and UI tests for the account controls`.

---

### Task 7: Verification, review, finishing

- [ ] Package suite, `swift build`, Deno suite, typography, app and `AlmanacWidgets` builds, all UI tests.
- [ ] Fresh whole-branch review on the most capable model; one fix pass.
- [ ] Offer the finishing options. Deploying `account-data` and `account-purge` and running the migration touch the live project: ask the owner before doing either.
