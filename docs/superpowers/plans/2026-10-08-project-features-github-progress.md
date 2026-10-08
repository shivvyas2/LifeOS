# Project Features and GitHub Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each project a plan of features whose stage (planned, building, in review, done) is read from GitHub branches and PRs, with a GitHub view of commits, branches and PRs, and a LIFO-drafted feature list.

**Architecture:** A new synced `FeatureRecord` / `project_features` table follows the milestone path through `ProjectsStore` and `ProjectSync`. GitHub is read on the phone (two GraphQL queries for branches and PRs, REST for history and a feature's commits) by `GitHubProjectSource`; a pure `FeatureStageResolver` turns that into a stage that the phone writes onto the feature and syncs. LIFO gains a `plan` task in `lifo-agent`, called through the existing `RemoteWire`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, XCTest UI tests, Supabase Postgres + RLS, Deno edge functions, Anthropic SDK (`claude-opus-5-5`), GitHub REST and GraphQL.

**Spec:** `docs/superpowers/specs/2026-10-08-project-features-github-progress-design.md`

## Global Constraints

- Every stored property on a SwiftData `@Model`, new or added, is optional or defaulted; installed stores must open.
- Server text limits are counted in Unicode scalars (`char_length`); trim on the phone with `ProjectsStore.limit(_:_:)`.
- Feature title 1–80, note ≤ 280, branch ≤ 255, stage_detail ≤ 80; stage one of `planned`, `building`, `review`, `done`.
- The app never writes to GitHub. The GitHub token never leaves the phone's Keychain.
- GitHub refresh: on open, every 5 minutes while a project view is on screen, on pull to refresh; in-memory cache per repo for 5 minutes.
- `plan` drafts: 10 × the task's `maxTokens` (6,000) = 60,000 tokens per person per day, in `lifo_usage` kind `plan`, separate from `chat`.
- Draft input caps: README 6,000 characters, 20 commit subjects, nudge 200 characters, whole prompt ≤ 12,000 characters.
- Model: `claude-opus-5-5` via the existing `MODEL` constant; no new model ids.
- Projects tab look: `brutalCard`, `BrutalProgress`, `brutalLabel`, uppercase heavy labels; colour only from `ProjectColour`.
- Commits: conventional (`feat(projects): ...`), no em dashes, no attribution trailers, never on `main`.
- Work in the worktree `.claude/worktrees/project-features` on branch `feat/project-features`; one PR per slice (cut `feat/project-features-github` and `feat/project-features-draft` from the previous slice's tip).
- Simulator ids: `xcrun simctl list devices available | grep -E "iPhone|iPad"`; use one iPhone and one iPad that are not in use by another session. A UI test run that reports `Executed 0 tests` means the file is not in the `LIfeOSUITests` target; register it (Task 4 Step 1).

## Review Focus

1. **A title made of emoji or accented letters near the limit**: it is cut to 80 scalars on the phone, so the server never refuses the row. Test in Task 2.
2. **A repo whose default branch is not `main`** (`master`, `develop`): stages compare against the real default branch. Test in Task 6.
3. **An empty repository** (no commits): history shows none and nothing errors (GitHub answers 409). Test in Task 6.
4. **A fork's PR from a branch with the same name as a feature's**: it does not move the feature. Test in Task 5.
5. **A branch name with `#`, `%` or spaces**: the compare URL is percent-encoded and still reaches the branch. Test in Task 6.

---

# Slice 1: Features and the Plan view

## Task 1: Server table `project_features`

**Files:**
- Create: `supabase/migrations/20261008120000_project_features.sql`

**Interfaces:**
- Produces: table `public.project_features` (columns `id, project_id, milestone_id, title, note, position, branch, stage, stage_detail, pr_number, stage_checked_at, updated_at, deleted_at`) and `public.project_tasks.feature_id uuid`.

- [ ] **Step 1: Write the migration**

```sql
-- Features: the plan between a project's scope and its tasks. Each may link
-- to a branch; its stage is worked out on a member's phone from GitHub and
-- written here, so members without access to the repo see it too. Same
-- membership rules as milestones.

create table public.project_features (
  id uuid primary key,
  project_id uuid not null references public.projects (id) on delete cascade,
  milestone_id uuid references public.project_milestones (id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  note text not null default '' check (char_length(note) <= 280),
  position integer not null default 0,
  branch text check (branch is null or char_length(branch) between 1 and 255),
  stage text not null default 'planned' check (stage in ('planned', 'building', 'review', 'done')),
  stage_detail text not null default '' check (char_length(stage_detail) <= 80),
  pr_number integer check (pr_number is null or pr_number > 0),
  stage_checked_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index project_features_project_idx on public.project_features (project_id, updated_at);

create trigger project_features_touch before insert or update on public.project_features
  for each row execute function public.touch_updated_at();

alter table public.project_features enable row level security;

create policy "members read features" on public.project_features
  for select to authenticated using (public.is_project_member(project_id));
create policy "members add features" on public.project_features
  for insert to authenticated with check (public.is_project_member(project_id));
create policy "members edit features" on public.project_features
  for update to authenticated using (public.is_project_member(project_id))
  with check (public.is_project_member(project_id));

alter table public.project_tasks
  add column feature_id uuid references public.project_features (id) on delete set null;
```

- [ ] **Step 2: Check it parses**

Run: `cd supabase && supabase db lint --schema public 2>&1 | tail -5` if Docker is running; otherwise read it against `20261007140000_projects.sql` lines 33–41 and 145–150 (the milestone table and policies it mirrors) and confirm column names and function names match exactly (`public.touch_updated_at`, `public.is_project_member`).
Expected: no errors, or a clean side-by-side read.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20261008120000_project_features.sql
git commit -m "feat(supabase): project features with membership checks"
```

## Task 2: `FeatureRecord`, its snapshot, and the store

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/ProjectRecords.swift` (add `FeatureRecord`, `FeatureSnapshot`; add `featureID` to `ProjectTaskRecord` and `ProjectTaskSnapshot`)
- Modify: `LifeOSKit/Sources/Persistence/ProjectRules.swift` (add `FeatureStage`, `FeatureProgress`)
- Modify: `LifeOSKit/Sources/Persistence/ProjectsStore.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift:28` (register `FeatureRecord.self`)
- Test: `LifeOSKit/Tests/PersistenceTests/FeaturesStoreTests.swift` (new)

**Interfaces:**
- Produces:
  - `public enum FeatureStage: String, CaseIterable, Sendable { case planned, building, review, done; var label: String }`
  - `public struct FeatureProgress: Equatable, Sendable { let done: Int; let total: Int; let counts: [FeatureStage: Int]; var fraction: Double; static func of(_ stages: [FeatureStage]) -> FeatureProgress }`
  - `@Model public final class FeatureRecord` with `id, projectID, milestoneID: UUID?, title, note, position, branch: String?, stage: String = "planned", stageDetail: String = "", prNumber: Int?, stageCheckedAt: Date?, updatedAt, syncedAt: Date?, deletedAt: Date?`
  - `public struct FeatureSnapshot: Identifiable, Equatable, Sendable` with `id, projectID, milestoneID, title, note, position, branch, stage: FeatureStage, stageDetail, prNumber, stageCheckedAt, openTasks: Int, doneTasks: Int`
  - `ProjectsStore`: `features(projectID:) -> [FeatureSnapshot]`, `feature(id:) -> FeatureSnapshot?`, `featureProgress(projectID:) -> FeatureProgress`, `createFeature(projectID:title:note:branch:milestoneID:) -> UUID`, `updateFeature(id:title:note:milestoneID:branch:)`, `moveFeature(id:to:)`, `deleteFeature(id:)`, `applyStage(featureID:stage:detail:prNumber:checkedAt:) -> Bool`, `applyRemoteFeature(...)`, and `updateTask(... featureID: UUID?? = nil ...)`.
  - `ProjectsStore.Pending.features: [FeatureRecord]`.
  - `ProjectTaskSnapshot.featureID: UUID?`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/PersistenceTests/FeaturesStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct FeaturesStoreTests {
    private let me = UUID()
    private func store() throws -> ProjectsStore {
        ProjectsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }
    private func project(_ store: ProjectsStore) throws -> UUID {
        try store.createProject(name: "LifeOS", scope: "Ship it", colour: "moss", ownerID: me)
    }

    @Test func featuresKeepTheirPlanOrder() throws {
        let store = try store()
        let p = try project(store)
        let a = try store.createFeature(projectID: p, title: "Sign in")
        let b = try store.createFeature(projectID: p, title: "Credit cards")
        let c = try store.createFeature(projectID: p, title: "Widgets")
        try store.moveFeature(id: c, to: 0)
        #expect(try store.features(projectID: p).map(\.id) == [c, a, b])
        #expect(try store.features(projectID: p).map(\.position) == [0, 1, 2])
    }

    @Test func aNewFeatureIsPlanned() throws {
        let store = try store()
        let p = try project(store)
        let id = try store.createFeature(projectID: p, title: "Sign in", note: "Apple and email")
        let feature = try #require(try store.feature(id: id))
        #expect(feature.stage == .planned)
        #expect(feature.stageDetail == "")
        #expect(feature.note == "Apple and email")
        #expect(feature.branch == nil)
    }

    /// Review Focus 1: the server counts scalars; a title it would refuse
    /// never leaves the phone.
    @Test func aLongEmojiTitleIsCutToEightyScalars() throws {
        let store = try store()
        let p = try project(store)
        let title = String(repeating: "👩🏽‍💻", count: 30)   // 4 scalars each
        let id = try store.createFeature(projectID: p, title: title)
        let saved = try #require(try store.feature(id: id)).title
        #expect(saved.unicodeScalars.count <= 80)
        #expect(saved.unicodeScalars.count == 80)
        try store.updateFeature(id: id, note: String(repeating: "é", count: 400))
        #expect(try #require(try store.feature(id: id)).note.unicodeScalars.count <= 280)
    }

    @Test func deletingAFeatureUnlinksItsTasks() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "Sign in")
        let t = try store.createTask(projectID: p, title: "Button")
        try store.updateTask(id: t, featureID: .some(f))
        #expect(try store.tasks(projectID: p).first?.featureID == f)
        try store.deleteFeature(id: f)
        #expect(try store.features(projectID: p).isEmpty)
        #expect(try store.tasks(projectID: p).first?.featureID == nil)
        #expect(try store.pending().features.contains { $0.id == f && $0.deletedAt != nil })
    }

    @Test func progressCountsDoneOverAll() throws {
        let store = try store()
        let p = try project(store)
        let a = try store.createFeature(projectID: p, title: "A")
        let b = try store.createFeature(projectID: p, title: "B")
        _ = try store.createFeature(projectID: p, title: "C")
        try store.applyStage(featureID: a, stage: .done, detail: "Merged", prNumber: 4, checkedAt: .now)
        try store.applyStage(featureID: b, stage: .review, detail: "PR #5 open", prNumber: 5, checkedAt: .now)
        let progress = try store.featureProgress(projectID: p)
        #expect(progress.done == 1 && progress.total == 3)
        #expect(progress.counts[.review] == 1 && progress.counts[.planned] == 1)
    }

    @Test func aFeatureCountsItsOwnTasks() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "Sign in")
        let a = try store.createTask(projectID: p, title: "A")
        let b = try store.createTask(projectID: p, title: "B", status: .done)
        try store.updateTask(id: a, featureID: .some(f))
        try store.updateTask(id: b, featureID: .some(f))
        let feature = try #require(try store.feature(id: f))
        #expect(feature.openTasks == 1 && feature.doneTasks == 1)
    }

    @Test func anUnchangedStageIsNotAnEdit() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "A")
        try store.markSynced(at: .now)
        let changed = try store.applyStage(featureID: f, stage: .planned, detail: "", prNumber: nil, checkedAt: .now)
        #expect(changed == false)
        #expect(try store.pending().features.isEmpty, "an unchanged stage would ping-pong between members")
        #expect(try #require(try store.feature(id: f)).stageCheckedAt != nil)
        #expect(try store.applyStage(featureID: f, stage: .building, detail: "2 commits · 1h ago", prNumber: nil, checkedAt: .now))
        #expect(try store.pending().features.map(\.id) == [f])
    }

    @Test func forgettingAProjectDropsItsFeatures() throws {
        let store = try store()
        let p = try project(store)
        _ = try store.createFeature(projectID: p, title: "A")
        try store.forgetProject(p)
        #expect(try store.features(projectID: p).isEmpty)
        #expect(try store.pending().features.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FeaturesStoreTests 2>&1 | tail -5`
Expected: build failure, `cannot find 'createFeature'` (and similar).

- [ ] **Step 3: Add the stage and progress types**

Append to `LifeOSKit/Sources/Persistence/ProjectRules.swift`:

```swift
/// Where a feature stands, worked out from its branch and PRs.
public enum FeatureStage: String, CaseIterable, Sendable {
    case planned, building, review, done

    public var label: String {
        switch self {
        case .planned: "PLANNED"
        case .building: "BUILDING"
        case .review: "IN REVIEW"
        case .done: "DONE"
        }
    }
}

/// Done features over all of them, and how many sit at each stage.
public struct FeatureProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int
    public let counts: [FeatureStage: Int]
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    public static func of(_ stages: [FeatureStage]) -> FeatureProgress {
        var counts: [FeatureStage: Int] = [:]
        for stage in stages { counts[stage, default: 0] += 1 }
        return FeatureProgress(done: counts[.done] ?? 0, total: stages.count, counts: counts)
    }
}
```

- [ ] **Step 4: Add the record and snapshot**

In `LifeOSKit/Sources/Persistence/ProjectRecords.swift`, add `public var featureID: UUID?` to `ProjectTaskRecord` directly under `milestoneID` (optional, so installed stores open). After `ProjectTaskRecord`, add:

```swift
@Model
public final class FeatureRecord {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    public var milestoneID: UUID?
    public var title: String = ""
    public var note: String = ""
    public var position: Int = 0
    public var branch: String?
    public var stage: String = "planned"
    public var stageDetail: String = ""
    public var prNumber: Int?
    public var stageCheckedAt: Date?
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, title: String, position: Int) {
        self.id = id; self.projectID = projectID; self.title = title; self.position = position
    }
}
```

Add `public let featureID: UUID?` to `ProjectTaskSnapshot` directly under `milestoneID`, and after `MilestoneSnapshot` add:

```swift
public struct FeatureSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let milestoneID: UUID?
    public let title: String
    public let note: String
    public let position: Int
    public let branch: String?
    public let stage: FeatureStage
    public let stageDetail: String
    public let prNumber: Int?
    public let stageCheckedAt: Date?
    public let openTasks: Int
    public let doneTasks: Int
}
```

In `ProjectsStore.snapshot(_:projects:)` (near line 392) pass `featureID: row.featureID` in the `ProjectTaskSnapshot` initializer, after `milestoneID: row.milestoneID`. Fix any other `ProjectTaskSnapshot(` call (`grep -rn "ProjectTaskSnapshot(" LifeOSKit LIfeOS`) the same way.

In `LifeOSKit/Sources/Persistence/LifeOSContainer.swift`, add `FeatureRecord.self,` on the line after `MilestoneRecord.self,`.

- [ ] **Step 5: Add the store reads and writes**

In `ProjectsStore.swift`, after `milestones(projectID:)`:

```swift
    public func features(projectID: UUID) throws -> [FeatureSnapshot] {
        let tasks = try liveTasks().filter { $0.projectID == projectID }
        return try liveFeatures().filter { $0.projectID == projectID }
            .sorted { $0.position < $1.position }
            .map { snapshot($0, tasks: tasks) }
    }

    public func feature(id: UUID) throws -> FeatureSnapshot? {
        guard let row = try liveFeatures().first(where: { $0.id == id }) else { return nil }
        return snapshot(row, tasks: try liveTasks().filter { $0.projectID == row.projectID })
    }

    public func featureProgress(projectID: UUID) throws -> FeatureProgress {
        FeatureProgress.of(try liveFeatures().filter { $0.projectID == projectID }
            .map { FeatureStage(rawValue: $0.stage) ?? .planned })
    }
```

After `moveMilestone(id:to:)`:

```swift
    @discardableResult
    public func createFeature(projectID: UUID, title: String, note: String = "", branch: String? = nil,
                              milestoneID: UUID? = nil) throws -> UUID {
        let position = try liveFeatures().filter { $0.projectID == projectID }.count
        let row = FeatureRecord(projectID: projectID, title: Self.limit(title, 80), position: position)
        row.note = Self.limit(note, 280)
        row.branch = branch.map { Self.limit($0, 255) }.flatMap { $0.isEmpty ? nil : $0 }
        row.milestoneID = milestoneID
        context.insert(row)
        try context.save()
        return row.id
    }

    public func updateFeature(id: UUID, title: String? = nil, note: String? = nil,
                              milestoneID: UUID?? = nil, branch: String?? = nil) throws {
        guard let row = try featureRecord(id) else { return }
        if let title { row.title = Self.limit(title, 80) }
        if let note { row.note = Self.limit(note, 280) }
        if let milestoneID { row.milestoneID = milestoneID }
        if let branch { row.branch = branch.map { Self.limit($0, 255) }.flatMap { $0.isEmpty ? nil : $0 } }
        row.updatedAt = .now
        try context.save()
    }

    public func moveFeature(id: UUID, to index: Int) throws {
        guard let moving = try featureRecord(id) else { return }
        var list = try liveFeatures().filter { $0.projectID == moving.projectID && $0.id != id }
            .sorted { $0.position < $1.position }
        list.insert(moving, at: min(max(index, 0), list.count))
        for (position, row) in list.enumerated() where row.position != position {
            row.position = position
            row.updatedAt = .now
        }
        try context.save()
    }

    /// Tombstones the feature and unlinks its tasks, as the server's
    /// `on delete set null` would.
    public func deleteFeature(id: UUID) throws {
        guard let row = try featureRecord(id) else { return }
        row.deletedAt = .now
        row.updatedAt = .now
        for task in try liveTasks() where task.featureID == id {
            task.featureID = nil
            task.updatedAt = .now
        }
        try context.save()
    }

    /// Writes a stage worked out from GitHub. Only a change is an edit: an
    /// unchanged stage would otherwise be pushed by every member who opens
    /// the project. The check time is kept here either way, for "as of".
    @discardableResult
    public func applyStage(featureID: UUID, stage: FeatureStage, detail: String, prNumber: Int?,
                           checkedAt: Date) throws -> Bool {
        guard let row = try featureRecord(featureID) else { return false }
        let detail = Self.limit(detail, 80)
        let changed = row.stage != stage.rawValue || row.stageDetail != detail || row.prNumber != prNumber
        row.stageCheckedAt = checkedAt
        if changed {
            row.stage = stage.rawValue
            row.stageDetail = detail
            row.prNumber = prNumber
            row.updatedAt = .now
        }
        try context.save()
        return changed
    }
```

Extend `updateTask` (line ~140): add parameter `featureID: UUID?? = nil` after `milestoneID: UUID?? = nil`, and in the body after `if let milestoneID { row.milestoneID = milestoneID }` add `if let featureID { row.featureID = featureID }`.

Sync plumbing in the same file:

```swift
    // Pending: add the field and include it in isEmpty
    public struct Pending {
        public let projects: [ProjectRecord]
        public let members: [ProjectMemberRecord]
        public let milestones: [MilestoneRecord]
        public let features: [FeatureRecord]
        public let tasks: [ProjectTaskRecord]
        public var isEmpty: Bool {
            projects.isEmpty && members.isEmpty && milestones.isEmpty && features.isEmpty && tasks.isEmpty
        }
    }
```

In `pending()` add `features: try context.fetch(FetchDescriptor<FeatureRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) },` after `milestones:`. In `PushedSnapshot.init` add `pending.features.forEach { stamps[$0.id] = $0.updatedAt }`. In `markSynced(_:)` add `for row in try context.fetch(FetchDescriptor<FeatureRecord>()) where unchanged(row.id, row.updatedAt) { row.syncedAt = row.updatedAt }`. In `forgetProject(_:)` add `for row in try context.fetch(FetchDescriptor<FeatureRecord>()) where row.projectID == id { context.delete(row) }` before the milestone line.

After `applyRemoteMilestone`:

```swift
    public func applyRemoteFeature(id: UUID, projectID: UUID, milestoneID: UUID?, title: String, note: String,
                                   position: Int, branch: String?, stage: String, stageDetail: String,
                                   prNumber: Int?, stageCheckedAt: Date?, updatedAt: Date, deletedAt: Date?) throws {
        let existing = try featureRecord(id)
        if let existing, ProjectMerge.keepLocal(localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt,
                                                remoteUpdatedAt: updatedAt) { return }
        let row = existing ?? {
            let made = FeatureRecord(id: id, projectID: projectID, title: title, position: position)
            context.insert(made)
            return made
        }()
        row.milestoneID = milestoneID; row.title = title; row.note = note; row.position = position
        row.branch = branch; row.stage = stage; row.stageDetail = stageDetail; row.prNumber = prNumber
        row.stageCheckedAt = stageCheckedAt
        row.deletedAt = deletedAt; row.updatedAt = updatedAt; row.syncedAt = updatedAt
        try context.save()
    }
```

Extend `applyRemoteTask` with a `featureID: UUID? = nil` parameter after `milestoneID` and set `row.featureID = featureID` beside `row.milestoneID = milestoneID`.

Helpers, beside `liveMilestones()`:

```swift
    private func featureRecord(_ id: UUID) throws -> FeatureRecord? {
        try context.fetch(FetchDescriptor<FeatureRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func liveFeatures() throws -> [FeatureRecord] {
        try context.fetch(FetchDescriptor<FeatureRecord>()).filter { $0.deletedAt == nil }
    }

    private func snapshot(_ row: FeatureRecord, tasks: [ProjectTaskRecord]) -> FeatureSnapshot {
        let theirs = tasks.filter { $0.featureID == row.id }
        let done = theirs.filter { $0.status == ProjectStatus.done.rawValue }.count
        return FeatureSnapshot(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID, title: row.title,
                               note: row.note, position: row.position, branch: row.branch,
                               stage: FeatureStage(rawValue: row.stage) ?? .planned, stageDetail: row.stageDetail,
                               prNumber: row.prNumber, stageCheckedAt: row.stageCheckedAt,
                               openTasks: theirs.count - done, doneTasks: done)
    }
```

- [ ] **Step 6: Run the tests**

Run: `cd LifeOSKit && swift test --filter "FeaturesStoreTests|ProjectsStoreTests" 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 7: Run the whole package**

Run: `cd LifeOSKit && swift test 2>&1 | grep -E "Test run with|error:" | tail -3`
Expected: `Test run with N tests ... passed` (N ≥ 1626 + 8).

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Persistence LifeOSKit/Tests/PersistenceTests/FeaturesStoreTests.swift
git commit -m "feat(persistence): features with plan order, stages and progress"
```

## Task 3: Sync features and the task link

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/ProjectWireFormat.swift` (add `FeatureRow`; `featureID` on `ProjectTaskRow`)
- Modify: `LifeOSKit/Sources/Integrations/ProjectSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/ProjectSyncTests.swift`

**Interfaces:**
- Consumes: Task 2's store API (`pending().features`, `applyRemoteFeature`, `applyRemoteTask(featureID:)`).
- Produces: `public struct FeatureRow: Equatable, Sendable` with `init?(json:)` and `payload()`; table name `"project_features"`.

- [ ] **Step 1: Write the failing tests**

Append inside `ProjectSyncTests`:

```swift
    @Test func featuresGoUpAndComeBack() async throws {
        let (_, store, server, sync) = try setUp()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        let f = try store.createFeature(projectID: project, title: "Sign in", branch: "feat/sign-in")
        let t = try store.createTask(projectID: project, title: "Button")
        try store.updateTask(id: t, featureID: .some(f))
        await sync.sync()
        let row = try #require(server.tables["project_features"]?[id(f)])
        #expect(row["title"] as? String == "Sign in")
        #expect(row["branch"] as? String == "feat/sign-in")
        #expect(row["stage"] as? String == "planned")
        #expect(server.tables["project_tasks"]?[id(t)]?["feature_id"] as? String == id(f))
        #expect(try store.pending().isEmpty)
    }

    /// A member with no access to the repo receives the stage another wrote.
    @Test func aStageWrittenElsewhereArrives() async throws {
        let (_, store, server, sync) = try setUp()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        let f = try store.createFeature(projectID: project, title: "Sign in")
        await sync.sync()
        var row = try #require(server.tables["project_features"]?[id(f)])
        row["stage"] = "review"; row["stage_detail"] = "PR #42 open"; row["pr_number"] = 42
        server.seed("project_features", row, at: .now.addingTimeInterval(60))
        await sync.sync()
        let feature = try #require(try store.feature(id: f))
        #expect(feature.stage == .review && feature.prNumber == 42 && feature.stageDetail == "PR #42 open")
    }

    @Test func aFriendAddedLaterReceivesTheFeaturesToo() async throws {
        let (_, store, server, sync) = try setUp()
        await sync.sync()
        let p = UUID(), f = UUID()
        let long = Date(timeIntervalSince1970: 1_000_000_000)
        server.seed("projects", ["id": id(p), "name": "Old", "scope": "", "colour": "iris", "owner_id": id(friend)], at: long)
        server.seed("project_features", ["id": id(f), "project_id": id(p), "title": "Old feature", "note": "",
                                         "position": 0, "stage": "done", "stage_detail": "Merged", "pr_number": 3], at: long)
        server.seed("project_members", ["id": id(UUID()), "project_id": id(p), "user_id": id(me), "role": "member"],
                    at: Date(timeIntervalSince1970: 1_900_000_000))
        await sync.sync()
        #expect(try store.features(projectID: p).map(\.title) == ["Old feature"])
        #expect(try store.features(projectID: p).first?.stage == .done)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter ProjectSyncTests 2>&1 | tail -5`
Expected: FAIL; `project_features` never written.

- [ ] **Step 3: Add the wire row**

In `ProjectWireFormat.swift`, after `MilestoneRow`:

```swift
public struct FeatureRow: Equatable, Sendable {
    public var id: UUID, projectID: UUID, milestoneID: UUID?, title: String, note: String, position: Int
    public var branch: String?, stage: String, stageDetail: String, prNumber: Int?, stageCheckedAt: Date?
    public var updatedAt: Date, deletedAt: Date?

    public init(id: UUID, projectID: UUID, milestoneID: UUID?, title: String, note: String, position: Int,
                branch: String?, stage: String, stageDetail: String, prNumber: Int?, stageCheckedAt: Date?,
                updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.projectID = projectID; self.milestoneID = milestoneID; self.title = title
        self.note = note; self.position = position; self.branch = branch; self.stage = stage
        self.stageDetail = stageDetail; self.prNumber = prNumber; self.stageCheckedAt = stageCheckedAt
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public init?(json: [String: Any]) {
        guard let id = WireDate.uuid(json["id"]), let project = WireDate.uuid(json["project_id"]),
              let updated = WireDate.read(json["updated_at"]) else { return nil }
        self.init(id: id, projectID: project, milestoneID: WireDate.uuid(json["milestone_id"]),
                  title: json["title"] as? String ?? "", note: json["note"] as? String ?? "",
                  position: json["position"] as? Int ?? 0, branch: json["branch"] as? String,
                  stage: json["stage"] as? String ?? "planned", stageDetail: json["stage_detail"] as? String ?? "",
                  prNumber: json["pr_number"] as? Int, stageCheckedAt: WireDate.read(json["stage_checked_at"]),
                  updatedAt: updated, deletedAt: WireDate.read(json["deleted_at"]))
    }

    public func payload() -> [String: Any] {
        ["id": WireDate.string(id), "project_id": WireDate.string(projectID),
         "milestone_id": WireDate.string(milestoneID), "title": title, "note": note, "position": position,
         "branch": branch ?? NSNull(), "stage": stage, "stage_detail": stageDetail,
         "pr_number": prNumber ?? NSNull(), "stage_checked_at": WireDate.instant(stageCheckedAt),
         "updated_at": WireDate.instant(updatedAt), "deleted_at": WireDate.instant(deletedAt)]
    }
}
```

Check how `WireDate.string(nil)` encodes absent values (`grep -n "static func string" LifeOSKit/Sources/Integrations/*.swift`) and use the same convention for `branch` and `pr_number` if it is not `NSNull()`.

Add `featureID: UUID?` to `ProjectTaskRow` after `milestoneID`: in the stored properties, the memberwise `init` (parameter `featureID: UUID? = nil` after `milestoneID`), `init?(json:)` (`featureID: WireDate.uuid(json["feature_id"])`), and `payload()` (`"feature_id": WireDate.string(featureID)`).

- [ ] **Step 4: Push and pull features in `ProjectSync`**

- In `push(token:)`, after the `project_milestones` line: `refused += try await send("project_features", pending.features.map(Self.featureRow), token: token)` (before tasks, since tasks reference features).
- In `pull(token:)`, after the `project_milestones` `pullTable`:

```swift
        try await pullTable("project_features", token: token) { json in
            guard let row = FeatureRow(json: json) else { return nil }
            try Self.apply(row, store)
            return row.updatedAt
        }
```

- In `pullWhole`, after the milestones loop:

```swift
        for json in SupabaseREST.decode(try await remote.fetch(table: "project_features", column: "project_id",
                                                               equals: key, accessToken: token, limit: 1_000)) {
            if let row = FeatureRow(json: json) { try Self.apply(row, store) }
        }
```

- Rows section:

```swift
    private static func apply(_ row: FeatureRow, _ store: ProjectsStore) throws {
        try store.applyRemoteFeature(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID,
                                     title: row.title, note: row.note, position: row.position, branch: row.branch,
                                     stage: row.stage, stageDetail: row.stageDetail, prNumber: row.prNumber,
                                     stageCheckedAt: row.stageCheckedAt, updatedAt: row.updatedAt,
                                     deletedAt: row.deletedAt)
    }

    private static func featureRow(_ r: FeatureRecord) -> [String: Any] {
        FeatureRow(id: r.id, projectID: r.projectID, milestoneID: r.milestoneID, title: r.title, note: r.note,
                   position: r.position, branch: r.branch, stage: r.stage, stageDetail: r.stageDetail,
                   prNumber: r.prNumber, stageCheckedAt: r.stageCheckedAt, updatedAt: r.updatedAt,
                   deletedAt: r.deletedAt).payload()
    }
```

- Pass `featureID: row.featureID` in `apply(_ row: ProjectTaskRow, ...)` and `featureID: r.featureID` in `taskRow(_:)`.
- Update the doc comment on `FakeProjectServer` from "four project tables" to "five".

- [ ] **Step 5: Run the tests**

Run: `cd LifeOSKit && swift test --filter "ProjectSyncTests|ProjectWire" 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/ProjectWireFormat.swift LifeOSKit/Sources/Integrations/ProjectSync.swift LifeOSKit/Tests/IntegrationsTests/ProjectSyncTests.swift
git commit -m "feat(projects): sync features and a task's feature"
```

## Task 4: The Plan view, the feature page, and a task's feature

**Files:**
- Modify: `LIfeOS/Features/Projects/ViewModel/ProjectsViewModel.swift` (feature writes)
- Create: `LIfeOS/Features/Projects/View/ProjectPlanView.swift`
- Create: `LIfeOS/Features/Projects/View/FeatureDetailView.swift`
- Modify: `LIfeOS/Features/Projects/View/ProjectScreen.swift` (Plan pane, scrolling picker, feature destination)
- Modify: `LIfeOS/Features/Projects/View/TaskSheet.swift` (Feature picker)
- Modify: `LIfeOS/Features/Projects/View/ProjectsDesignPreview.swift` (features in the fixture, `project-plan` page)
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:139` (route `project-plan`, already matched by `page.hasPrefix("project-")`; confirm)
- Test: `LIfeOSUITests/ProjectPlanUITests.swift` (new; register in the pbxproj)

**Interfaces:**
- Consumes: Task 2's store API.
- Produces: `ProjectsViewModel.createFeature(in:title:) -> UUID?`, `updateFeature(_:title:note:milestoneID:branch:)`, `moveFeature(_:to:)`, `deleteFeature(_:)`; `ProjectScreen.Pane.plan`; `ProjectPlanView(features:progress:colour:header:onOpen:onAdd:onMove:onDelete:footer:)`; `FeatureDetailView(model:featureID:colour:commits:)` where `commits` is a view slot slice 2 fills.

- [ ] **Step 1: Write the failing UI test**

Create `LIfeOSUITests/ProjectPlanUITests.swift`:

```swift
import XCTest

/// The Plan view on the `project-plan` preview page, whose fixture has three
/// features: one done, one in review, one planned.
@MainActor
final class ProjectPlanUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testThePlanShowsProgressAndStages() {
        let app = launch("project-plan")
        XCTAssertTrue(app.staticTexts["1 OF 3 FEATURES DONE"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["IN REVIEW"].exists)
        XCTAssertTrue(app.staticTexts["PR #42 open"].exists)
    }

    func testAddingAFeature() {
        let app = launch("project-plan")
        let field = app.textFields["New feature"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Dark mode\n")
        XCTAssertTrue(app.staticTexts["Dark mode"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["1 OF 4 FEATURES DONE"].exists)
    }

    func testOpeningAFeatureShowsItsBranch() {
        let app = launch("project-plan")
        let row = app.buttons["Credit cards"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(app.staticTexts["feat/credit-cards"].waitForExistence(timeout: 4))
    }
}
```

Register it in the UI test target (that group is not synchronized). Write this script to the scratchpad and run it with the file name:

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('LIfeOS.xcodeproj')
target = project.targets.find { |t| t.name == 'LIfeOSUITests' }
group = project.main_group.find_subpath('LIfeOSUITests', false)
ref = group.new_reference(ARGV[0])
target.source_build_phase.add_file_reference(ref)
project.save
```

Run: `ruby <scratchpad>/addtest.rb ProjectPlanUITests.swift`

- [ ] **Step 2: Run it to see it fail**

Run: `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=<iPhone simulator id>' -only-testing:LIfeOSUITests/ProjectPlanUITests 2>&1 | grep -E "Test Case|error:" | head`
Expected: FAIL; no `1 OF 3 FEATURES DONE`. (Confirm it says `Executed 3 tests`; zero executed means the file is not in the target.)

- [ ] **Step 3: View model writes**

In `ProjectsViewModel.swift`, after `moveMilestone`:

```swift
    @discardableResult
    func createFeature(in project: UUID, title: String, note: String = "", branch: String? = nil,
                       milestoneID: UUID? = nil) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store else { return nil }
        let id = try? store.createFeature(projectID: project, title: trimmed, note: note, branch: branch,
                                          milestoneID: milestoneID)
        requestSync()
        return id
    }

    func updateFeature(_ id: UUID, title: String? = nil, note: String? = nil, milestoneID: UUID?? = nil,
                       branch: String?? = nil) {
        try? store?.updateFeature(id: id, title: title, note: note, milestoneID: milestoneID, branch: branch)
        requestSync()
    }

    func moveFeature(_ id: UUID, to index: Int) {
        try? store?.moveFeature(id: id, to: index)
        requestSync()
    }

    func deleteFeature(_ id: UUID) {
        try? store?.deleteFeature(id: id)
        requestSync()
    }
```

Extend `updateTask` with `featureID: UUID?? = nil` and pass it through to `store.updateTask(... featureID: featureID ...)`.

- [ ] **Step 4: The Plan view**

Create `LIfeOS/Features/Projects/View/ProjectPlanView.swift`:

```swift
import SwiftUI
import DesignSystem
import Persistence

/// A project's features in plan order with their stages, and the bar of
/// how many are done. Slice 2 passes the GitHub "as of" line through
/// `header`; slice 3 passes the Draft button through `footer`.
struct ProjectPlanView<Header: View, Footer: View>: View {
    let features: [FeatureSnapshot]
    let progress: FeatureProgress
    let colour: ProjectColour
    @ViewBuilder var header: () -> Header
    let onOpen: (UUID) -> Void
    let onAdd: (String) -> Void
    let onMove: (UUID, Int) -> Void
    let onDelete: (UUID) -> Void
    @ViewBuilder var footer: () -> Footer

    @Environment(\.colorScheme) private var scheme
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: Space.x1) {
                if progress.total > 0 {
                    Text("\(progress.done) OF \(progress.total) FEATURES DONE").brutalLabel()
                    BrutalProgress(fraction: progress.fraction, colour: colour)
                    HStack(spacing: Space.x2) {
                        ForEach(FeatureStage.allCases, id: \.self) { stage in
                            Text("\(stage.label) \(progress.counts[stage] ?? 0)")
                                .font(LifeOSType.caption.weight(.heavy)).monospacedDigit()
                        }
                    }
                } else {
                    Text("NO FEATURES YET").brutalLabel()
                    Text("List what this project needs to ship, in the order you will build it.")
                        .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                }
                header()
            }
            .brutalCard()

            ForEach(features) { feature in
                Button { onOpen(feature.id) } label: { FeatureRow(feature: feature, colour: colour) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(feature.title)
                    .accessibilityAction(named: "Move up") { onMove(feature.id, max(feature.position - 1, 0)) }
                    .accessibilityAction(named: "Move down") { onMove(feature.id, feature.position + 1) }
                    .contextMenu {
                        Button("Move up") { onMove(feature.id, max(feature.position - 1, 0)) }
                        Button("Move down") { onMove(feature.id, feature.position + 1) }
                        Button("Delete", role: .destructive) { onDelete(feature.id) }
                    }
            }

            HStack {
                TextField("New feature", text: $newTitle)
                    .font(LifeOSType.body)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("ADD", action: add).font(LifeOSType.label.weight(.heavy))
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .brutalCard()

            footer()
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAdd(title)
        newTitle = ""
    }
}

/// One feature: title, stage chip and the line under it.
struct FeatureRow: View {
    let feature: FeatureSnapshot
    let colour: ProjectColour
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(LifeOSType.rowTitle.weight(.heavy))
                if !feature.stageDetail.isEmpty {
                    Text(feature.stageDetail).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            Spacer()
            StageChip(stage: feature.stage, colour: colour)
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .brutalCard()
    }
}

/// Filled for done, outlined otherwise, so the column of chips reads at a glance.
struct StageChip: View {
    let stage: FeatureStage
    let colour: ProjectColour
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        Text(stage.label)
            .font(LifeOSType.caption.weight(.heavy)).tracking(0.6)
            .padding(.horizontal, Space.x1).padding(.vertical, 2)
            .foregroundStyle(stage == .done ? LifeOSTokens.canvas.resolve(scheme) : ink)
            .background(stage == .done ? ink : (stage == .planned ? .clear : colour.fill.resolve(scheme)))
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
    }
}
```

Before writing, run `grep -n "func brutalLabel\|func brutalCard\|struct BrutalProgress" -r LIfeOS/Features/Projects` and match the exact signatures (`brutalCard(header:)` takes an optional colour).

- [ ] **Step 5: The feature page**

Create `LIfeOS/Features/Projects/View/FeatureDetailView.swift`:

```swift
import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// One feature: its note, milestone, branch, and tasks. `commits` is where
/// slice 2 puts the branch's commits and its PR.
struct FeatureDetailView<Commits: View>: View {
    @Bindable var model: ProjectsViewModel
    let featureID: UUID
    let colour: ProjectColour
    @ViewBuilder var commits: () -> Commits

    @Environment(\.colorScheme) private var scheme
    @State private var note = ""
    @State private var branch = ""
    @State private var newTask = ""
    @State private var revision = 0

    private var feature: FeatureSnapshot? { _ = revision; _ = model.projects; return try? model.store?.feature(id: featureID) }
    private var tasks: [ProjectTaskSnapshot] {
        _ = revision; _ = model.projects
        guard let feature else { return [] }
        return ((try? model.store?.tasks(projectID: feature.projectID)) ?? []).filter { $0.featureID == featureID }
    }
    private var milestones: [MilestoneSnapshot] {
        guard let feature else { return [] }
        return (try? model.store?.milestones(projectID: feature.projectID)) ?? []
    }

    var body: some View {
        if let feature {
            VStack(alignment: .leading, spacing: Space.x2) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    HStack {
                        Text(feature.title.uppercased()).font(LifeOSType.sectionTitle.weight(.black))
                        Spacer()
                        StageChip(stage: feature.stage, colour: colour)
                    }
                    if !feature.stageDetail.isEmpty {
                        Text(feature.stageDetail).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .font(LifeOSType.body)
                        .onSubmit { model.updateFeature(featureID, note: note) }
                    Picker("Milestone", selection: Binding(
                        get: { feature.milestoneID },
                        set: { model.updateFeature(featureID, milestoneID: .some($0)); revision += 1 })) {
                        Text("None").tag(UUID?.none)
                        ForEach(milestones) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.menu)
                }
                .brutalCard(header: colour.fill.resolve(scheme))

                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("BRANCH").brutalLabel()
                    if let linked = feature.branch {
                        HStack {
                            Text(linked).font(LifeOSType.body.monospaced())
                            Spacer()
                            Button("COPY") { UIPasteboard.general.string = linked }.font(LifeOSType.label.weight(.heavy))
                            Button("UNLINK") { model.updateFeature(featureID, branch: .some(nil)); revision += 1 }
                                .font(LifeOSType.label.weight(.heavy))
                        }
                    } else {
                        HStack {
                            TextField("Branch name", text: $branch)
                                .font(LifeOSType.body.monospaced())
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .onSubmit(linkTypedBranch)
                            Button("LINK", action: linkTypedBranch).font(LifeOSType.label.weight(.heavy))
                        }
                    }
                }
                .brutalCard()

                commits()

                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("TASKS \(feature.doneTasks)/\(feature.doneTasks + feature.openTasks)").brutalLabel()
                    ForEach(tasks) { task in ProjectTaskRow(task: task, owner: task.ownerID.map(model.name)) }
                    HStack {
                        TextField("New task", text: $newTask).onSubmit(addTask)
                        Button("ADD", action: addTask).font(LifeOSType.label.weight(.heavy))
                    }
                }
                .brutalCard()
            }
            .onAppear { note = feature.note; branch = "" }
        }
    }

    private func linkTypedBranch() {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.updateFeature(featureID, branch: .some(name))
        branch = ""
        revision += 1
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let feature, let id = model.createTask(in: feature.projectID, title: title) else { return }
        model.updateTask(id, featureID: .some(featureID))
        newTask = ""
        revision += 1
    }
}
```

The branch field starts empty here; slice 2 (Task 8) pre-fills the suggested name and adds a branch picker.

- [ ] **Step 6: Wire Plan into the project screen**

In `ProjectScreen.swift`:

1. Replace the `Pane` enum with:

```swift
    enum Pane: String, CaseIterable {
        case plan = "PLAN", board = "BOARD", schedule = "SCHEDULE", milestones = "MILESTONES", list = "LIST"
    }
```

2. Add state and reads:

```swift
    @State private var openFeature: UUID?
    private var features: [FeatureSnapshot] { _ = revision; _ = model.projects; return (try? model.store?.features(projectID: projectID)) ?? [] }
    private var featureProgress: FeatureProgress {
        _ = revision; _ = model.projects
        return (try? model.store?.featureProgress(projectID: projectID)) ?? .of([])
    }
```

3. In the `switch pane`, add:

```swift
                    case .plan:
                        ProjectPlanView(
                            features: features, progress: featureProgress, colour: colour,
                            header: { EmptyView() },
                            onOpen: { openFeature = $0 },
                            onAdd: { title in model.createFeature(in: projectID, title: title); revision += 1 },
                            onMove: { id, index in model.moveFeature(id, to: index); revision += 1 },
                            onDelete: { id in model.deleteFeature(id); revision += 1 },
                            footer: { EmptyView() })
```

4. After the `.sheet(isPresented: $showMembers ...)` modifier:

```swift
        .navigationDestination(item: $openFeature) { id in
            ScrollView {
                FeatureDetailView(model: model, featureID: id,
                                  colour: ProjectColour(named: project?.colour ?? "tomato"),
                                  commits: { EmptyView() })
                    .padding(.horizontal, layout.gutter)
                    .padding(.leading, layout.railInset)
                    .padding(.vertical, Space.x2)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .onDisappear { revision += 1 }
        }
```

5. Make the picker fit six panes on a phone: wrap the `HStack(spacing: 0)` in `ScrollView(.horizontal, showsIndicators: false)` and give each option `.frame(minWidth: 76)` in place of `.frame(maxWidth: .infinity)`, keeping `.padding(.vertical, Space.x1)` and adding `.padding(.horizontal, Space.x1)`. On regular width keep the full-width layout: `if layout.isRegular { row.frame(maxWidth: .infinity) } else { ScrollView(.horizontal) { row } }`, with `row` the existing `HStack`.

6. Initial pane: change `init` so the default is the plan when the project has a repo. The repo is not known in `init`, so make `initialPane: Pane? = nil`, store it in `_pane = State(initialValue: initialPane ?? .board)`, and add to `body` `.task { if initialPaneWasDefault, project?.repo != nil { pane = .plan } }` with `private let initialPaneWasDefault: Bool` set in `init` as `initialPane == nil`.

- [ ] **Step 7: A task's feature in the task sheet**

In `TaskSheet.swift`: add `let features: [FeatureSnapshot]` beside `milestones`, `@State private var feature: UUID?`, a picker after the milestone picker:

```swift
                    Picker("Feature", selection: $feature) {
                        Text("None").tag(UUID?.none)
                        ForEach(features) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
```

Load it with the other fields (`feature = task.featureID`) and save it with them (`featureID: .some(feature)` in the `model.updateTask(...)` call at line ~125). Pass `features: features` from `ProjectScreen`'s `.sheet(item: $editing)`. Find every other `TaskSheet(` call (`grep -rn "TaskSheet(" LIfeOS`) and pass `features: []` where no project is open.

- [ ] **Step 8: The preview page**

In `ProjectsDesignPreview.swift`, in the fixture after the milestones are made:

```swift
        let signIn = try! store.createFeature(projectID: launch, title: "Sign in", branch: "feat/sign-in")
        try! store.applyStage(featureID: signIn, stage: .done, detail: "Merged 3d ago · PR #40", prNumber: 40, checkedAt: today)
        let cards = try! store.createFeature(projectID: launch, title: "Credit cards", branch: "feat/credit-cards")
        try! store.applyStage(featureID: cards, stage: .review, detail: "PR #42 open", prNumber: 42, checkedAt: today)
        _ = try! store.createFeature(projectID: launch, title: "Widgets")
```

and in the page switch: `case "project-plan": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .plan)`.

- [ ] **Step 9: Build and run the UI tests**

Run: `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=<iPhone simulator id>' -only-testing:LIfeOSUITests/ProjectPlanUITests -only-testing:LIfeOSUITests/ProjectsUITests 2>&1 | grep -E "Test Case|Executed|error:" | head -20`
Expected: `Executed 3+N tests, with 0 failures`. The existing `ProjectsUITests` still pass (they tap `BOARD`, `SCHEDULE`).

- [ ] **Step 10: Commit**

```bash
git add LIfeOS/Features/Projects LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift LIfeOSUITests/ProjectPlanUITests.swift LIfeOS.xcodeproj/project.pbxproj
git commit -m "feat(projects): a plan of features with progress, a feature page, and a task's feature"
```

- [ ] **Step 11: Open the slice 1 PR**

Push `feat/project-features` and open a PR titled "Projects: features and the Plan view". Body: summary, owner step `supabase db push` (migration `20261008120000_project_features.sql`), test plan with the counts from Steps 7 and 9.

---

# Slice 2: GitHub

Branch `feat/project-features-github` from the slice 1 tip.

## Task 5: Stages, branch names and linking (pure)

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FeatureStageResolver.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FeatureStageResolverTests.swift`

**Interfaces:**
- Consumes: `FeatureStage` (Persistence).
- Produces:
  - `public struct GitHubBranchState: Equatable, Sendable { name: String; lastCommitAt: Date?; ahead: Int; behind: Int }`
  - `public struct GitHubPullState: Equatable, Sendable { enum State: String { open, closed, merged }; number: Int; title: String; state: State; url: URL; mergedAt: Date?; headBranch: String; headRepo: String? }`
  - `public struct GitHubProjectStatus: Equatable, Sendable { defaultBranch: String; branches: [GitHubBranchState]; pulls: [GitHubPullState]; var lastCommitAt: Date? }`
  - `public struct ResolvedStage: Equatable, Sendable { stage: FeatureStage; detail: String; prNumber: Int? }`
  - `public enum BranchLink: Equatable, Sendable { case none, one(String), several([String]) }`
  - `public enum FeatureStageResolver { static func resolve(branch: String?, repo: String, status: GitHubProjectStatus, now: Date) -> ResolvedStage; static func slug(_:) -> String; static func suggestedBranch(_:) -> String; static func link(title: String, branches: [String]) -> BranchLink }`
  - `public enum GitHubRelative { static func short(_ date: Date, now: Date) -> String }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Integrations
import Persistence

@Suite struct FeatureStageResolverTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private let repo = "shivvyas2/LifeOS"
    private func pr(_ number: Int, _ state: GitHubPullState.State, branch: String = "feat/cards",
                    repo: String? = "shivvyas2/LifeOS", mergedHoursAgo: Double? = nil) -> GitHubPullState {
        GitHubPullState(number: number, title: "PR \(number)", state: state,
                        url: URL(string: "https://github.com/\(self.repo)/pull/\(number)")!,
                        mergedAt: mergedHoursAgo.map { now.addingTimeInterval(-$0 * 3_600) },
                        headBranch: branch, headRepo: repo)
    }
    private func status(branches: [GitHubBranchState] = [], pulls: [GitHubPullState] = []) -> GitHubProjectStatus {
        GitHubProjectStatus(defaultBranch: "main", branches: branches, pulls: pulls)
    }
    private func branch(_ name: String = "feat/cards", ahead: Int, hoursAgo: Double = 2) -> GitHubBranchState {
        GitHubBranchState(name: name, lastCommitAt: now.addingTimeInterval(-hoursAgo * 3_600), ahead: ahead, behind: 0)
    }

    @Test func noBranchIsNotStarted() {
        #expect(FeatureStageResolver.resolve(branch: nil, repo: repo, status: status(), now: now)
                == ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil))
    }

    @Test func aMissingBranchIsNotStarted() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo, status: status(), now: now).stage == .planned)
    }

    @Test func aBranchWithNoCommitsIsStillPlanned() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                                    status: status(branches: [branch(ahead: 0)]), now: now)
        #expect(resolved == ResolvedStage(stage: .planned, detail: "Branch made, no commits yet", prNumber: nil))
    }

    @Test func commitsAheadAreBuilding() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 12)]), now: now)
                == ResolvedStage(stage: .building, detail: "12 commits · 2h ago", prNumber: nil))
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 1)]), now: now).detail
                == "1 commit · 2h ago")
    }

    @Test func anOpenPRIsInReview() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 3)], pulls: [pr(42, .open)]), now: now)
                == ResolvedStage(stage: .review, detail: "PR #42 open", prNumber: 42))
    }

    @Test func aMergedPRIsDoneEvenAfterTheBranchIsDeleted() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(pulls: [pr(42, .merged, mergedHoursAgo: 50)]), now: now)
                == ResolvedStage(stage: .done, detail: "Merged 2d ago · PR #42", prNumber: 42))
    }

    @Test func aNewerOpenPRAfterAMergeIsInReview() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
            status: status(branches: [branch(ahead: 1)], pulls: [pr(42, .merged, mergedHoursAgo: 50), pr(57, .open)]), now: now)
        #expect(resolved.stage == .review && resolved.prNumber == 57)
    }

    @Test func aClosedUnmergedPRIsIgnored() {
        #expect(FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
                                             status: status(branches: [branch(ahead: 4)], pulls: [pr(42, .closed)]), now: now).stage
                == .building)
    }

    /// Review Focus 4: a fork's PR from a branch of the same name is not ours.
    @Test func aForksPRDoesNotMoveTheFeature() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: repo,
            status: status(pulls: [pr(42, .merged, repo: "someone/LifeOS", mergedHoursAgo: 1)]), now: now)
        #expect(resolved.stage == .planned)
    }

    @Test func repoNamesMatchWithoutCase() {
        let resolved = FeatureStageResolver.resolve(branch: "feat/cards", repo: "ShivVyas2/lifeos",
                                                    status: status(pulls: [pr(42, .open)]), now: now)
        #expect(resolved.stage == .review)
    }

    @Test func slugsAreShortPlainAndLowercase() {
        #expect(FeatureStageResolver.slug("Credit cards") == "credit-cards")
        #expect(FeatureStageResolver.slug("  Café & Crème: v2!  ") == "cafe-creme-v2")
        #expect(FeatureStageResolver.slug("🚀") == "feature")
        #expect(FeatureStageResolver.slug(String(repeating: "abc ", count: 30)).count <= 40)
        #expect(!FeatureStageResolver.slug(String(repeating: "abc ", count: 30)).hasSuffix("-"))
        #expect(FeatureStageResolver.suggestedBranch("Credit cards") == "feat/credit-cards")
    }

    @Test func linkingNeedsExactlyOneMatch() {
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["main", "feat/credit-cards"]) == .one("feat/credit-cards"))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["shiv/credit-cards"]) == .one("shiv/credit-cards"))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["feat/credit-cards", "fix/credit-cards"])
                == .several(["feat/credit-cards", "fix/credit-cards"]))
        #expect(FeatureStageResolver.link(title: "Credit cards", branches: ["feat/credit-cards-v2"]) == .none)
    }

    @Test func relativeTimesAreShort() {
        #expect(GitHubRelative.short(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(GitHubRelative.short(now.addingTimeInterval(-600), now: now) == "10m ago")
        #expect(GitHubRelative.short(now.addingTimeInterval(-7_200), now: now) == "2h ago")
        #expect(GitHubRelative.short(now.addingTimeInterval(-3 * 86_400), now: now) == "3d ago")
    }

    @Test func theLastCommitIsTheNewestBranchCommit() {
        let s = status(branches: [branch("a", ahead: 1, hoursAgo: 5), branch("b", ahead: 1, hoursAgo: 1)])
        #expect(s.lastCommitAt == now.addingTimeInterval(-3_600))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FeatureStageResolverTests 2>&1 | tail -3`
Expected: build failure, `cannot find 'FeatureStageResolver'`.

- [ ] **Step 3: Implement**

Create `LifeOSKit/Sources/Integrations/FeatureStageResolver.swift`:

```swift
import Foundation
import Persistence

public struct GitHubBranchState: Equatable, Sendable {
    public let name: String
    public let lastCommitAt: Date?
    /// Commits on this branch that the default branch does not have.
    public let ahead: Int
    /// Commits on the default branch that this branch does not have.
    public let behind: Int
    public init(name: String, lastCommitAt: Date?, ahead: Int, behind: Int) {
        self.name = name; self.lastCommitAt = lastCommitAt; self.ahead = ahead; self.behind = behind
    }
}

public struct GitHubPullState: Equatable, Sendable {
    public enum State: String, Sendable { case open, closed, merged }
    public let number: Int
    public let title: String
    public let state: State
    public let url: URL
    public let mergedAt: Date?
    public let headBranch: String
    /// `owner/name` of the repo the head branch lives in; nil when GitHub
    /// no longer knows it (a deleted fork).
    public let headRepo: String?
    public init(number: Int, title: String, state: State, url: URL, mergedAt: Date?, headBranch: String, headRepo: String?) {
        self.number = number; self.title = title; self.state = state; self.url = url
        self.mergedAt = mergedAt; self.headBranch = headBranch; self.headRepo = headRepo
    }
}

public struct GitHubProjectStatus: Equatable, Sendable {
    public let defaultBranch: String
    public let branches: [GitHubBranchState]
    public let pulls: [GitHubPullState]
    public var lastCommitAt: Date? { branches.compactMap(\.lastCommitAt).max() }
    public init(defaultBranch: String, branches: [GitHubBranchState], pulls: [GitHubPullState]) {
        self.defaultBranch = defaultBranch; self.branches = branches; self.pulls = pulls
    }
}

public struct ResolvedStage: Equatable, Sendable {
    public let stage: FeatureStage
    public let detail: String
    public let prNumber: Int?
    public init(stage: FeatureStage, detail: String, prNumber: Int?) {
        self.stage = stage; self.detail = detail; self.prNumber = prNumber
    }
}

public enum BranchLink: Equatable, Sendable { case none, one(String), several([String]) }

/// Turns what GitHub says about a branch into a feature's stage. No network.
public enum FeatureStageResolver {
    public static func resolve(branch: String?, repo: String, status: GitHubProjectStatus, now: Date) -> ResolvedStage {
        guard let branch else { return ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil) }
        // A PR beats the branch, and of the open and merged ones the newest
        // decides. A fork's PR from a branch of the same name is not ours.
        let ours = status.pulls.filter {
            $0.headBranch == branch && $0.state != .closed
                && $0.headRepo?.caseInsensitiveCompare(repo) == .orderedSame
        }
        if let latest = ours.max(by: { $0.number < $1.number }) {
            switch latest.state {
            case .open:
                return ResolvedStage(stage: .review, detail: "PR #\(latest.number) open", prNumber: latest.number)
            case .merged:
                let when = latest.mergedAt.map { GitHubRelative.short($0, now: now) } ?? "recently"
                return ResolvedStage(stage: .done, detail: "Merged \(when) · PR #\(latest.number)", prNumber: latest.number)
            case .closed:
                break
            }
        }
        guard let state = status.branches.first(where: { $0.name == branch }) else {
            return ResolvedStage(stage: .planned, detail: "Not started", prNumber: nil)
        }
        guard state.ahead > 0 else {
            return ResolvedStage(stage: .planned, detail: "Branch made, no commits yet", prNumber: nil)
        }
        let count = state.ahead == 1 ? "1 commit" : "\(state.ahead) commits"
        let when = state.lastCommitAt.map { " · " + GitHubRelative.short($0, now: now) } ?? ""
        return ResolvedStage(stage: .building, detail: count + when, prNumber: nil)
    }

    /// Lower-case ASCII words joined by `-`, at most 40 characters.
    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                if pendingDash && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        var cut = String(out.prefix(40))
        while cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? "feature" : cut
    }

    public static func suggestedBranch(_ title: String) -> String { "feat/" + slug(title) }

    /// A branch named for the feature: exactly the slug, or any prefix
    /// followed by `/slug`. Several matches link none; the page lists them.
    public static func link(title: String, branches: [String]) -> BranchLink {
        let slug = slug(title)
        let matches = branches.filter { $0 == slug || $0.hasSuffix("/" + slug) }.sorted()
        switch matches.count {
        case 0: return .none
        case 1: return .one(matches[0])
        default: return .several(matches)
        }
    }
}

public enum GitHubRelative {
    public static func short(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
```

`Integrations` must already depend on `Persistence` (check `Package.swift`: `grep -n "Integrations" LifeOSKit/Package.swift`); `ProjectSync.swift` imports it, so it does.

- [ ] **Step 4: Run the tests**

Run: `cd LifeOSKit && swift test --filter FeatureStageResolverTests 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FeatureStageResolver.swift LifeOSKit/Tests/IntegrationsTests/FeatureStageResolverTests.swift
git commit -m "feat(integrations): a feature's stage from its branch and PRs"
```

## Task 6: `GitHubProjectSource`

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/GitHubDayLoader.swift` (add `post` to `GitHubTransport`)
- Create: `LifeOSKit/Sources/Integrations/GitHubProjectSource.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/GitHubProjectSourceTests.swift`

**Interfaces:**
- Consumes: Task 5's `GitHubProjectStatus`, `GitHubBranchState`, `GitHubPullState`; `GitHubAPI.url`, `GitHubWire.decoder`, `GitHubRepoRef`.
- Produces:
  - `GitHubTransport.post(_ url: URL, body: Data, token: String) async throws -> (Data, Int)`
  - `public enum GitHubProjectError: Error, Equatable { case unauthorized, notFound, rateLimited, unavailable(Int) }`
  - `public struct GitHubCommitItem: Decodable, Equatable, Sendable { sha: String; htmlUrl: URL; commit: Commit; var subject: String; var authorName: String; var date: Date }`
  - `public struct GitHubProjectSource: Sendable { init(transport:token:repo:); func status() async throws -> GitHubProjectStatus; func history(branch: String, page: Int) async throws -> [GitHubCommitItem]; func branchCommits(base: String, head: String) async throws -> [GitHubCommitItem]; func readme() async -> String?; static func repos(transport:token:) async throws -> [GitHubRepoRef] }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Integrations

/// GET routes by path prefix, and GraphQL replies by a substring of the query.
final class ProjectStubTransport: GitHubTransport, @unchecked Sendable {
    var gets: [(String, Int, String)] = []
    var posts: [(String, Int, String)] = []
    private(set) var requested: [URL] = []
    private(set) var queries: [String] = []

    func get(_ url: URL, token: String) async throws -> (Data, Int) {
        requested.append(url)
        let path = url.path + "?" + (url.query ?? "")
        guard let route = gets.first(where: { path.hasPrefix($0.0) }) else { return (Data("{}".utf8), 404) }
        return (Data(route.2.utf8), route.1)
    }

    func post(_ url: URL, body: Data, token: String) async throws -> (Data, Int) {
        let query = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["query"] as? String ?? ""
        queries.append(query)
        guard let reply = posts.first(where: { query.contains($0.0) }) else { return (Data("{}".utf8), 500) }
        return (Data(reply.2.utf8), reply.1)
    }
}

@Suite struct GitHubProjectSourceTests {
    private let defaultQuery = #"{"data":{"repository":{"defaultBranchRef":{"name":"develop"}}}}"#
    private let statusReply = """
    {"data":{"repository":{
      "refs":{"nodes":[
        {"name":"feat/cards","target":{"committedDate":"2026-10-07T10:00:00Z"},"compare":{"aheadBy":2,"behindBy":5}},
        {"name":"develop","target":{"committedDate":"2026-10-06T10:00:00Z"},"compare":{"aheadBy":0,"behindBy":0}}
      ]},
      "pullRequests":{"nodes":[
        {"number":42,"title":"Cards","state":"OPEN","url":"https://github.com/o/r/pull/42","mergedAt":null,
         "headRefName":"feat/cards","headRepository":{"nameWithOwner":"o/r"}},
        {"number":40,"title":"Old","state":"MERGED","url":"https://github.com/o/r/pull/40","mergedAt":"2026-10-01T09:00:00Z",
         "headRefName":"feat/sign-in","headRepository":null}
      ]}
    }}}
    """
    private func source(_ t: ProjectStubTransport, repo: String = "o/r") -> GitHubProjectSource {
        GitHubProjectSource(transport: t, token: "t", repo: repo)
    }

    /// Review Focus 2: the default branch is read, not assumed to be main.
    /// `Ref.compare(headRef:)` takes the branch as base: its behindBy is what
    /// the branch has that the default does not.
    @Test func statusReadsTheRealDefaultBranchAndFlipsCompare() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, defaultQuery), ("refs(", 200, statusReply)]
        let status = try await source(t).status()
        #expect(status.defaultBranch == "develop")
        let cards = try #require(status.branches.first { $0.name == "feat/cards" })
        #expect(cards.ahead == 5 && cards.behind == 2)
        #expect(status.pulls.map(\.number) == [42, 40])
        #expect(status.pulls[0].state == .open && status.pulls[0].headRepo == "o/r")
        #expect(status.pulls[1].state == .merged && status.pulls[1].headRepo == nil)
        #expect(t.queries.last?.contains("develop") == false, "the default branch goes in variables, not the query text")
    }

    @Test func aMissingRepoIsNotFound() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, #"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND"}]}"#)]
        await #expect(throws: GitHubProjectError.notFound) { _ = try await source(t).status() }
    }

    @Test func aRevokedTokenIsUnauthorized() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 401, "{}")]
        await #expect(throws: GitHubProjectError.unauthorized) { _ = try await source(t).status() }
    }

    @Test func aRateLimitIsItsOwnError() async throws {
        let t = ProjectStubTransport()
        t.posts = [("defaultBranchRef", 200, #"{"errors":[{"type":"RATE_LIMITED"}]}"#)]
        await #expect(throws: GitHubProjectError.rateLimited) { _ = try await source(t).status() }
        t.posts = [("defaultBranchRef", 403, "{}")]
        await #expect(throws: GitHubProjectError.rateLimited) { _ = try await source(t).status() }
    }

    /// Review Focus 3: an empty repository has no history, not an error.
    @Test func anEmptyRepoHasNoHistory() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/commits", 409, #"{"message":"Git Repository is empty."}"#)]
        #expect(try await source(t).history(branch: "main", page: 1).isEmpty)
    }

    @Test func historyPagesThirtyAtATime() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/commits", 200, """
        [{"sha":"abc1234def","html_url":"https://github.com/o/r/commit/abc",
          "commit":{"message":"feat: cards\\n\\nbody","author":{"name":"Shiv","date":"2026-10-07T10:00:00Z"}}}]
        """)]
        let page = try await source(t).history(branch: "develop", page: 2)
        #expect(page.first?.subject == "feat: cards")
        #expect(page.first?.authorName == "Shiv")
        let query = try #require(t.requested.first?.query)
        #expect(query.contains("sha=develop") && query.contains("per_page=30") && query.contains("page=2"))
    }

    /// Review Focus 5: odd branch names reach GitHub encoded.
    @Test func branchNamesAreEncodedInCompare() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/compare/", 200, #"{"commits":[]}"#)]
        _ = try await source(t).branchCommits(base: "main", head: "fix/50% faster #2")
        let url = try #require(t.requested.first)
        #expect(url.absoluteString.contains("fix/50%25%20faster%20%232"))
    }

    @Test func aDeletedBranchHasNoCommits() async throws {
        let t = ProjectStubTransport()
        t.gets = [("/repos/o/r/compare/", 404, "{}")]
        #expect(try await source(t).branchCommits(base: "main", head: "gone").isEmpty)
    }

    @Test func reposPageUntilAShortPage() async throws {
        let t = ProjectStubTransport()
        let full = "[" + (0..<100).map { #"{"name":"r\#($0)","full_name":"o/r\#($0)","html_url":"https://github.com/o/r\#($0)"}"# }
            .joined(separator: ",") + "]"
        t.gets = [("/user/repos?per_page=100&page=1", 200, full),
                  ("/user/repos?per_page=100&page=2", 200, #"[{"name":"last","full_name":"o/last","html_url":"https://github.com/o/last"}]"#)]
        let repos = try await GitHubProjectSource.repos(transport: t, token: "t")
        #expect(repos.count == 101)
        #expect(t.requested.count == 2)
    }

    @Test func theReadmeIsDecodedFromBase64() async throws {
        let t = ProjectStubTransport()
        let encoded = Data("# LifeOS\nA home for your life.".utf8).base64EncodedString()
        t.gets = [("/repos/o/r/readme", 200, #"{"content":"\#(encoded)","encoding":"base64"}"#)]
        #expect(await source(t).readme() == "# LifeOS\nA home for your life.")
        t.gets = []
        #expect(await source(t).readme() == nil)
    }
}
```

The reply order in `posts` matters: the first query contains `defaultBranchRef`, the second contains `refs(`; the second query must not contain the text `defaultBranchRef` or the first stub would answer it.

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter GitHubProjectSourceTests 2>&1 | tail -3`
Expected: build failure (`post` not in `GitHubTransport`, no `GitHubProjectSource`).

- [ ] **Step 3: Add `post` to the transport**

In `GitHubDayLoader.swift`:

```swift
public protocol GitHubTransport: Sendable {
    func get(_ url: URL, token: String) async throws -> (Data, Int)
    func post(_ url: URL, body: Data, token: String) async throws -> (Data, Int)
}

public extension GitHubTransport {
    /// Transports that only ever served GETs (the day card's) answer GraphQL
    /// as unimplemented rather than failing to compile.
    func post(_ url: URL, body: Data, token: String) async throws -> (Data, Int) { (Data(), 501) }
}
```

and in `URLSessionGitHubTransport`:

```swift
    public func post(_ url: URL, body: Data, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
```

- [ ] **Step 4: Implement the source**

Create `LifeOSKit/Sources/Integrations/GitHubProjectSource.swift`:

```swift
import Foundation

public enum GitHubProjectError: Error, Equatable {
    case unauthorized, notFound, rateLimited
    case unavailable(Int)
}

public struct GitHubCommitItem: Decodable, Equatable, Sendable {
    public struct Commit: Decodable, Equatable, Sendable {
        public struct Author: Decodable, Equatable, Sendable {
            public let name: String
            public let date: Date
        }
        public let message: String
        public let author: Author
    }
    public let sha: String
    public let htmlUrl: URL
    public let commit: Commit
    public var subject: String { commit.message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
    public var authorName: String { commit.author.name }
    public var date: Date { commit.author.date }
    public var shortSHA: String { String(sha.prefix(7)) }
}

/// Everything a project reads from its repo, with the phone's own token.
public struct GitHubProjectSource: Sendable {
    let transport: any GitHubTransport
    let token: String
    let repo: String

    public init(transport: any GitHubTransport, token: String, repo: String) {
        self.transport = transport; self.token = token; self.repo = repo
    }

    private var owner: String { String(repo.split(separator: "/").first ?? "") }
    private var name: String { String(repo.split(separator: "/").dropFirst().first ?? "") }

    // MARK: Status (GraphQL)

    public func status() async throws -> GitHubProjectStatus {
        let first: DefaultReply = try await graphQL(Self.defaultQuery, ["owner": owner, "name": name])
        guard let repository = first.repository else { throw GitHubProjectError.notFound }
        let base = repository.defaultBranchRef?.name ?? "main"
        let second: StatusReply = try await graphQL(Self.statusQuery, ["owner": owner, "name": name, "base": base])
        guard let repo = second.repository else { throw GitHubProjectError.notFound }
        // `Ref.compare(headRef:)` takes this branch as the base and the
        // default branch as the head, so its behindBy is this branch's ahead.
        let branches = repo.refs.nodes.map {
            GitHubBranchState(name: $0.name, lastCommitAt: $0.target?.committedDate,
                              ahead: $0.compare?.behindBy ?? 0, behind: $0.compare?.aheadBy ?? 0)
        }
        let pulls = repo.pullRequests.nodes.compactMap { node -> GitHubPullState? in
            guard let state = GitHubPullState.State(rawValue: node.state.lowercased()) else { return nil }
            return GitHubPullState(number: node.number, title: node.title, state: state, url: node.url,
                                   mergedAt: node.mergedAt, headBranch: node.headRefName,
                                   headRepo: node.headRepository?.nameWithOwner)
        }
        return GitHubProjectStatus(defaultBranch: base, branches: branches, pulls: pulls)
    }

    static let defaultQuery = """
    query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { defaultBranchRef { name } } }
    """

    static let statusQuery = """
    query($owner: String!, $name: String!, $base: String!) {
      repository(owner: $owner, name: $name) {
        refs(refPrefix: "refs/heads/", first: 100, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
          nodes { name target { ... on Commit { committedDate } } compare(headRef: $base) { aheadBy behindBy } }
        }
        pullRequests(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes { number title state url mergedAt headRefName headRepository { nameWithOwner } }
        }
      }
    }
    """

    private struct Envelope<Payload: Decodable>: Decodable {
        struct Failure: Decodable { let type: String? }
        let data: Payload?
        let errors: [Failure]?
    }
    private struct DefaultReply: Decodable {
        struct Repository: Decodable { struct Ref: Decodable { let name: String }; let defaultBranchRef: Ref? }
        let repository: Repository?
    }
    private struct StatusReply: Decodable {
        struct Repository: Decodable {
            struct Refs: Decodable {
                struct Node: Decodable {
                    struct Target: Decodable { let committedDate: Date? }
                    struct Compare: Decodable { let aheadBy: Int; let behindBy: Int }
                    let name: String; let target: Target?; let compare: Compare?
                }
                let nodes: [Node]
            }
            struct Pulls: Decodable {
                struct Node: Decodable {
                    struct Head: Decodable { let nameWithOwner: String }
                    let number: Int; let title: String; let state: String; let url: URL
                    let mergedAt: Date?; let headRefName: String; let headRepository: Head?
                }
                let nodes: [Node]
            }
            let refs: Refs; let pullRequests: Pulls
        }
        let repository: Repository?
    }

    private func graphQL<Payload: Decodable>(_ query: String, _ variables: [String: String]) async throws -> Payload {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, status) = try await transport.post(URL(string: "https://api.github.com/graphql")!, body: body, token: token)
        try Self.check(status)
        guard let envelope = try? GitHubWire.decoder.decode(Envelope<Payload>.self, from: data) else {
            throw GitHubProjectError.unavailable(status)
        }
        if let errors = envelope.errors, !errors.isEmpty {
            if errors.contains(where: { $0.type == "RATE_LIMITED" }) { throw GitHubProjectError.rateLimited }
            if errors.contains(where: { $0.type == "NOT_FOUND" }) { throw GitHubProjectError.notFound }
        }
        guard let payload = envelope.data else { throw GitHubProjectError.unavailable(status) }
        return payload
    }

    // MARK: REST

    public func history(branch: String, page: Int) async throws -> [GitHubCommitItem] {
        let url = GitHubAPI.url("/repos/\(repo)/commits", query: [("sha", branch), ("per_page", "30"), ("page", "\(page)")])
        let (data, status) = try await transport.get(url, token: token)
        if status == 409 { return [] }   // an empty repository
        try Self.check(status)
        return (try? GitHubWire.decoder.decode([GitHubCommitItem].self, from: data)) ?? []
    }

    /// The commits `head` has that `base` does not; none when the branch is gone.
    public func branchCommits(base: String, head: String) async throws -> [GitHubCommitItem] {
        struct Reply: Decodable { let commits: [GitHubCommitItem] }
        let url = GitHubAPI.url("/repos/\(repo)/compare/\(base)...\(head)")
        let (data, status) = try await transport.get(url, token: token)
        if status == 404 { return [] }
        try Self.check(status)
        return ((try? GitHubWire.decoder.decode(Reply.self, from: data))?.commits ?? []).reversed()
    }

    /// The README as text, or nil when there is none or it cannot be read.
    public func readme() async -> String? {
        struct Reply: Decodable { let content: String; let encoding: String }
        guard let (data, status) = try? await transport.get(GitHubAPI.url("/repos/\(repo)/readme"), token: token),
              status == 200, let reply = try? GitHubWire.decoder.decode(Reply.self, from: data),
              reply.encoding == "base64",
              let decoded = Data(base64Encoded: reply.content.replacingOccurrences(of: "\n", with: "")) else { return nil }
        return String(data: decoded, encoding: .utf8)
    }

    /// Every repo the person can see, 100 a page, up to 10 pages.
    public static func repos(transport: any GitHubTransport, token: String) async throws -> [GitHubRepoRef] {
        var all: [GitHubRepoRef] = []
        for page in 1...10 {
            let url = GitHubAPI.url("/user/repos", query: [
                ("per_page", "100"), ("page", "\(page)"), ("sort", "pushed"),
                ("affiliation", "owner,collaborator,organization_member"),
            ])
            let (data, status) = try await transport.get(url, token: token)
            try check(status)
            let batch = (try? GitHubWire.decoder.decode([GitHubRepoRef].self, from: data)) ?? []
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw GitHubProjectError.unauthorized
        case 403, 429: throw GitHubProjectError.rateLimited
        case 404: throw GitHubProjectError.notFound
        default: throw GitHubProjectError.unavailable(status)
        }
    }
}
```

The repos test's route is `"/user/repos?per_page=100&page=1"`, so keep `per_page` and `page` first in the query list, in that order.

`GitHubAPI.url` sets `components.path`, which percent-encodes `%`, space and `#` in the branch name; Review Focus 5's test pins that. If it fails, encode the head with `head.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "#%")))` and set `percentEncodedPath` instead.

- [ ] **Step 5: Run the tests**

Run: `cd LifeOSKit && swift test --filter "GitHubProjectSourceTests|GitHubDay" 2>&1 | tail -3`
Expected: all pass (the day card's tests still compile through the `post` default).

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/GitHubDayLoader.swift LifeOSKit/Sources/Integrations/GitHubProjectSource.swift LifeOSKit/Tests/IntegrationsTests/GitHubProjectSourceTests.swift
git commit -m "feat(integrations): read a repo's branches, PRs, history and README"
```

## Task 7: Refresh stages from GitHub

**Files:**
- Create: `LifeOSKit/Sources/Integrations/FeatureStageRefresher.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/FeatureStageRefresherTests.swift`

**Interfaces:**
- Consumes: Task 2 store (`features`, `updateFeature(branch:)`, `applyStage`), Task 5 resolver.
- Produces: `@MainActor public enum FeatureStageRefresher { @discardableResult static func apply(_ status: GitHubProjectStatus, repo: String, projectID: UUID, store: ProjectsStore, now: Date) throws -> Bool; static func candidates(for feature: FeatureSnapshot, in status: GitHubProjectStatus) -> [String] }`. `apply` auto-links unlinked features that have exactly one matching branch, then resolves and writes each stage; returns true when anything changed (so the caller syncs).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

@Suite @MainActor struct FeatureStageRefresherTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private func setUp() throws -> (ProjectsStore, UUID) {
        let store = ProjectsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
        let p = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: UUID())
        return (store, p)
    }
    private func status(_ branches: [String], pulls: [GitHubPullState] = []) -> GitHubProjectStatus {
        GitHubProjectStatus(defaultBranch: "main",
                            branches: branches.map { GitHubBranchState(name: $0, lastCommitAt: now, ahead: 3, behind: 0) },
                            pulls: pulls)
    }

    @Test func anUnlinkedFeatureLinksToItsOneBranchAndMoves() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Credit cards")
        let changed = try FeatureStageRefresher.apply(status(["main", "feat/credit-cards"]), repo: "o/r",
                                                      projectID: p, store: store, now: now)
        #expect(changed)
        let feature = try #require(try store.feature(id: f))
        #expect(feature.branch == "feat/credit-cards")
        #expect(feature.stage == .building)
    }

    @Test func severalMatchesLinkNone() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Credit cards")
        try FeatureStageRefresher.apply(status(["feat/credit-cards", "fix/credit-cards"]), repo: "o/r",
                                        projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.branch == nil)
        let feature = try #require(try store.feature(id: f))
        #expect(FeatureStageRefresher.candidates(for: feature, in: status(["feat/credit-cards", "fix/credit-cards"]))
                == ["feat/credit-cards", "fix/credit-cards"])
    }

    @Test func nothingChangedIsNothingToSync() throws {
        let (store, p) = try setUp()
        _ = try store.createFeature(projectID: p, title: "Widgets")
        try store.markSynced(at: now)
        let changed = try FeatureStageRefresher.apply(status(["main"]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(changed == false)
        #expect(try store.pending().isEmpty)
    }

    @Test func aMergedFeatureStaysDoneWhenItsBranchGoes() throws {
        let (store, p) = try setUp()
        let f = try store.createFeature(projectID: p, title: "Sign in", branch: "feat/sign-in")
        let merged = GitHubPullState(number: 40, title: "Sign in", state: .merged, url: URL(string: "https://x")!,
                                     mergedAt: now, headBranch: "feat/sign-in", headRepo: "o/r")
        try FeatureStageRefresher.apply(status(["main"], pulls: [merged]), repo: "o/r", projectID: p, store: store, now: now)
        #expect(try store.feature(id: f)?.stage == .done)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter FeatureStageRefresherTests 2>&1 | tail -3`
Expected: build failure, no `FeatureStageRefresher`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Persistence

/// Applies one read of the repo to a project's features: links the ones
/// with exactly one branch named for them, then writes each stage.
@MainActor
public enum FeatureStageRefresher {
    @discardableResult
    public static func apply(_ status: GitHubProjectStatus, repo: String, projectID: UUID,
                             store: ProjectsStore, now: Date) throws -> Bool {
        var changed = false
        let names = status.branches.map(\.name).filter { $0 != status.defaultBranch }
        for feature in try store.features(projectID: projectID) {
            var branch = feature.branch
            if branch == nil, case .one(let match) = FeatureStageRefresher.link(feature, names) {
                try store.updateFeature(id: feature.id, branch: .some(match))
                branch = match
                changed = true
            }
            let resolved = FeatureStageResolver.resolve(branch: branch, repo: repo, status: status, now: now)
            if try store.applyStage(featureID: feature.id, stage: resolved.stage, detail: resolved.detail,
                                    prNumber: resolved.prNumber, checkedAt: now) {
                changed = true
            }
        }
        return changed
    }

    /// The branches a feature could link to when more than one is named for it.
    public static func candidates(for feature: FeatureSnapshot, in status: GitHubProjectStatus) -> [String] {
        switch link(feature, status.branches.map(\.name)) {
        case .several(let names): names
        case .one(let name): [name]
        case .none: []
        }
    }

    private static func link(_ feature: FeatureSnapshot, _ branches: [String]) -> BranchLink {
        FeatureStageResolver.link(title: feature.title, branches: branches)
    }
}
```

- [ ] **Step 4: Run the tests, then the package**

Run: `cd LifeOSKit && swift test --filter FeatureStageRefresherTests 2>&1 | tail -3 && swift test 2>&1 | grep -E "Test run with" | tail -1`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/FeatureStageRefresher.swift LifeOSKit/Tests/IntegrationsTests/FeatureStageRefresherTests.swift
git commit -m "feat(integrations): link features to their branches and write their stages"
```

## Task 8: GitHub in the app

**Files:**
- Modify: `LIfeOS/Features/Settings/ViewModel/GitHubConnectionViewModel.swift` (expose the connection; repos via the source)
- Create: `LIfeOS/Features/Projects/ViewModel/ProjectGitHubModel.swift`
- Create: `LIfeOS/Features/Projects/View/ProjectGitHubView.swift`
- Modify: `LIfeOS/Features/Projects/View/ProjectScreen.swift` (GitHub pane, refresh loop, "as of" header, feature commits)
- Modify: `LIfeOS/Features/Projects/View/FeatureDetailView.swift` (suggested branch, branch picker)
- Modify: `LIfeOS/Features/Projects/View/ProjectsHomeScreen.swift` (feature progress and last commit on cards)
- Modify: `LIfeOS/Features/Projects/View/NewProjectSheet.swift` (repo search)
- Modify: `LIfeOS/Features/Projects/View/ProjectsDesignPreview.swift` (`project-github` page with a fixture status)
- Test: `LIfeOSUITests/ProjectGitHubUITests.swift` (new; register in the pbxproj)

**Interfaces:**
- Consumes: Tasks 5–7.
- Produces:
  - `GitHubConnectionViewModel.connection: GitHubConnection?` (`tokens.load()` when connected and not `needsReconnect`), and `markNeedsReconnect()`.
  - `@MainActor @Observable final class ProjectGitHubModel { enum Problem { notConnected, noAccess, reconnect, rateLimited, unavailable }; private(set) var status: GitHubProjectStatus?; private(set) var problem: Problem?; private(set) var history: [GitHubCommitItem]; private(set) var historyDone: Bool; init(repo: String, github: GitHubConnectionViewModel?, transport: any GitHubTransport = URLSessionGitHubTransport()); init(fixture: GitHubProjectStatus, history: [GitHubCommitItem]); func refresh(force: Bool) async; func loadMoreHistory() async; func commits(for branch: String) async -> [GitHubCommitItem]; static func cached(_ repo: String) -> GitHubProjectStatus? }`

- [ ] **Step 1: Write the failing UI test**

```swift
import XCTest

/// The GitHub view and the Plan's GitHub lines on preview pages whose model
/// is built from a fixture status: branches feat/credit-cards (5 ahead) and
/// old/spike (no commit in 40 days), PR #42 open, PR #40 merged.
@MainActor
final class ProjectGitHubUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testTheGitHubViewListsCommitsBranchesAndPRs() {
        let app = launch("project-github")
        XCTAssertTrue(app.staticTexts["COMMITS"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["feat: cards in Settings"].exists)
        XCTAssertTrue(app.staticTexts["feat/credit-cards"].exists)
        XCTAssertTrue(app.staticTexts["5 ahead · 0 behind"].exists)
        XCTAssertTrue(app.staticTexts["#42 Credit cards"].exists)
    }

    func testAFeaturePageShowsTheSuggestedBranch() {
        let app = launch("project-plan")
        let row = app.buttons["Widgets"]
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(app.textFields["Branch name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.textFields["Branch name"].value as? String, "feat/widgets")
    }
}
```

Register with the same `addtest.rb` as Task 4. Run it and see it fail (no `project-github` page).

- [ ] **Step 2: Expose the connection**

In `GitHubConnectionViewModel.swift`, beside `contributions()`:

```swift
    /// The token for a project's own reads, while the connection is good.
    var connection: GitHubConnection? {
        guard case .connected = state, !needsReconnect else { return nil }
        return tokens.load()
    }

    func markNeedsReconnect() {
        defaults.set(true, forKey: GitHubDaySource.needsReconnectKey)
        needsReconnect = true
    }
```

Replace the body of `loadRepos()` so it uses every page:

```swift
    func loadRepos() async {
        guard let connection = tokens.load() else { return }
        do {
            repos = try await GitHubProjectSource.repos(transport: transport, token: connection.token)
        } catch GitHubProjectError.unauthorized {
            markNeedsReconnect()
        } catch {
            githubLog.error("github repos failed: \(error)")
        }
    }
```

- [ ] **Step 3: The project's GitHub model**

Create `LIfeOS/Features/Projects/ViewModel/ProjectGitHubModel.swift`:

```swift
import Foundation
import Observation
import OSLog
import Integrations

private let projectGitHubLog = Logger(subsystem: "com.shivvyas.lifeos", category: "github")

/// One project's repo as last read: status for stages and branches, and the
/// default branch's history page by page. Reads are cached per repo for five
/// minutes so moving between views does not read again.
@MainActor @Observable
final class ProjectGitHubModel {
    enum Problem: Equatable { case notConnected, noAccess, reconnect, rateLimited, unavailable }

    private(set) var status: GitHubProjectStatus?
    private(set) var problem: Problem?
    private(set) var fetchedAt: Date?
    private(set) var history: [GitHubCommitItem] = []
    private(set) var historyDone = false

    let repo: String
    private weak var github: GitHubConnectionViewModel?
    private let transport: any GitHubTransport
    private let isFixture: Bool
    private var historyPage = 0

    private static var cache: [String: (status: GitHubProjectStatus, at: Date)] = [:]
    static func cached(_ repo: String) -> GitHubProjectStatus? { cache[repo.lowercased()]?.status }

    init(repo: String, github: GitHubConnectionViewModel?, transport: any GitHubTransport = URLSessionGitHubTransport()) {
        self.repo = repo; self.github = github; self.transport = transport; self.isFixture = false
    }

    /// Previews and UI tests: a fixed read, no network.
    init(fixture: GitHubProjectStatus, history: [GitHubCommitItem], repo: String = "shivvyas2/LifeOS") {
        self.repo = repo; self.github = nil; self.transport = URLSessionGitHubTransport(); self.isFixture = true
        self.status = fixture; self.history = history; self.historyDone = true; self.fetchedAt = .now
    }

    private var source: GitHubProjectSource? {
        guard let connection = github?.connection else { return nil }
        return GitHubProjectSource(transport: transport, token: connection.token, repo: repo)
    }

    func refresh(force: Bool = false) async {
        guard !isFixture else { return }
        let key = repo.lowercased()
        if !force, let hit = Self.cache[key], Date.now.timeIntervalSince(hit.at) < 300 {
            status = hit.status; fetchedAt = hit.at; problem = nil
            return
        }
        guard let source else { problem = .notConnected; return }
        do {
            let read = try await source.status()
            Self.cache[key] = (read, .now)
            status = read; fetchedAt = .now; problem = nil
        } catch GitHubProjectError.unauthorized {
            github?.markNeedsReconnect(); problem = .reconnect
        } catch GitHubProjectError.notFound {
            problem = .noAccess
        } catch GitHubProjectError.rateLimited {
            problem = .rateLimited
        } catch {
            projectGitHubLog.error("project status failed: \(String(describing: error))")
            problem = .unavailable
        }
    }

    func loadMoreHistory() async {
        guard !isFixture, !historyDone, let source, let branch = status?.defaultBranch else { return }
        historyPage += 1
        do {
            let page = try await source.history(branch: branch, page: historyPage)
            history += page
            historyDone = page.count < 30
        } catch {
            historyPage -= 1
            projectGitHubLog.error("project history failed: \(String(describing: error))")
        }
    }

    func commits(for branch: String) async -> [GitHubCommitItem] {
        guard let source, let base = status?.defaultBranch else { return [] }
        return (try? await source.branchCommits(base: base, head: branch)) ?? []
    }

    func readme() async -> String? { await source?.readme() }
}
```

- [ ] **Step 4: The GitHub view**

Create `LIfeOS/Features/Projects/View/ProjectGitHubView.swift`:

```swift
import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// The repo as it stands: history, branches and pull requests.
struct ProjectGitHubView: View {
    @Bindable var github: ProjectGitHubModel
    let features: [FeatureSnapshot]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let problem = github.problem { ProjectGitHubProblem(problem: problem) }

            VStack(alignment: .leading, spacing: Space.x1) {
                Text("COMMITS").brutalLabel()
                if github.history.isEmpty && github.historyDone {
                    Text("No commits yet.").font(LifeOSType.secondary)
                }
                ForEach(github.history, id: \.sha) { commit in
                    Button { openURL(commit.htmlUrl) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.subject).font(LifeOSType.rowTitle).lineLimit(2)
                            Text("\(commit.authorName) · \(GitHubRelative.short(commit.date, now: .now)) · \(commit.shortSHA)")
                                .font(LifeOSType.caption.monospaced()).foregroundStyle(Editorial.quietInk(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .onAppear { if commit.sha == github.history.last?.sha { Task { await github.loadMoreHistory() } } }
                }
            }
            .brutalCard()
            .task { if github.history.isEmpty { await github.loadMoreHistory() } }

            VStack(alignment: .leading, spacing: Space.x1) {
                Text("BRANCHES").brutalLabel()
                ForEach(github.status?.branches ?? [], id: \.name) { branch in
                    let stale = branch.lastCommitAt.map { Date.now.timeIntervalSince($0) > 30 * 86_400 } ?? true
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(branch.name).font(LifeOSType.rowTitle.monospaced())
                            Spacer()
                            if let feature = features.first(where: { $0.branch == branch.name }) {
                                Text(feature.title.uppercased()).font(LifeOSType.caption.weight(.heavy))
                            }
                        }
                        Text("\(branch.ahead) ahead · \(branch.behind) behind"
                             + (branch.lastCommitAt.map { " · " + GitHubRelative.short($0, now: .now) } ?? ""))
                            .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    .opacity(stale ? 0.45 : 1)
                }
            }
            .brutalCard()

            VStack(alignment: .leading, spacing: Space.x1) {
                Text("PULL REQUESTS").brutalLabel()
                let pulls = github.status?.pulls ?? []
                let open = pulls.filter { $0.state == .open }
                let merged = pulls.filter { $0.state == .merged }.prefix(5)
                ForEach(open + merged, id: \.number) { pull in
                    Button { openURL(pull.url) } label: {
                        HStack {
                            Text("#\(pull.number) \(pull.title)").font(LifeOSType.rowTitle).lineLimit(1)
                            Spacer()
                            Text(pull.state == .open ? "OPEN" : "MERGED").font(LifeOSType.caption.weight(.heavy))
                        }
                    }
                    .buttonStyle(.plain)
                }
                if pulls.isEmpty { Text("No pull requests yet.").font(LifeOSType.secondary) }
            }
            .brutalCard()
        }
    }
}

/// One line saying why the repo could not be read, and what to do.
struct ProjectGitHubProblem: View {
    let problem: ProjectGitHubModel.Problem
    var body: some View {
        Text(message).font(LifeOSType.secondary).brutalCard()
    }
    private var message: String {
        switch problem {
        case .notConnected: "Connect GitHub in Settings to update stages from your repo."
        case .noAccess: "This GitHub account cannot see the repo."
        case .reconnect: "GitHub needs you to sign in again, in Settings."
        case .rateLimited: "GitHub asked to slow down. Showing the last read."
        case .unavailable: "GitHub could not be reached. Showing the last read."
        }
    }
}
```

- [ ] **Step 5: Wire it into the project screen**

In `ProjectScreen.swift`:

1. `Pane` gains `case github = "GITHUB"` last. Make the picker iterate `visiblePanes`: `Pane.allCases.filter { $0 != .github || project?.repo != nil }`.
2. Add `@Environment(\.github) private var githubConnection` and `@State private var github: ProjectGitHubModel?`. Add an initializer parameter `github: ProjectGitHubModel? = nil` stored in `_github = State(initialValue: github)` for previews.
3. Refresh loop on the screen:

```swift
        .task(id: project?.repo) {
            guard let repo = project?.repo else { github = nil; return }
            if github?.repo != repo { github = ProjectGitHubModel(repo: repo, github: githubConnection) }
            while !Task.isCancelled {
                await refreshStages(force: false)
                try? await Task.sleep(for: .seconds(300))
            }
        }
```

with:

```swift
    private func refreshStages(force: Bool) async {
        guard let github, let repo = project?.repo, let store = model.store else { return }
        await github.refresh(force: force)
        guard let status = github.status else { return }
        if (try? FeatureStageRefresher.apply(status, repo: repo, projectID: projectID, store: store, now: .now)) == true {
            model.syncAfterStages()
        }
        revision += 1
    }
```

and in `ProjectsViewModel`: `func syncAfterStages() { requestSync() }`.

4. `.refreshable { await model.refresh(); await refreshStages(force: true); revision += 1 }`.
5. Plan header: pass `header: { planGitHubLine }`:

```swift
    @ViewBuilder private var planGitHubLine: some View {
        if let github {
            if let problem = github.problem {
                ProjectGitHubProblem(problem: problem)
                if let checked = features.compactMap(\.stageCheckedAt).max() {
                    Text("As of \(GitHubRelative.short(checked, now: .now))").font(LifeOSType.caption)
                }
            } else if let fetched = github.fetchedAt {
                Text("From GitHub · \(GitHubRelative.short(fetched, now: .now))").font(LifeOSType.caption)
            }
        }
    }
```

6. Switch case: `case .github: if let github { ProjectGitHubView(github: github, features: features) }`.
7. In the feature destination, pass a `commits:` closure that shows `FeatureCommits`, defined as:

```swift
/// A feature's commits ahead of the default branch, and its PR.
struct FeatureCommits: View {
    let github: ProjectGitHubModel?
    let feature: FeatureSnapshot?
    @State private var commits: [GitHubCommitItem] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let github, let feature, let branch = feature.branch {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("COMMITS ON \(branch.uppercased())").brutalLabel()
                if let number = feature.prNumber,
                   let pull = github.status?.pulls.first(where: { $0.number == number }) {
                    Button("PR #\(number): \(pull.title)") { openURL(pull.url) }.font(LifeOSType.rowTitle.weight(.heavy))
                }
                ForEach(commits, id: \.sha) { commit in
                    Text("\(commit.shortSHA) \(commit.subject)").font(LifeOSType.caption.monospaced()).lineLimit(1)
                }
                if commits.isEmpty { Text("None ahead of \(github.status?.defaultBranch ?? "main").").font(LifeOSType.caption) }
            }
            .brutalCard()
            .task(id: branch) { commits = await github.commits(for: branch) }
        }
    }
}
```

Put `FeatureCommits` at the bottom of `ProjectGitHubView.swift`. In `ProjectScreen` pass `commits: { FeatureCommits(github: github, feature: try? model.store?.feature(id: id)) }`.

- [ ] **Step 6: Suggested branch and the picker on the feature page**

In `FeatureDetailView`, declare `var candidates: [String] = []` and `var branches: [String] = []` directly after `let colour` and before `commits` (the memberwise initializer takes arguments in declaration order; the defaults keep slice 1's call sites compiling). Call it as `FeatureDetailView(model:featureID:colour:candidates:branches:commits:)`. In `.onAppear` set `branch = FeatureStageResolver.suggestedBranch(feature.title)`. Under the link row, when `feature.branch == nil`:

```swift
                        if !candidates.isEmpty {
                            Text("SEVERAL BRANCHES MATCH").font(LifeOSType.caption.weight(.heavy))
                        }
                        if !branches.isEmpty {
                            Menu("PICK A BRANCH") {
                                ForEach(candidates + branches.filter { !candidates.contains($0) }, id: \.self) { name in
                                    Button(name) { model.updateFeature(featureID, branch: .some(name)); revision += 1 }
                                }
                            }
                            .font(LifeOSType.label.weight(.heavy))
                        }
```

and a `COPY` button beside `LINK` that copies `branch`. From `ProjectScreen` pass `branches: github?.status?.branches.map(\.name).filter { $0 != github?.status?.defaultBranch } ?? []` and `candidates: feature.map { f in github?.status.map { FeatureStageRefresher.candidates(for: f, in: $0) } ?? [] } ?? []`.

- [ ] **Step 7: Home cards and the repo picker**

In `ProjectsHomeScreen.card(_:)`, after the task progress `HStack`:

```swift
            if let progress = try? model.store?.featureProgress(projectID: project.id), progress.total > 0 {
                HStack(spacing: Space.x2) {
                    BrutalProgress(fraction: progress.fraction, colour: colour)
                    Text("\(progress.done)/\(progress.total) FEATURES").font(LifeOSType.caption.weight(.heavy))
                }
            }
            if let repo = project.repo, let last = ProjectGitHubModel.cached(repo)?.lastCommitAt {
                Text("LAST COMMIT \(GitHubRelative.short(last, now: .now).uppercased())")
                    .font(LifeOSType.caption.weight(.heavy))
            }
```

and in the home's `.task(id:)` after `loadContributions`, read each linked repo once so the line can show:

```swift
            for repo in Set(model.projects.compactMap(\.repo)) {
                await ProjectGitHubModel(repo: repo, github: github).refresh()
            }
```

In `NewProjectSheet`, add `@State private var repoQuery = ""` and above the picker `TextField("Search repos", text: $repoQuery).textInputAutocapitalization(.never)`; filter the `ForEach` with `(github?.repos ?? []).filter { repoQuery.isEmpty || $0.fullName.localizedCaseInsensitiveContains(repoQuery) }`.

- [ ] **Step 8: The preview page**

In `ProjectsDesignPreview.swift`, give the `launch` project `repo: "shivvyas2/LifeOS"` and add a fixture model:

```swift
    static let githubFixture: ProjectGitHubModel = {
        let now = Date.now
        let status = GitHubProjectStatus(defaultBranch: "main", branches: [
            GitHubBranchState(name: "feat/credit-cards", lastCommitAt: now.addingTimeInterval(-7_200), ahead: 5, behind: 0),
            GitHubBranchState(name: "old/spike", lastCommitAt: now.addingTimeInterval(-40 * 86_400), ahead: 1, behind: 30),
        ], pulls: [
            GitHubPullState(number: 42, title: "Credit cards", state: .open, url: URL(string: "https://github.com")!,
                            mergedAt: nil, headBranch: "feat/credit-cards", headRepo: "shivvyas2/LifeOS"),
            GitHubPullState(number: 40, title: "Sign in", state: .merged, url: URL(string: "https://github.com")!,
                            mergedAt: now.addingTimeInterval(-3 * 86_400), headBranch: "feat/sign-in", headRepo: "shivvyas2/LifeOS"),
        ])
        let history = try! GitHubWire.decoder.decode([GitHubCommitItem].self, from: Data("""
        [{"sha":"a1b2c3d4e5","html_url":"https://github.com","commit":{"message":"feat: cards in Settings","author":{"name":"Shiv","date":"2026-10-07T10:00:00Z"}}}]
        """.utf8))
        return ProjectGitHubModel(fixture: status, history: history)
    }()
```

Pages: `case "project-github": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .github, github: Self.githubFixture)`, and pass `github: Self.githubFixture` on `project-plan` too.

- [ ] **Step 9: Build and run the UI tests**

Run: `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=<iPhone simulator id>' -only-testing:LIfeOSUITests/ProjectGitHubUITests -only-testing:LIfeOSUITests/ProjectPlanUITests -only-testing:LIfeOSUITests/ProjectsUITests 2>&1 | grep -E "Test Case|Executed|error:" | head -20`
Expected: all pass, with the executed count matching the number of tests.

Then the iPad layout the spec asks for (list and feature page side by side). In `ProjectScreen`, when `layout.isRegular && pane == .plan`, render

```swift
HStack(alignment: .top, spacing: Space.x3) {
    planView.frame(maxWidth: 420)
    if let selected = openFeature {
        FeatureDetailView(model: model, featureID: selected, colour: colour,
                          candidates: candidates(for: selected), branches: branchNames,
                          commits: { FeatureCommits(github: github, feature: try? model.store?.feature(id: selected)) })
    } else {
        Text("Pick a feature to see its branch, commits and tasks.").font(LifeOSType.secondary).brutalCard()
    }
}
```

where `planView` is the `ProjectPlanView(...)` from the `.plan` case moved into a computed property, `branchNames` and `candidates(for:)` are the expressions from Step 6 lifted into helpers, and the `.navigationDestination(item: $openFeature)` only applies when `!layout.isRegular` (wrap it: `.navigationDestination(item: layout.isRegular ? .constant(nil) : $openFeature)`). Run the `project-plan` page on the iPad simulator (`xcrun simctl launch <iPad id> com.shivvyas.lifeos --design-preview --page=project-plan`), tap a feature, screenshot (`xcrun simctl io <iPad id> screenshot <path>`), and check the two columns.

- [ ] **Step 10: Commit and open the slice 2 PR**

```bash
git add LIfeOS LIfeOSUITests/ProjectGitHubUITests.swift LIfeOS.xcodeproj/project.pbxproj
git commit -m "feat(projects): stages from GitHub, the GitHub view, and progress on the cards"
```

Push `feat/project-features-github`, PR "Projects: feature stages and the GitHub view", based on slice 1's branch until that merges. No owner step.

---

# Slice 3: Draft with LIFO

Branch `feat/project-features-draft` from the slice 2 tip.

## Task 9: The `plan` task in `lifo-agent`

**Files:**
- Modify: `supabase/functions/_shared/lifo.ts`
- Modify: `supabase/functions/lifo-agent/index.ts`
- Test: `supabase/functions/_shared/lifo_test.ts`

**Interfaces:**
- Produces: task `plan` (request `{task: "plan", prompt}`, reply `{output: {features: [{title, note, branch, milestone}]}, tokens}`); `export const PLAN_TOKEN_CAP = 60_000`; `export const MAX_PLAN_PROMPT = 12_000`; `export function usageKind(parsed): "chat" | "plan"`; `export function usageCap(kind): number`; `export function cleanPlan(output): {features: ...}`.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/functions/_shared/lifo_test.ts` (add `cleanPlan, MAX_PLAN_PROMPT, PLAN_TOKEN_CAP, usageCap, usageKind, parseRequest, taskConfig` to its import from `./lifo.ts`, keeping what is already imported):

```ts
Deno.test("plan is a task with a schema", () => {
  const config = taskConfig("plan");
  assertEquals(config?.maxTokens, 6_000);
  assertEquals((config?.schema as { required: string[] }).required, ["features"]);
});

Deno.test("a plan prompt over the cap is refused", () => {
  assertEquals(parseRequest({ task: "plan", prompt: "x".repeat(MAX_PLAN_PROMPT + 1) }), null);
  assertEquals(parseRequest({ task: "plan", prompt: "Scope: ship it" })?.kind, "prompt");
});

Deno.test("plans are billed to their own allowance", () => {
  assertEquals(usageKind({ kind: "prompt", task: "plan", prompt: "p" }), "plan");
  assertEquals(usageKind({ kind: "prompt", task: "answer", prompt: "p" }), "chat");
  assertEquals(usageCap("plan"), PLAN_TOKEN_CAP);
  assertEquals(PLAN_TOKEN_CAP, 60_000);
});

Deno.test("a plan is trimmed to the server's limits and to twelve", () => {
  const long = "é".repeat(100);
  const features = Array.from({ length: 15 }, (_, i) => ({
    title: i === 0 ? long : ` Feature ${i} `, note: "n".repeat(400), branch: `feat/f-${i}`, milestone: "",
  }));
  features.push({ title: "   ", note: "", branch: "", milestone: "" });
  const cleaned = cleanPlan({ features });
  assertEquals(cleaned.features.length, 12);
  assertEquals([...cleaned.features[0].title].length, 80);
  assertEquals(cleaned.features[1].title, "Feature 1");
  assertEquals(cleaned.features[1].note.length, 280);
});

Deno.test("an empty plan is an error, not an empty list", () => {
  assertThrows(() => cleanPlan({ features: [{ title: " ", note: "", branch: "", milestone: "" }] }));
  assertThrows(() => cleanPlan({ features: "nope" }));
});
```

Import `assertThrows` from `jsr:@std/assert@1` beside `assertEquals`.

- [ ] **Step 2: Run them to see them fail**

Run: `cd supabase/functions && deno test _shared/lifo_test.ts 2>&1 | tail -5`
Expected: FAIL (`cleanPlan` not exported).

- [ ] **Step 3: Implement in `lifo.ts`**

Add to `TASKS`:

```ts
  plan: {
    system: `You plan software projects for one developer. From the project's
name, scope, dates, milestones, README and recent commit subjects, list the
features to build, in the order to build them. Each feature is something a
person can see working when it is done, small enough for one branch and one
pull request. Give 3 to 12. For each: a title of at most 8 words, a one
sentence note, a branch name of the form feat/<words-with-dashes>, and the
title of the milestone it belongs to from the given list, or an empty string.
Do not repeat work the commits show is already done. If the owner adds a
nudge, follow it.`,
    maxTokens: 6_000,
    schema: {
      type: "object",
      properties: {
        features: {
          type: "array",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              note: { type: "string" },
              branch: { type: "string" },
              milestone: { type: "string" },
            },
            required: ["title", "note", "branch", "milestone"],
            additionalProperties: false,
          },
        },
      },
      required: ["features"],
      additionalProperties: false,
    },
  },
```

Teach `validateShape` arrays: in its loop, add before the `else` branch:

```ts
    } else if (declaredType === "array") {
      if (!Array.isArray(value)) throw new Error(`output missing required property "${key}"`);
```

Add, near `NUDGE_TOKEN_CAP`:

```ts
/// Ten drafts a day at the task's ceiling, kept apart from chat so planning
/// a project never eats the evening's coaching.
export const PLAN_TOKEN_CAP = 60_000;
export const MAX_PLAN_PROMPT = 12_000;

type Parsed = NonNullable<ReturnType<typeof parseRequest>>;

export function usageKind(parsed: Parsed | { kind: "prompt"; task: string; prompt: string }): "chat" | "plan" {
  return parsed.kind === "prompt" && parsed.task === "plan" ? "plan" : "chat";
}

export function usageCap(kind: "chat" | "plan"): number {
  return kind === "plan" ? PLAN_TOKEN_CAP : DAILY_TOKEN_CAP;
}

/// Cuts a plan to what the features table accepts (title 80, note 280,
/// branch 255, counted in code points like char_length) and to twelve.
export function cleanPlan(output: Record<string, unknown>) {
  if (!Array.isArray(output.features)) throw new Error("plan without features");
  const cut = (value: unknown, max: number) => [...String(value ?? "").trim()].slice(0, max).join("");
  const features = output.features
    .map((raw) => {
      const item = (raw ?? {}) as Record<string, unknown>;
      return {
        title: cut(item.title, 80),
        note: cut(item.note, 280),
        branch: cut(item.branch, 255),
        milestone: cut(item.milestone, 80),
      };
    })
    .filter((item) => item.title.length > 0)
    .slice(0, 12);
  if (features.length === 0) throw new Error("empty plan");
  return { features };
}
```

In `parseRequest`, after `if (!prompt) return null;`: `if (task === "plan" && prompt.length > MAX_PLAN_PROMPT) return null;`

- [ ] **Step 4: Use them in `lifo-agent/index.ts`**

- Import `cleanPlan, usageCap, usageKind` from `../_shared/lifo.ts`.
- After `parsed` is known: `const kind = usageKind(parsed);`
- In the usage lookup replace `.eq("kind", "chat")` with `.eq("kind", kind)` and the cap check with `if ((usage?.tokens ?? 0) >= usageCap(kind)) return json({ error: "exhausted" }, 429);`. Update the comment above it: chat, nudges and plans each have their own allowance.
- In `debit`, `p_kind: kind`.
- In the one-shot success path: `const { output } = parseOutput(parsed.task, reply);` then `const shaped = parsed.task === "plan" ? cleanPlan(output) : output;` and return `json({ output: shaped, tokens }, 200)`. A thrown `cleanPlan` falls into the existing `catch` and becomes `upstream_failure` (502), after the debit, as the comment there requires.

- [ ] **Step 5: Run the tests and type-check**

Run: `cd supabase/functions && deno test _shared/lifo_test.ts 2>&1 | tail -3 && deno check lifo-agent/index.ts`
Expected: all pass; `Check lifo-agent/index.ts` clean.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/lifo.ts supabase/functions/_shared/lifo_test.ts supabase/functions/lifo-agent/index.ts
git commit -m "feat(lifo): draft a project's features, on their own daily allowance"
```

## Task 10: The draft request on the phone

**Files:**
- Create: `LifeOSKit/Sources/Insights/Engines/PlanDraft.swift`
- Test: `LifeOSKit/Tests/InsightsTests/PlanDraftTests.swift`

**Interfaces:**
- Consumes: `RemoteWire.request(baseURL:anonKey:accessToken:taskName:prompt:)`, `RemoteWire.result(data:status:)`, `RemoteEngineError`.
- Produces: `public struct PlanDraft: Decodable, Equatable, Sendable { public var features: [Item] }` with `Item: Identifiable` (`id` not decoded) `title, note, branch, milestone`; `public enum PlanPrompt { static func make(name:scope:startsOn:endsOn:milestones:readme:commits:nudge:) -> String }`; `public enum PlanDrafter { static func draft(prompt: String, baseURL: URL, anonKey: String, accessToken: String, session: URLSession = .shared) async throws -> PlanDraft }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Insights

@Suite struct PlanDraftTests {
    @Test func thePromptCarriesTheProjectAndStaysUnderTheCap() {
        let prompt = PlanPrompt.make(
            name: "LifeOS", scope: "Ship credit cards", startsOn: nil, endsOn: nil, milestones: ["Alpha", "Beta"],
            readme: String(repeating: "r", count: 20_000), commits: (0..<50).map { "commit \($0)" },
            nudge: String(repeating: "n", count: 500))
        #expect(prompt.contains("Project: LifeOS"))
        #expect(prompt.contains("Scope: Ship credit cards"))
        #expect(prompt.contains("Milestones: Alpha; Beta"))
        #expect(prompt.contains("commit 19") && !prompt.contains("commit 20"))
        #expect(!prompt.contains(String(repeating: "r", count: 6_001)))
        #expect(!prompt.contains(String(repeating: "n", count: 201)))
        #expect(prompt.count <= 12_000)
    }

    @Test func noRepoMeansNoRepoSection() {
        let prompt = PlanPrompt.make(name: "P", scope: "S", startsOn: nil, endsOn: nil, milestones: [],
                                     readme: nil, commits: [], nudge: nil)
        #expect(!prompt.contains("README"))
        #expect(!prompt.contains("Recent commits"))
        #expect(!prompt.contains("Nudge"))
    }

    @Test func aDraftDecodesWithFreshIDs() throws {
        let data = Data(#"{"output":{"features":[{"title":"Sign in","note":"Apple","branch":"feat/sign-in","milestone":""},{"title":"Cards","note":"","branch":"feat/cards","milestone":"Alpha"}]},"tokens":10}"#.utf8)
        let draft: PlanDraft = try RemoteWire.result(data: data, status: 200)
        #expect(draft.features.map(\.title) == ["Sign in", "Cards"])
        #expect(draft.features[0].id != draft.features[1].id)
        #expect(draft.features[1].milestone == "Alpha")
    }

    @Test func theAllowanceIsItsOwnError() {
        #expect(throws: RemoteEngineError.exhausted) {
            let _: PlanDraft = try RemoteWire.result(data: Data(#"{"error":"exhausted"}"#.utf8), status: 429)
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter PlanDraftTests 2>&1 | tail -3`
Expected: build failure, no `PlanPrompt`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// A feature list LIFO drafted, for the owner to edit before anything is kept.
public struct PlanDraft: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable, Identifiable {
        public var id = UUID()
        public var title: String
        public var note: String
        public var branch: String
        public var milestone: String
        enum CodingKeys: String, CodingKey { case title, note, branch, milestone }
        public init(title: String, note: String, branch: String, milestone: String) {
            self.title = title; self.note = note; self.branch = branch; self.milestone = milestone
        }
    }
    public var features: [Item]
}

/// What the phone tells LIFO about a project. Bounded here and again on the
/// server: README 6,000 characters, 20 commit subjects, nudge 200.
public enum PlanPrompt {
    public static func make(name: String, scope: String, startsOn: Date?, endsOn: Date?, milestones: [String],
                            readme: String?, commits: [String], nudge: String?) -> String {
        var lines = ["Project: \(name)", "Scope: \(scope.isEmpty ? "(none given)" : scope)"]
        if let startsOn, let endsOn {
            lines.append("Dates: \(startsOn.formatted(.iso8601.year().month().day())) to \(endsOn.formatted(.iso8601.year().month().day()))")
        }
        if !milestones.isEmpty { lines.append("Milestones: " + milestones.joined(separator: "; ")) }
        if let readme, !readme.isEmpty { lines.append("README:\n" + String(readme.prefix(6_000))) }
        if !commits.isEmpty {
            lines.append("Recent commits:\n" + commits.prefix(20).map { "- " + String($0.prefix(120)) }.joined(separator: "\n"))
        }
        if let nudge, !nudge.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Nudge from the owner: " + String(nudge.prefix(200)))
        }
        return String(lines.joined(separator: "\n\n").prefix(12_000))
    }
}

public enum PlanDrafter {
    public static func draft(prompt: String, baseURL: URL, anonKey: String, accessToken: String,
                             session: URLSession = .shared) async throws -> PlanDraft {
        let request = try RemoteWire.request(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken,
                                             taskName: "plan", prompt: prompt)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw RemoteEngineError.unavailable }
        return try RemoteWire.result(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
```

Check that `RemoteWire.result` unwraps `{output: ...}` (it decodes `Reply<T>` with `output`), which the decode test confirms.

- [ ] **Step 4: Run the tests**

Run: `cd LifeOSKit && swift test --filter PlanDraftTests 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/Engines/PlanDraft.swift LifeOSKit/Tests/InsightsTests/PlanDraftTests.swift
git commit -m "feat(insights): ask LIFO for a project's features"
```

## Task 11: Draft, edit, keep

**Files:**
- Modify: `LIfeOS/Features/Projects/ViewModel/ProjectsViewModel.swift` (`draftPlan`, `keepDraft`)
- Create: `LIfeOS/Features/Projects/View/PlanDraftSheet.swift`
- Modify: `LIfeOS/Features/Projects/View/ProjectScreen.swift` (Draft button in the Plan footer, sheet)
- Modify: `LIfeOS/Features/Projects/View/ProjectsDesignPreview.swift` (`project-draft` page with a fixed draft)
- Test: `LIfeOSUITests/PlanDraftUITests.swift` (new; register in the pbxproj)

**Interfaces:**
- Consumes: Task 10 (`PlanPrompt`, `PlanDrafter`, `PlanDraft`), Task 8 (`ProjectGitHubModel.readme()`, `history`).
- Produces: `ProjectsViewModel.draftPlan(projectID: UUID, nudge: String?, github: ProjectGitHubModel?) async -> Result<[PlanDraft.Item], DraftFailure>` with `enum DraftFailure: Error { case exhausted, refused(String), unavailable, notSignedIn }`; `ProjectsViewModel.keepDraft(_ items: [PlanDraft.Item], in projectID: UUID)`; `PlanDraftSheet(model:projectID:github:preset:)`.

- [ ] **Step 1: Write the failing UI test**

```swift
import XCTest

/// The draft sheet on the `project-draft` page, preset with three features
/// so no network is involved.
@MainActor
final class PlanDraftUITests: XCTestCase {
    func testEditingAndKeepingADraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=project-draft"]
        app.launch()
        let first = app.textFields["Feature 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 6))
        XCTAssertEqual(first.value as? String, "Sign in")
        app.buttons["Remove Widgets"].tap()
        XCTAssertFalse(app.textFields["Feature 3"].exists)
        app.buttons["Keep"].tap()
        XCTAssertTrue(app.staticTexts["0 OF 2 FEATURES DONE"].waitForExistence(timeout: 4))
    }
}
```

Register it, run it, see it fail.

- [ ] **Step 2: View model**

```swift
    enum DraftFailure: Error, Equatable { case exhausted, refused(String), unavailable, notSignedIn }

    func draftPlan(projectID: UUID, nudge: String?, github: ProjectGitHubModel?) async -> Result<[PlanDraft.Item], DraftFailure> {
        guard let store, let project = try? store.project(id: projectID),
              let base = AppConfig.supabaseURL, let anon = AppConfig.supabaseAnonKey,
              let token = KeychainAuthSessionStore().load()?.accessToken else { return .failure(.notSignedIn) }
        if let github, github.history.isEmpty { await github.loadMoreHistory() }
        let prompt = PlanPrompt.make(
            name: project.name, scope: project.scope, startsOn: project.startsOn, endsOn: project.endsOn,
            milestones: ((try? store.milestones(projectID: projectID)) ?? []).map(\.title),
            readme: await github?.readme(), commits: github?.history.map(\.subject) ?? [], nudge: nudge)
        do {
            return .success(try await PlanDrafter.draft(prompt: prompt, baseURL: base, anonKey: anon, accessToken: token).features)
        } catch RemoteEngineError.exhausted {
            return .failure(.exhausted)
        } catch RemoteEngineError.refused(let message) {
            return .failure(.refused(message))
        } catch {
            return .failure(.unavailable)
        }
    }

    /// Adds the kept features after any already planned, matching milestones by title.
    func keepDraft(_ items: [PlanDraft.Item], in projectID: UUID) {
        guard let store else { return }
        let milestones = (try? store.milestones(projectID: projectID)) ?? []
        for item in items where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let milestone = milestones.first { $0.title.caseInsensitiveCompare(item.milestone) == .orderedSame }?.id
            _ = try? store.createFeature(projectID: projectID, title: item.title, note: item.note,
                                         branch: item.branch.isEmpty ? nil : item.branch, milestoneID: milestone)
        }
        requestSync()
    }
```

Add `import Insights` to the file. Confirm the names `AppConfig.supabaseURL` / `supabaseAnonKey` (used by `loadNames()` in the same file).

- [ ] **Step 3: The sheet**

Create `LIfeOS/Features/Projects/View/PlanDraftSheet.swift`:

```swift
import SwiftUI
import DesignSystem
import Insights

/// LIFO's draft of a project's features, edited before anything is saved.
struct PlanDraftSheet: View {
    @Bindable var model: ProjectsViewModel
    let projectID: UUID
    let github: ProjectGitHubModel?
    /// Previews start from a fixed draft instead of asking LIFO.
    var preset: [PlanDraft.Item]? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var items: [PlanDraft.Item] = []
    @State private var drafting = false
    @State private var message: String?
    @State private var nudge = ""

    var body: some View {
        NavigationStack {
            List {
                if drafting {
                    HStack { ProgressView(); Text("LIFO is drafting the plan…") }
                }
                if let message { Text(message).font(LifeOSType.secondary) }
                ForEach(Array($items.enumerated()), id: \.element.id) { index, $item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Feature \(index + 1)", text: $item.title)
                                .font(LifeOSType.rowTitle.weight(.heavy))
                                .accessibilityLabel("Feature \(index + 1)")
                            Button { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(item.title)")
                        }
                        TextField("Note", text: $item.note, axis: .vertical).font(LifeOSType.secondary)
                        Text(item.branch).font(LifeOSType.caption.monospaced()).foregroundStyle(Editorial.quietInk(scheme))
                    }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                Section {
                    TextField("Nudge, e.g. smaller, or start with auth", text: $nudge)
                    Button("Redraft") { Task { await draft() } }.disabled(drafting)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Draft plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { model.keepDraft(items, in: projectID); dismiss() }
                        .disabled(items.isEmpty || drafting)
                }
            }
            .task {
                if let preset { items = preset } else { await draft() }
            }
        }
    }

    private func draft() async {
        drafting = true
        message = nil
        defer { drafting = false }
        switch await model.draftPlan(projectID: projectID, nudge: nudge.isEmpty ? nil : nudge, github: github) {
        case .success(let drafted): items = drafted
        case .failure(.exhausted): message = "That is today's drafts used up. Add features by hand, or draft again tomorrow."
        case .failure(.refused(let reason)): message = reason
        case .failure(.notSignedIn): message = "Sign in to draft with LIFO."
        case .failure(.unavailable): message = "LIFO could not be reached. Try again, or add features by hand."
        }
    }
}
```

- [ ] **Step 4: Wire it in**

In `ProjectScreen`: `@State private var drafting = false`; the Plan `footer` becomes:

```swift
                            footer: {
                                Button { drafting = true } label: {
                                    Text(features.isEmpty ? "DRAFT WITH LIFO" : "DRAFT MORE WITH LIFO")
                                        .font(LifeOSType.label.weight(.heavy))
                                        .frame(maxWidth: .infinity).padding(.vertical, Space.x1)
                                }
                                .buttonStyle(.plain)
                                .brutalCard()
                            }
```

and `.sheet(isPresented: $drafting, onDismiss: { revision += 1 }) { PlanDraftSheet(model: model, projectID: projectID, github: github) }`.

Add `var presetDraft: [PlanDraft.Item]? = nil` to `ProjectScreen`'s init, and when non-nil present the sheet on appear with `preset: presetDraft`, for the preview page.

- [ ] **Step 5: The preview page**

In `ProjectsDesignPreview.swift`, add `case "project-draft":` that shows the `design` project (no features) with:

```swift
ProjectScreen(model: fixture.model, projectID: fixture.design, initialPane: .plan, presetDraft: [
    .init(title: "Sign in", note: "Apple and email", branch: "feat/sign-in", milestone: ""),
    .init(title: "Case studies", note: "Three, with images", branch: "feat/case-studies", milestone: ""),
    .init(title: "Widgets", note: "", branch: "feat/widgets", milestone: ""),
])
```

(`fixture.design` must be stored on the fixture like `launch`; add `let design: UUID` and assign it where the project is created.)

- [ ] **Step 6: Build and run the UI tests**

Run: `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=<iPhone simulator id>' -only-testing:LIfeOSUITests/PlanDraftUITests -only-testing:LIfeOSUITests/ProjectPlanUITests 2>&1 | grep -E "Test Case|Executed|error:" | head`
Expected: all pass.

Then run the whole package and the whole UI test target once:
`cd LifeOSKit && swift test 2>&1 | grep "Test run with"` and `xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=<iPhone simulator id>' 2>&1 | grep -E "Executed|failed" | tail -3`.

- [ ] **Step 7: Commit and open the slice 3 PR**

```bash
git add LIfeOS LIfeOSUITests/PlanDraftUITests.swift LIfeOS.xcodeproj/project.pbxproj
git commit -m "feat(projects): draft a plan with LIFO, edit it, keep it"
```

Push `feat/project-features-draft`, PR "Projects: draft a plan with LIFO". Owner step: `supabase functions deploy lifo-agent`.
