# Workout Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A curated, verified YouTube workout catalog, a planner that picks today's session from the person's goal, battery and recent splits, a library screen, and a player screen with the glass HUD that records the session.

**Architecture:** A read-only Supabase table seeded by a migration whose ids are verified by a keyless oEmbed script. The app caches rows in SwiftData, computes the plan with a pure `WorkoutPlanner` in `Sectors`, and plays videos in a `WKWebView` with the existing `SessionHUD` and `ActivityRecorder` underneath. No runtime AI, no YouTube API quota.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, WebKit, Supabase (Postgres, RLS), Deno for the verify script, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-14-workout-library-design.md`

## Global Constraints

- iOS 26.0, Swift 6.0. Package tests run on macOS; package code stays free of WebKit and UIKit.
- Tests are Swift Testing. Backend scripts and their tests are Deno (`deno test`).
- A missing value is never a zero; an unverified video never ships; an empty cache with no network shows the "needs a connection" copy, never a fake list.
- No runtime AI calls. Catalog reads at most once a day plus pull to refresh.
- YouTube: play only through YouTube's embed (`youtube-nocookie.com`), never hotlink media; thumbnails from `i.ytimg.com`. Landscape overlays the collapsed capsule at the top leading edge, at most 44 points tall, never expanding; a side-rail layout stays behind `VideoWorkoutLayout.landscapeOverlay`.
- Copy has no em dashes. Commit messages are conventional commits with a body and no attribution trailer.
- Work happens in a worktree on branch `feat/workout-library` forked from `main` after the watch companion has merged (it consumes reps and sets). Never commit to `main`. Never use bare `git stash`.
- Package tests: `cd LifeOSKit && swift test --filter <Suite>`. App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build`. Migrations apply with `supabase db push` from the repo root (the project is already linked). The plain `sleep` command is blocked in the agent harness; wait with `perl -e 'select(undef,undef,undef,SECONDS)'`.
- The design preview launches with `--design-preview --page=<page>`; add pages for the new screens as described in Task 7.

## File map

| File | Responsibility |
|---|---|
| `supabase/migrations/20260915090000_workout_videos.sql` (new) | Table, RLS, grants. |
| `supabase/migrations/20260915090100_workout_videos_seed.sql` (new) | Verified rows. |
| `scripts/catalog/catalog.json` (new) | The human-curated list the seed is generated from. |
| `scripts/catalog/verify_lib.ts`, `verify.ts`, `verify_lib_test.ts` (new) | oEmbed verification and SQL generation. |
| `LifeOSKit/Sources/Persistence/CatalogVideo.swift` (new) | Cached catalog row. |
| `LifeOSKit/Sources/Persistence/UserGoals.swift`, `SourceRecords.swift`, `LifeOSContainer.swift` | Training preferences, `split` and `videoID` on workouts, schema registration. |
| `LifeOSKit/Sources/Integrations/WorkoutCatalogClient.swift` (new) | Supabase read and wire decoding. |
| `LifeOSKit/Sources/Integrations/CapacityInputs.swift` (new) | `todayCapacity(store:now:)` shared by the recorder and the planner. |
| `LifeOSKit/Sources/Sectors/WorkoutPlanner.swift` (new) | Pure planner. |
| `LIfeOS/Features/Workouts/Model/VideoWorkoutLayout.swift`, `ViewModel/WorkoutLibraryViewModel.swift`, `View/WorkoutLibraryScreen.swift`, `View/TrainingPreferencesSheet.swift`, `View/VideoWorkoutScreen.swift`, `View/YouTubePlayerView.swift` (new) | The feature. |
| `LIfeOS/Features/Health/View/FitnessSegmentView.swift`, `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`, `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`, `LIfeOS/App/RootView.swift` | Entry points and the pending video on the recorder. |
| `docs/design/workout-library/` (new) | Captures and report. |

---

### Task 1: Catalog table, curated list, verification script and seed

**Files:**
- Create: `supabase/migrations/20260915090000_workout_videos.sql`, `scripts/catalog/catalog.json`, `scripts/catalog/verify_lib.ts`, `scripts/catalog/verify_lib_test.ts`, `scripts/catalog/verify.ts`, `supabase/migrations/20260915090100_workout_videos_seed.sql`

**Interfaces:**
- Produces: table `public.workout_videos` (spec 3.1); `verify_lib.ts` exports `titleMatches(rowTitle, oembedTitle)`, `durationPlausible(title, durationS)`, `rowToSQL(row, verifiedAt)`, `parseCatalog(json)`.

- [ ] **Step 1: Write the failing Deno test**

Create `scripts/catalog/verify_lib_test.ts`:

```ts
import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { durationPlausible, parseCatalog, rowToSQL, titleMatches } from "./verify_lib.ts";

Deno.test("a row title must be a prefix of the oEmbed title, case and punctuation aside", () => {
  assertEquals(titleMatches("30 Min Pull Day", "30 MIN PULL DAY | Back & Biceps"), true);
  assertEquals(titleMatches("30 Min Push Day", "30 MIN PULL DAY | Back & Biceps"), false);
});

Deno.test("a stated length in the title must be within ten percent of the duration", () => {
  assertEquals(durationPlausible("30 Min Pull Day", 1780), true);
  assertEquals(durationPlausible("30 Min Pull Day", 2400), false);
  assertEquals(durationPlausible("Pull Day", 2400), true);
});

Deno.test("a row becomes one insert with arrays and a verified timestamp", () => {
  const sql = rowToSQL({
    youtube_id: "abc123XYZ_-", title: "30 Min Pull Day", channel: "Caroline Girvan", duration_s: 1780,
    goal: ["strength", "hypertrophy"], split: "pull", muscles: ["back", "biceps"], equipment: ["dumbbells"], intensity: 2,
  }, "2026-09-15T09:00:00Z");
  assertEquals(sql.includes("'abc123XYZ_-'"), true);
  assertEquals(sql.includes("array['strength','hypertrophy']"), true);
  assertEquals(sql.includes("'2026-09-15T09:00:00Z'"), true);
});

Deno.test("the catalog rejects unknown vocabulary and bad ids", () => {
  assertThrows(() => parseCatalog(JSON.stringify([{ youtube_id: "short", title: "x", channel: "c", duration_s: 60, goal: ["strength"], split: "push", muscles: [], equipment: [], intensity: 2 }])));
  assertThrows(() => parseCatalog(JSON.stringify([{ youtube_id: "abc123XYZ_-", title: "x", channel: "c", duration_s: 60, goal: ["cardio"], split: "push", muscles: [], equipment: [], intensity: 2 }])));
  assertEquals(parseCatalog(JSON.stringify([{ youtube_id: "abc123XYZ_-", title: "x", channel: "c", duration_s: 60, goal: ["strength"], split: "push", muscles: [], equipment: ["none"], intensity: 2 }])).length, 1);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd scripts/catalog && deno test 2>&1 | tail -3`
Expected: module not found for `./verify_lib.ts`.

- [ ] **Step 3: Write the library, the script, the table**

Create `scripts/catalog/verify_lib.ts`:

```ts
export const GOALS = ["strength", "hypertrophy", "endurance", "mobility"] as const;
export const SPLITS = ["push", "pull", "legs", "upper", "lower", "full", "core", "arms", "chest", "back", "shoulders", "mobility", "cardio"] as const;
export const EQUIPMENT = ["none", "dumbbells", "barbell", "bands", "machine", "kettlebell"] as const;

export interface CatalogRow {
  youtube_id: string; title: string; channel: string; duration_s: number;
  goal: string[]; split: string; muscles: string[]; equipment: string[]; intensity: number;
}

const ID = /^[A-Za-z0-9_-]{11}$/;

export function parseCatalog(json: string): CatalogRow[] {
  const rows = JSON.parse(json) as CatalogRow[];
  for (const row of rows) {
    if (!ID.test(row.youtube_id)) throw new Error(`bad id ${row.youtube_id}`);
    if (!row.goal.length || row.goal.some((g) => !(GOALS as readonly string[]).includes(g))) throw new Error(`bad goal in ${row.youtube_id}`);
    if (!(SPLITS as readonly string[]).includes(row.split)) throw new Error(`bad split in ${row.youtube_id}`);
    if (row.equipment.some((e) => !(EQUIPMENT as readonly string[]).includes(e))) throw new Error(`bad equipment in ${row.youtube_id}`);
    if (!Number.isInteger(row.intensity) || row.intensity < 1 || row.intensity > 3) throw new Error(`bad intensity in ${row.youtube_id}`);
    if (!Number.isInteger(row.duration_s) || row.duration_s <= 0) throw new Error(`bad duration in ${row.youtube_id}`);
  }
  const ids = new Set(rows.map((r) => r.youtube_id));
  if (ids.size !== rows.length) throw new Error("duplicate id");
  return rows;
}

const normalise = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

export function titleMatches(rowTitle: string, oembedTitle: string): boolean {
  return normalise(oembedTitle).startsWith(normalise(rowTitle));
}

export function durationPlausible(title: string, durationS: number): boolean {
  const stated = /(\d+)\s*min/i.exec(title);
  if (!stated) return true;
  const seconds = Number(stated[1]) * 60;
  return Math.abs(durationS - seconds) <= seconds * 0.1;
}

const quote = (s: string) => `'${s.replace(/'/g, "''")}'`;
const array = (items: string[]) => items.length ? `array[${items.map(quote).join(",")}]` : "'{}'";

export function rowToSQL(row: CatalogRow, verifiedAt: string): string {
  return `insert into public.workout_videos (youtube_id, title, channel, duration_s, goal, split, muscles, equipment, intensity, verified_at) values (` +
    `${quote(row.youtube_id)}, ${quote(row.title)}, ${quote(row.channel)}, ${row.duration_s}, ${array(row.goal)}, ${quote(row.split)}, ` +
    `${array(row.muscles)}, ${array(row.equipment)}, ${row.intensity}, ${quote(verifiedAt)}) on conflict (youtube_id) do update set ` +
    `title = excluded.title, channel = excluded.channel, duration_s = excluded.duration_s, goal = excluded.goal, split = excluded.split, ` +
    `muscles = excluded.muscles, equipment = excluded.equipment, intensity = excluded.intensity, verified_at = excluded.verified_at, updated_at = now();`;
}
```

Create `scripts/catalog/verify.ts`:

```ts
// Verifies every catalog row against YouTube's keyless oEmbed endpoint and
// writes the seed migration. Run: deno run --allow-net --allow-read --allow-write scripts/catalog/verify.ts
import { durationPlausible, parseCatalog, rowToSQL, titleMatches } from "./verify_lib.ts";

const rows = parseCatalog(await Deno.readTextFile("scripts/catalog/catalog.json"));
const verifiedAt = new Date().toISOString();
const failures: string[] = [];
const statements: string[] = [];
for (const row of rows) {
  const url = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${row.youtube_id}&format=json`;
  const response = await fetch(url);
  if (!response.ok) { failures.push(`${row.youtube_id}: oEmbed ${response.status}`); continue; }
  const body = await response.json() as { title: string; author_name: string };
  if (!titleMatches(row.title, body.title)) failures.push(`${row.youtube_id}: title "${body.title}" does not start with "${row.title}"`);
  if (!durationPlausible(row.title, row.duration_s)) failures.push(`${row.youtube_id}: duration ${row.duration_s}s disagrees with the title`);
  if (body.author_name.toLowerCase() !== row.channel.toLowerCase()) failures.push(`${row.youtube_id}: channel is "${body.author_name}", not "${row.channel}"`);
  statements.push(rowToSQL(row, verifiedAt));
}
if (failures.length) { console.error(failures.join("\n")); Deno.exit(1); }
const header = "-- Generated by scripts/catalog/verify.ts. Edit scripts/catalog/catalog.json and rerun; do not edit by hand.\n";
await Deno.writeTextFile("supabase/migrations/20260915090100_workout_videos_seed.sql", header + statements.join("\n") + "\n");
console.log(`verified ${rows.length} videos`);
```

Create `supabase/migrations/20260915090000_workout_videos.sql` with the SQL from spec 3.1 verbatim, preceded by a comment explaining the read-only policy.

- [ ] **Step 4: Curate `catalog.json`**

Curate about 60 rows meeting spec 3.2's coverage: for each channel named there, open the channel's videos page in a browser (or use web search), pick follow-along sessions whose titles name the split and length, copy the 11-character id from the URL, read the duration from the page, and tag goal, split, muscles, equipment and intensity (1 beginner or low impact, 2 moderate, 3 hard). Enter the `title` as the first words of the video's real title (the verifier checks the prefix) and `channel` as the channel's display name exactly. Do not invent ids or durations; every row must pass the verifier. A row that fails is removed or corrected, never forced.

Coverage check (run after verify): `deno eval` a count per split from `catalog.json` and confirm push, pull, legs, upper, lower, full at least 6; core, arms, chest, back, shoulders at least 3; mobility, cardio at least 5.

- [ ] **Step 5: Run the tests, the verifier, and apply the migrations**

Run: `cd scripts/catalog && deno test 2>&1 | tail -3` (4 tests pass). From the repo root: `deno run --allow-net --allow-read --allow-write scripts/catalog/verify.ts` (prints `verified N videos`, writes the seed). Then `supabase db push` and confirm with `supabase db query "select split, count(*) from public.workout_videos group by 1 order by 1"` (or the dashboard) that the counts match the coverage check.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260915090000_workout_videos.sql supabase/migrations/20260915090100_workout_videos_seed.sql scripts/catalog
git commit -m "feat(catalog): a verified table of curated workout videos

A read-only table for signed-in users, a curated list tagged by goal,
split, muscles, equipment and intensity, and a keyless oEmbed verifier
that generates the seed so no unverified id ever ships."
```

---

### Task 2: Persistence: cache model, preferences, workout columns

**Files:**
- Create: `LifeOSKit/Sources/Persistence/CatalogVideo.swift`
- Modify: `LifeOSKit/Sources/Persistence/UserGoals.swift`, `LifeOSKit/Sources/Persistence/SourceRecords.swift`, `LifeOSKit/Sources/Persistence/LifeOSContainer.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/CatalogVideoTests.swift` (new)

**Interfaces:**
- Produces: `@Model public final class CatalogVideo` (fields mirror the table; `thumbnailURL: URL`), `CatalogStore.upsert(_ rows: [CatalogVideoRow], context:)` and `CatalogStore.all(context:)`, `public struct CatalogVideoRow: Codable, Sendable, Equatable` (the wire shape, decoded with snake_case keys), `UserGoals.trainingGoal: String?`, `equipmentRaw: [String]`, `sessionMinutes: Int?`, `WorkoutRecord.split: String?`, `WorkoutRecord.videoID: String?`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import Persistence

struct CatalogVideoTests {
    @Test @MainActor func upsertIsIdempotentAndRemovesMissingRows() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let a = CatalogVideoRow(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C", durationS: 1800, goal: ["strength"], split: "push", muscles: [], equipment: ["none"], intensity: 2, verifiedAt: .now)
        let b = CatalogVideoRow(youtubeID: "bbbbbbbbbbb", title: "B", channel: "C", durationS: 1200, goal: ["mobility"], split: "mobility", muscles: [], equipment: [], intensity: 1, verifiedAt: .now)
        try CatalogStore.upsert([a, b], context: context)
        try CatalogStore.upsert([a, b], context: context)
        #expect(try CatalogStore.all(context: context).count == 2)
        try CatalogStore.upsert([a], context: context)
        let rows = try CatalogStore.all(context: context)
        #expect(rows.count == 1 && rows.first?.youtubeID == "aaaaaaaaaaa")
        #expect(rows.first?.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg")
    }

    @Test func goalsAndWorkoutColumnsDefaultToAbsent() {
        let goals = UserGoals()
        #expect(goals.trainingGoal == nil && goals.equipmentRaw.isEmpty && goals.sessionMinutes == nil)
        let row = WorkoutRecord(externalID: "x", start: .now, durationMinutes: 1, activityName: "Strength")
        #expect(row.split == nil && row.videoID == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: write the code**

`CatalogVideo.swift`:

```swift
import Foundation
import SwiftData

/// The wire row, snake_case on the server, decoded by the client.
public struct CatalogVideoRow: Codable, Sendable, Equatable {
    public var youtubeID: String, title: String, channel: String, durationS: Int
    public var goal: [String], split: String, muscles: [String], equipment: [String], intensity: Int, verifiedAt: Date
    enum CodingKeys: String, CodingKey {
        case youtubeID = "youtube_id", title, channel, durationS = "duration_s", goal, split, muscles, equipment, intensity, verifiedAt = "verified_at"
    }
    public init(youtubeID: String, title: String, channel: String, durationS: Int, goal: [String], split: String, muscles: [String], equipment: [String], intensity: Int, verifiedAt: Date) {
        self.youtubeID = youtubeID; self.title = title; self.channel = channel; self.durationS = durationS; self.goal = goal
        self.split = split; self.muscles = muscles; self.equipment = equipment; self.intensity = intensity; self.verifiedAt = verifiedAt
    }
}

/// A cached catalog row. The server is the source of truth; a refresh
/// replaces the set, so a video pulled from the catalog disappears here.
@Model
public final class CatalogVideo {
    #Unique<CatalogVideo>([\.youtubeID])
    public var youtubeID: String
    public var title: String
    public var channel: String
    public var durationS: Int
    public var goal: [String]
    public var split: String
    public var muscles: [String]
    public var equipment: [String]
    public var intensity: Int
    public var verifiedAt: Date
    public var cachedAt: Date

    public init(_ row: CatalogVideoRow, cachedAt: Date = .now) {
        youtubeID = row.youtubeID; title = row.title; channel = row.channel; durationS = row.durationS; goal = row.goal
        split = row.split; muscles = row.muscles; equipment = row.equipment; intensity = row.intensity; verifiedAt = row.verifiedAt
        self.cachedAt = cachedAt
    }
    public var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(youtubeID)/hqdefault.jpg")! }
    public var durationMinutes: Int { Int((Double(durationS) / 60).rounded()) }
}

public enum CatalogStore {
    public static func all(context: ModelContext) throws -> [CatalogVideo] {
        try context.fetch(FetchDescriptor<CatalogVideo>(sortBy: [SortDescriptor(\.title)]))
    }
    /// Replace the cache with `rows`: update matches, insert new, delete absent.
    public static func upsert(_ rows: [CatalogVideoRow], context: ModelContext, now: Date = .now) throws {
        let existing = try all(context: context)
        let incoming = Dictionary(uniqueKeysWithValues: rows.map { ($0.youtubeID, $0) })
        for video in existing {
            if let row = incoming[video.youtubeID] {
                video.title = row.title; video.channel = row.channel; video.durationS = row.durationS; video.goal = row.goal
                video.split = row.split; video.muscles = row.muscles; video.equipment = row.equipment; video.intensity = row.intensity
                video.verifiedAt = row.verifiedAt; video.cachedAt = now
            } else { context.delete(video) }
        }
        let present = Set(existing.map(\.youtubeID))
        for row in rows where !present.contains(row.youtubeID) { context.insert(CatalogVideo(row, cachedAt: now)) }
        try context.save()
    }
}
```

`UserGoals`: add `public var trainingGoal: String?`, `public var equipmentRaw: [String] = []`, `public var sessionMinutes: Int?` (defaults in the initialiser: `trainingGoal: String? = nil, equipmentRaw: [String] = [], sessionMinutes: Int? = nil`). `WorkoutRecord`: add `public var split: String?` and `public var videoID: String?`. `LifeOSContainer.schema`: append `CatalogVideo.self`.

- [ ] **Step 4: Run tests** (`swift test --filter "CatalogVideoTests|PersistenceTests"`), all pass. **Step 5: Commit** `feat(persistence): catalog cache, training preferences, workout split and video`.

---

### Task 3: Catalog client

**Files:**
- Create: `LifeOSKit/Sources/Integrations/WorkoutCatalogClient.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/WorkoutCatalogClientTests.swift` (new)

**Interfaces:**
- Produces: `public struct WorkoutCatalogClient: Sendable { init(baseURL:anonKey:session:); func videos(accessToken:) async throws -> [CatalogVideoRow]; static func request(baseURL:anonKey:accessToken:) -> URLRequest; static func decode(_ data: Data) throws -> [CatalogVideoRow] }`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
import Persistence
@testable import Integrations

struct WorkoutCatalogClientTests {
    @Test func requestCarriesBothKeysAndSelectsEverything() {
        let request = WorkoutCatalogClient.request(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon", accessToken: "tok")
        #expect(request.url?.absoluteString == "https://x.supabase.co/rest/v1/workout_videos?select=*&order=updated_at.asc")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }
    @Test func decodesArraysAndKeepsUnknownSplitAsText() throws {
        let json = #"[{"youtube_id":"abcdefghijk","title":"T","channel":"C","duration_s":1800,"goal":["strength"],"split":"glutes","muscles":["glutes"],"equipment":["bands"],"intensity":2,"verified_at":"2026-09-15T09:00:00Z","updated_at":"2026-09-15T09:00:00Z"}]"#
        let rows = try WorkoutCatalogClient.decode(Data(json.utf8))
        #expect(rows.count == 1 && rows[0].split == "glutes" && rows[0].equipment == ["bands"] && rows[0].durationS == 1800)
    }
}
```

- [ ] **Step 2: Fail, then write**

```swift
import Foundation
import Persistence

/// Reads the curated catalog. Read only: the table grants nothing else.
public struct WorkoutCatalogClient: Sendable {
    private let baseURL: URL, anonKey: String, session: URLSession
    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) { self.baseURL = baseURL; self.anonKey = anonKey; self.session = session }

    public static func request(baseURL: URL, anonKey: String, accessToken: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/workout_videos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "select", value: "*"), .init(name: "order", value: "updated_at.asc")]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
    public static func decode(_ data: Data) throws -> [CatalogVideoRow] { try SocialAPI.decoder.decode([CatalogVideoRow].self, from: data) }

    public func videos(accessToken: String) async throws -> [CatalogVideoRow] {
        let (data, response) = try await session.data(for: Self.request(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SocialAPIError.status((response as? HTTPURLResponse)?.statusCode ?? -1, message: SocialAPI.serverMessage(data))
        }
        return try Self.decode(data)
    }
}
```

`SocialAPI.decoder` and `serverMessage` are `static` inside `Integrations`; if they are `private`, make them `static` internal. Tests pass; commit `feat(catalog): a read-only client for the workout catalog`.

---

### Task 4: Planner

**Files:**
- Create: `LifeOSKit/Sources/Sectors/WorkoutPlanner.swift`, `LifeOSKit/Tests/SectorsTests/WorkoutPlannerTests.swift`

- [ ] **Step 1: Failing tests** covering every rule in spec 4.2:

```swift
import Foundation
import Testing
@testable import Sectors

struct WorkoutPlannerTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var wednesday: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9))! }
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: wednesday)! }

    @Test func redBatteryIsMobility() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 45, batteryPercent: 20, recentSplits: [], now: wednesday, calendar: calendar)
        #expect(plan.split == "mobility" && plan.maxIntensity == 1 && plan.minutes == 45)
    }
    @Test func strengthRotatesAfterTheMostRecentSplit() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: nil, batteryPercent: 80,
                                       recentSplits: [(day(2), "push"), (day(5), "legs")], now: wednesday, calendar: calendar)
        #expect(plan.split == "pull" && plan.maxIntensity == 3 && plan.minutes == 30)
        #expect(plan.reason == "You did push on Monday, so today is pull.")
        let afterLegs = WorkoutPlanner.plan(goal: "hypertrophy", sessionMinutes: 40, batteryPercent: 50, recentSplits: [(day(1), "legs")], now: wednesday, calendar: calendar)
        #expect(afterLegs.split == "push" && afterLegs.maxIntensity == 2)
    }
    @Test func firstSessionOfTheWeekIsPush() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 30, batteryPercent: 70, recentSplits: [(day(9), "pull")], now: wednesday, calendar: calendar)
        #expect(plan.split == "push" && plan.reason == "First session this week: push.")
    }
    @Test func enduranceAndMobilityGoals() {
        #expect(WorkoutPlanner.plan(goal: "endurance", sessionMinutes: 30, batteryPercent: 50, recentSplits: [], now: wednesday, calendar: calendar).split == "cardio")
        #expect(WorkoutPlanner.plan(goal: "endurance", sessionMinutes: 30, batteryPercent: 50, recentSplits: [], now: wednesday, calendar: calendar).maxIntensity == 2)
        #expect(WorkoutPlanner.plan(goal: "mobility", sessionMinutes: 20, batteryPercent: 90, recentSplits: [], now: wednesday, calendar: calendar).split == "mobility")
    }
    @Test func unknownGoalIsFullBody() {
        let plan = WorkoutPlanner.plan(goal: nil, sessionMinutes: nil, batteryPercent: nil, recentSplits: [], now: wednesday, calendar: calendar)
        #expect(plan.split == "full" && plan.maxIntensity == 2 && plan.reason == "Set a goal for a plan built around you.")
    }
    @Test func unknownBatteryAfterAHardDayIsMobility() {
        let plan = WorkoutPlanner.plan(goal: "strength", sessionMinutes: 30, batteryPercent: nil, recentSplits: [(day(1), "legs")], now: wednesday, calendar: calendar)
        #expect(plan.split == "mobility")
    }
}
```

- [ ] **Step 2: Fail, then write**

```swift
import Foundation

public struct TrainingPlan: Equatable, Sendable {
    public let split: String
    public let minutes: Int
    public let maxIntensity: Int
    public let reason: String
    public init(split: String, minutes: Int, maxIntensity: Int, reason: String) { self.split = split; self.minutes = minutes; self.maxIntensity = maxIntensity; self.reason = reason }
}

/// Today's session from what the person wants, how much they have, and what
/// they did. Pure, so every rule is a test.
public enum WorkoutPlanner {
    static let rotation = ["push", "pull", "legs"]

    public static func plan(goal: String?, sessionMinutes: Int?, batteryPercent: Int?,
                            recentSplits: [(date: Date, split: String)], now: Date, calendar: Calendar = .current) -> TrainingPlan {
        let minutes = sessionMinutes ?? 30
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let recent = recentSplits.filter { $0.date >= weekAgo && $0.date <= now }.sorted { $0.date > $1.date }
        let hardYesterday = recent.first.map { calendar.isDate($0.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!) && rotation.contains($0.split) } ?? false
        let cap: Int = { switch batteryPercent { case .some(let b) where b >= 67: return 3; case .some(let b) where b >= 34: return 2; case .some: return 1; case .none: return 2 } }()

        if (batteryPercent ?? 100) <= 33 || (batteryPercent == nil && hardYesterday) {
            return TrainingPlan(split: "mobility", minutes: minutes, maxIntensity: 1, reason: "Recovery is low today, so this is a mobility day.")
        }
        switch goal {
        case "mobility": return TrainingPlan(split: "mobility", minutes: minutes, maxIntensity: cap, reason: "A mobility day, as you asked for.")
        case "endurance": return TrainingPlan(split: "cardio", minutes: minutes, maxIntensity: cap, reason: "Endurance today, paced by your battery.")
        case "strength", "hypertrophy":
            if let last = recent.first(where: { rotation.contains($0.split) }) {
                let next = rotation[(rotation.firstIndex(of: last.split)! + 1) % rotation.count]
                let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: last.date) - 1]
                return TrainingPlan(split: next, minutes: minutes, maxIntensity: cap, reason: "You did \(last.split) on \(weekday), so today is \(next).")
            }
            return TrainingPlan(split: "push", minutes: minutes, maxIntensity: cap, reason: "First session this week: push.")
        default:
            return TrainingPlan(split: "full", minutes: minutes, maxIntensity: cap, reason: "Set a goal for a plan built around you.")
        }
    }
}
```

Tests pass; commit `feat(sectors): a planner for today's workout`.

---

### Task 5: Shared capacity inputs and the recorder's pending video

**Files:**
- Create: `LifeOSKit/Sources/Integrations/CapacityInputs.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`

- [ ] **Step 1:** Move the body of `ActivityRecorder.loadCapacity()` into `public enum CapacityInputs { public static func todayCapacity(store: MetricsStore, now: Date = .now, calendar: Calendar = .current) -> Capacity? }` in `Integrations` (it maps the last nine days of `DailyMetrics` rows into `RecoveryDay` and calls `CapacityMath.capacity`). The recorder's `loadCapacity()` becomes `context.map { CapacityInputs.todayCapacity(store: MetricsStore(context: $0)) } ?? nil`.
- [ ] **Step 2:** Add to the recorder `var pendingVideoID: String?` and `var pendingSplit: String?`; in `saveFinished()` after `row.distanceMeters = distance` add `row.videoID = pendingVideoID; row.split = pendingSplit`; clear both in `discard()`. Add `private(set) var followingTitle: String?` set by the player screen through `var following: (title: String, channel: String)?` for the in-session line.
- [ ] **Step 3:** Add a recorder check: set `pendingVideoID = "abcdefghijk"; pendingSplit = "pull"` before `finish()` on a fresh recorder and check the saved record carries both. Build, run the checks, commit `refactor(activity): share capacity inputs and stamp videos on workouts`.

---

### Task 6: Library view model, screens, entry points

**Files:**
- Create: `LIfeOS/Features/Workouts/Model/VideoWorkoutLayout.swift`, `LIfeOS/Features/Workouts/ViewModel/WorkoutLibraryViewModel.swift`, `LIfeOS/Features/Workouts/View/WorkoutLibraryScreen.swift`, `LIfeOS/Features/Workouts/View/TrainingPreferencesSheet.swift`, `LIfeOS/Features/Workouts/View/WorkoutVideoRow.swift`
- Modify: `LIfeOS/Features/Health/View/FitnessSegmentView.swift`, `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`, `LIfeOS/App/RootView.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class WorkoutLibraryViewModel` with `attach(_ context:)`, `refreshIfDue(force:)`, `plan: TrainingPlan?`, `videos: [CatalogVideo]`, `filtered: [CatalogVideo]`, `splitFilter: String?`, `durationBand: DurationBand?`, `needsPreferences: Bool`, `savePreferences(goal:equipment:minutes:)`, `status: String?`, `batteryLine: String?`.

- [ ] **Step 1:** Write the view model. `attach` loads `UserGoals` (creating the singleton row if absent the way other view models do), `CatalogStore.all`, the last 7 days of `WorkoutRecord` with a non-nil `split`, and `CapacityInputs.todayCapacity`; computes `plan` with `WorkoutPlanner.plan(goal:sessionMinutes:batteryPercent:recentSplits:now:)`. `refreshIfDue(force:)` calls `WorkoutCatalogClient(baseURL: AppConfig.supabaseURL!, anonKey: AppConfig.supabaseAnonKey!).videos(accessToken:)` with the token from `KeychainAuthSessionStore().load()?.accessToken` when the newest `cachedAt` is older than a day or `force`, then `CatalogStore.upsert`; failures set `status` ("The library needs a connection the first time." when the cache is empty, otherwise "Showing the last catalog we downloaded.") and never clear the cache. `filtered` applies the plan's split, intensity cap and minutes ± 15, widening as the spec says and setting `status` to "Widened to any length." or "Widened to any split for your goal." `batteryLine` reuses the readout vocabulary: "Battery 67% · up to zone 4" from `capacity` and `EffortCeiling`.
- [ ] **Step 2:** Screens. `WorkoutLibraryScreen(model:onOpen: (CatalogVideo) -> Void)`: the Today card (gradient `ModuleHue.activity`, title `plan.split.capitalized + " day"`, reason, `batteryLine`, minutes), filter chips, `WorkoutVideoRow` list (AsyncImage thumbnail 16:9 in a 22 point rounded rectangle with an SF Symbol fallback, title two lines, channel, "\(durationMinutes) min", intensity dots, split and equipment chips), pull to refresh, toolbar button to edit preferences, and `.sheet(isPresented: $model.needsPreferences) { TrainingPreferencesSheet(model: model) }`. `TrainingPreferencesSheet`: three pickers (goal from the four values, equipment multi-select from six values, minutes 15 to 90 in steps of 15) and Save.
- [ ] **Step 3:** Entry points. `FitnessSegmentView.trainingCard` gains a `NavigationLink { WorkoutLibraryScreen(...) }` row "Plan today's workout ›" showing `plan.split` and minutes (the segment receives a `WorkoutLibraryViewModel` from `RootView`, attached in `attachAll()`). `BeginActivityScreen` pre-session state gains, above the picker, a bordered button "Follow a video" that pushes `WorkoutLibraryScreen` inside its `NavigationStack`; opening a video pushes `VideoWorkoutScreen` (Task 7). `RootView` creates `@State private var library = WorkoutLibraryViewModel()` and attaches it.
- [ ] **Step 4:** Add design preview pages `--page=library` (fixture with six `CatalogVideo` rows inserted into the in-memory container, goals set to strength, two recent splits) and `--page=library-empty`. Build, capture `library-iphone.png`, `library-iphone-dark.png`, `library-ipad.png`, `library-empty.png` into `docs/design/workout-library/`, inspect. Commit `feat(workouts): the library with today's plan`.

---

### Task 7: Player screen

**Files:**
- Create: `LIfeOS/Features/Workouts/View/YouTubePlayerView.swift`, `LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift`
- Modify: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` (the "Following:" line), `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`

- [ ] **Step 1: `YouTubePlayerView`**

```swift
import SwiftUI
import WebKit

/// YouTube's own player, privacy-enhanced domain, inline. No JavaScript
/// bridge: the person taps YouTube's play button, which is the one gesture
/// the embed needs. `onLoadFailure` shows the "Open in YouTube" fallback.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    var onLoadFailure: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .black; view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1")!
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onLoadFailure: onLoadFailure) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoadFailure: () -> Void
        init(onLoadFailure: @escaping () -> Void) { self.onLoadFailure = onLoadFailure }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onLoadFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onLoadFailure() }
    }
}
```

- [ ] **Step 2: `VideoWorkoutLayout` and `VideoWorkoutScreen`**

`VideoWorkoutLayout`: `enum VideoWorkoutLayout { static let landscapeOverlay = true }`.

`VideoWorkoutScreen(video: CatalogVideo, model: ActivityRecorder)`: reads `verticalSizeClass`. Portrait: `VStack` of the player (`.aspectRatio(16/9, contentMode: .fit)`), then before Start: title, channel, duration, split and intensity chips, and a primary "Start this workout" button that sets `model.selection = activity(for: video.split)`, `model.pendingVideoID = video.youtubeID`, `model.pendingSplit = video.split`, `model.following = (video.title, video.channel)` and `await model.start()`; after Start: `SessionHUD(readout:activity:zonesAvailable:isExpanded:onAddRep:onNextSet:)`, the controls (pause or resume, finish and save, discard, reusing the same buttons as Begin Activity by extracting `ActivityControls` into its own view in `Features/Activity/View/ActivityControls.swift`), and the "Open in YouTube" link when the player failed (`openURL(URL(string: "https://www.youtube.com/watch?v=\(video.youtubeID)")!)`). Landscape (compact vertical size class) and `landscapeOverlay`: `ZStack(alignment: .topLeading)` with the player filling the screen and, when a session runs, the collapsed capsule (`showsTimer: true`, `isExpanded: .constant(false)`) with `.padding(16)` and `.frame(maxHeight: 44)`; a tap on it opens a controls sheet. When `landscapeOverlay` is false: an `HStack` of the player and a 180 point rail with the HUD and controls. `activity(for:)`: cardio → `.other`, mobility → `.yoga`, everything else → `.strength`.

In `BeginActivityScreen.liveHero`, under the status pill, add `if let following = model.following { Text("Following: \(following.title) · \(following.channel)").font(LifeOSType.caption).opacity(0.85).lineLimit(1) }`.

- [ ] **Step 3: Captures.** Add `--page=player` (fixture video, `--live` starts the session) and capture `player-portrait.png`, `player-portrait-live.png`, and in landscape (`xcrun simctl` cannot rotate; with the Simulator frontmost run `osascript -e 'tell application "System Events" to key code 123 using command down'`, which is Command and Left Arrow, then capture) `player-landscape-live.png`. Inspect: the capsule sits at the top leading edge, 44 points, away from the player's control bar. Spot-check five seed videos play in the simulator's embed (network required) and record which.
- [ ] **Step 4:** Build, commit `feat(workouts): play a video with the live HUD`.

---

### Task 8: Design QA report and spec status

- [ ] Write `docs/design/workout-library/report.md` in `design-qa.md`'s order, referencing every capture, listing the five spot-checked videos and any that failed to embed (and were then removed from `catalog.json` with the verifier rerun), the Deno and Swift test totals, and the checks output. Update the spec status line to `**Status:** implemented on feat/workout-library, see docs/design/workout-library/report.md`. Run the full package suite and the app build. Commit `docs(workouts): QA report for the workout library`.

## Self-review

**Spec coverage.** 3.1 table: Task 1. 3.2 curation and verification: Task 1 (script, tests, coverage check). 3.3 client and cache: Tasks 2 and 3. 4.1 preferences: Tasks 2 and 6 (sheet). 4.2 planner and widening: Tasks 4 and 6. 5.1 library: Task 6. 5.2 and 5.3 player and landscape flag: Task 7. 5.4 entry points and the "Following" line: Tasks 6 and 7. 6 data flow: Task 5 (`CapacityInputs`), Task 6. 7 tests and QA: Tasks 1 to 4, 8. 8 risks: the "Open in YouTube" fallback in Task 7, spot checks in Task 8.

**Placeholders.** Curation in Task 1 is a procedure with a verifier and a coverage check, not a list to invent; the migration timestamps are fixed.

**Type consistency.** `CatalogVideoRow(youtubeID:...)`, `CatalogStore.upsert(_:context:)`/`all(context:)`, `WorkoutCatalogClient.videos(accessToken:)`, `WorkoutPlanner.plan(goal:sessionMinutes:batteryPercent:recentSplits:now:calendar:)`, `TrainingPlan(split:minutes:maxIntensity:reason:)`, `CapacityInputs.todayCapacity(store:now:calendar:)`, `ActivityRecorder.pendingVideoID/pendingSplit/following`, `VideoWorkoutLayout.landscapeOverlay` are used consistently across tasks.
