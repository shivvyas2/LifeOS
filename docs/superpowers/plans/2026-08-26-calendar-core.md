# Calendar Core (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The calendar layer of the calendar-and-assistant project: EventKit events synced into a windowed SwiftData cache with dedup, pruning, and free-slot computation, fully tested with no simulator and no network.

**Architecture:** A `CalendarEvent` SwiftData model with a detached `Sendable` snapshot, a `@MainActor` `CalendarStore` over `ModelContext` for windowed queries, upsert by natural key `(source, sourceID)`, pruning, and free slots; a `CalendarSource` protocol in Integrations with `EventKitSource` behind it; a pure `CalendarMerge`; and a `CalendarSync` coordinator that fetches every authorized source, merges, applies to the store, and routes writes back to the owning source.

**Tech Stack:** Swift 6, SwiftData, EventKit, Swift Testing (`@Suite` / `#expect`), no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-25-calendar-and-assistant-design.md` (Sections 4, 5, 6, 15 Phase A, 16). Phase B (assistant), C (agenda card), D (Google) are out of scope here.

## Global Constraints

- Platforms: `.iOS("26.0")`, `.macOS("26.0")` (Package.swift already declares both; everything must compile for both, so no UIKit).
- Enums stored raw (`sourceRaw: String`) so cases can be added without a migration, matching `PlanEntry.kindRaw`.
- Nothing above `CalendarStore` holds a `CalendarEvent`; views and tools get `CalendarEventSnapshot` (Sendable) only.
- Sync window: 30 days back, 90 days forward, from `calendar.startOfDay(for: now)`.
- Dedup rule, verbatim from DayGuide: collision when `title.lowercased()` equal AND `startDate` equal; EventKit wins.
- All tests run under `swift test` in `LifeOSKit/` with no simulator and no network; `EKEventStore` is never instantiated in tests.
- Commits: conventional commits, no em dashes, no Co-Authored-By trailer. Work happens on a branch, never directly on main.
- The EventKit permission prompt is NEVER triggered at launch; Phase A only adds the capability (`requestAccess()`) and the usage string.

---

### Task 1: CalendarEvent model, snapshot, draft, and schema registration

**Files:**
- Create: `LifeOSKit/Sources/Persistence/CalendarEvent.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift` (schema array)
- Test: `LifeOSKit/Tests/PersistenceTests/CalendarEventTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `CalendarEventSource` (enum: `.eventKit`, `.google`), `CalendarEvent` (`@Model`), `CalendarEventSnapshot` (value type, `Equatable, Identifiable, Sendable`), `CalendarEventDraft` (value type, `Equatable, Sendable`), `CalendarEvent.snapshot() -> CalendarEventSnapshot`, `CalendarEvent.init(from: CalendarEventSnapshot)`. Every later task builds on these exact names.

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/PersistenceTests/CalendarEventTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarEventTests {
    @Test func aStoredEventRoundTripsThroughItsSnapshot() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_756_200_000)
        let snapshot = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-1",
            calendarTitle: "Home", title: "Dentist",
            startDate: start, endDate: start.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false,
            location: "12 Main St", notes: "bring card"
        )
        context.insert(CalendarEvent(from: snapshot))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CalendarEvent>())
        #expect(fetched.count == 1)
        #expect(fetched[0].snapshot() == snapshot)
    }

    @Test func anUnknownSourceRawFallsBackToEventKit() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_756_200_000)
        let event = CalendarEvent(from: CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "x",
            calendarTitle: "c", title: "t",
            startDate: start, endDate: start.addingTimeInterval(60),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        ))
        event.sourceRaw = "outlook"
        context.insert(event)
        #expect(event.source == .eventKit)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LifeOSKit && swift test --filter CalendarEventTests`
Expected: FAIL to compile with "cannot find 'CalendarEventSnapshot' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Persistence/CalendarEvent.swift
import Foundation
import SwiftData

public enum CalendarEventSource: String, Codable, Sendable, CaseIterable {
    case eventKit, google
}

/// Detached value form, safe to hand to a view or an assistant tool.
/// `Sendable` is the point: a tool result crosses into an engine, and a
/// `CalendarEvent` cannot make that trip because it is not Sendable.
public struct CalendarEventSnapshot: Equatable, Identifiable, Sendable {
    /// Local identity. Provisional when the snapshot comes from a provider
    /// fetch; `CalendarStore.apply` preserves the id of an existing row and
    /// only adopts this one for genuinely new events.
    public let id: UUID
    public let source: CalendarEventSource
    /// EKEvent.eventIdentifier, or the Google event id. Unique within a source.
    public let sourceID: String
    public let calendarTitle: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    /// One occurrence of a recurring series. Gated writes refuse these.
    public let isRecurring: Bool
    public let location: String?
    public let notes: String?

    public init(
        id: UUID, source: CalendarEventSource, sourceID: String,
        calendarTitle: String, title: String,
        startDate: Date, endDate: Date,
        isAllDay: Bool, isRecurring: Bool,
        location: String?, notes: String?
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.calendarTitle = calendarTitle
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isRecurring = isRecurring
        self.location = location
        self.notes = notes
    }
}

/// What a caller supplies to create or edit an event. No id, no source:
/// routing decides those.
public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?

    public init(
        title: String, startDate: Date, endDate: Date,
        isAllDay: Bool = false, location: String? = nil, notes: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

@Model
public final class CalendarEvent {
    public var id: UUID
    /// Stored raw so the enum can gain cases without a migration.
    public var sourceRaw: String
    public var sourceID: String
    public var calendarTitle: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var isRecurring: Bool
    public var location: String?
    public var notes: String?
    public var lastSyncedAt: Date

    public init(from snapshot: CalendarEventSnapshot, syncedAt: Date = .now) {
        self.id = snapshot.id
        self.sourceRaw = snapshot.source.rawValue
        self.sourceID = snapshot.sourceID
        self.calendarTitle = snapshot.calendarTitle
        self.title = snapshot.title
        self.startDate = snapshot.startDate
        self.endDate = snapshot.endDate
        self.isAllDay = snapshot.isAllDay
        self.isRecurring = snapshot.isRecurring
        self.location = snapshot.location
        self.notes = snapshot.notes
        self.lastSyncedAt = syncedAt
    }

    public var source: CalendarEventSource {
        get { CalendarEventSource(rawValue: sourceRaw) ?? .eventKit }
        set { sourceRaw = newValue.rawValue }
    }

    public func snapshot() -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: source, sourceID: sourceID,
            calendarTitle: calendarTitle, title: title,
            startDate: startDate, endDate: endDate,
            isAllDay: isAllDay, isRecurring: isRecurring,
            location: location, notes: notes
        )
    }
}
```

In `LifeOSContainer.swift`, add one line to the schema array after `CheckInAnswer.self`:

```swift
        CalendarEvent.self,
```

(`ChatMessage` belongs to Phase B, which registers it; Phase A does not create it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LifeOSKit && swift test --filter CalendarEventTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/CalendarEvent.swift LifeOSKit/Sources/Persistence/LifeOSContainer.swift LifeOSKit/Tests/PersistenceTests/CalendarEventTests.swift
git commit -m "feat(calendar): add the CalendarEvent model, snapshot, and draft"
```

---

### Task 2: CalendarStore windowed queries, upsert, and pruning

**Files:**
- Create: `LifeOSKit/Sources/Persistence/CalendarStore.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/CalendarStoreTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarEventSnapshot`, `CalendarEventSource` from Task 1.
- Produces: `CalendarStore` (`@MainActor` struct): `init(context: ModelContext, calendar: Calendar = .current)`, `events(from: Date, to: Date) throws -> [CalendarEventSnapshot]`, `snapshot(id: UUID) throws -> CalendarEventSnapshot?`, `apply(_ fetched: [CalendarEventSnapshot], window: DateInterval) throws`. Task 3 adds `freeSlots` to this same struct; Task 5 consumes all of it.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/PersistenceTests/CalendarStoreTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarStoreTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeStore() throws -> CalendarStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return CalendarStore(context: ModelContext(container), calendar: calendar)
    }

    private func snapshot(
        _ title: String, sourceID: String, start: Date,
        minutes: Double = 60, source: CalendarEventSource = .eventKit,
        allDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: title,
            startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            isAllDay: allDay, isRecurring: false, location: nil, notes: nil
        )
    }

    /// Day 0 of every test, away from DST transitions.
    private var noon: Date { Date(timeIntervalSince1970: 1_756_209_600) }
    private var window: DateInterval {
        DateInterval(
            start: calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: noon))!,
            end: calendar.date(byAdding: .day, value: 90, to: calendar.startOfDay(for: noon))!
        )
    }

    @Test func applyingTheSameFetchTwiceDoesNotDuplicate() throws {
        let store = try makeStore()
        let fetched = [snapshot("Standup", sourceID: "ek-1", start: noon)]

        try store.apply(fetched, window: window)
        try store.apply(fetched, window: window)

        let events = try store.events(from: window.start, to: window.end)
        #expect(events.count == 1)
    }

    @Test func applyPreservesTheLocalIDOfAnExistingRow() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let firstID = try store.events(from: window.start, to: window.end)[0].id

        // A re-fetch produces a fresh provisional UUID for the same event.
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let secondID = try store.events(from: window.start, to: window.end)[0].id
        #expect(firstID == secondID)
    }

    @Test func applyUpdatesChangedFieldsInPlace() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        try store.apply([snapshot("Standup (moved)", sourceID: "ek-1", start: noon.addingTimeInterval(1_800))], window: window)

        let events = try store.events(from: window.start, to: window.end)
        #expect(events.count == 1)
        #expect(events[0].title == "Standup (moved)")
    }

    @Test func inWindowRowsAbsentFromAFetchAreDeleted() throws {
        let store = try makeStore()
        try store.apply([
            snapshot("Keep", sourceID: "ek-1", start: noon),
            snapshot("Gone", sourceID: "ek-2", start: noon.addingTimeInterval(7_200)),
        ], window: window)

        try store.apply([snapshot("Keep", sourceID: "ek-1", start: noon)], window: window)

        let titles = try store.events(from: window.start, to: window.end).map(\.title)
        #expect(titles == ["Keep"])
    }

    @Test func outOfWindowRowsSurviveAnApply() throws {
        let store = try makeStore()
        let past = calendar.date(byAdding: .day, value: -45, to: noon)!
        try store.apply([snapshot("Old", sourceID: "ek-old", start: past)],
                        window: DateInterval(start: past.addingTimeInterval(-86_400), end: past.addingTimeInterval(86_400)))

        try store.apply([snapshot("New", sourceID: "ek-1", start: noon)], window: window)

        let all = try store.events(
            from: calendar.date(byAdding: .day, value: -60, to: noon)!,
            to: window.end
        )
        #expect(all.map(\.title).sorted() == ["New", "Old"])
    }

    @Test func windowQueriesIncludeEventsOverlappingTheEdges() throws {
        let store = try makeStore()
        let dayStart = calendar.startOfDay(for: noon)
        // Started yesterday 23:30, runs into today.
        let spanning = snapshot("Redeye", sourceID: "ek-1", start: dayStart.addingTimeInterval(-1_800))
        // All-day today.
        let allDay = snapshot("Birthday", sourceID: "ek-2", start: dayStart, minutes: 24 * 60, allDay: true)
        // Ends exactly at the window start: excluded, a zero-length overlap is no overlap.
        let before = snapshot("Earlier", sourceID: "ek-3", start: dayStart.addingTimeInterval(-3_600))
        try store.apply([spanning, allDay, before], window: window)

        let today = try store.events(from: dayStart, to: dayStart.addingTimeInterval(86_400))
        #expect(today.map(\.title) == ["Redeye", "Birthday"])
    }

    @Test func snapshotByIDFindsTheRow() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let id = try store.events(from: window.start, to: window.end)[0].id

        #expect(try store.snapshot(id: id)?.title == "Standup")
        #expect(try store.snapshot(id: UUID()) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CalendarStoreTests`
Expected: FAIL to compile with "cannot find 'CalendarStore' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Persistence/CalendarStore.swift
import Foundation
import SwiftData

/// Windowed reads and sync writes over the calendar cache. Never talks to a
/// provider; `CalendarSync` owns that side and feeds fetches through `apply`.
@MainActor
public struct CalendarStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Events overlapping the half-open interval `[from, to)`, sorted by start.
    /// Overlap is strict, so an event ending exactly at `from` is excluded.
    public func events(from: Date, to: Date) throws -> [CalendarEventSnapshot] {
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate < to && $0.endDate > from },
            sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor).map { $0.snapshot() }
    }

    public func snapshot(id: UUID) throws -> CalendarEventSnapshot? {
        try row(id: id)?.snapshot()
    }

    /// Reconciles one provider fetch into the cache.
    ///
    /// Matches on the natural key `(source, sourceID)`: an existing row is
    /// updated in place and keeps its local id, a new one adopts the
    /// snapshot's. Rows overlapping `window` whose key is absent from
    /// `fetched` are deleted, so deletions made in another app propagate.
    /// Rows outside the window are never touched.
    public func apply(_ fetched: [CalendarEventSnapshot], window: DateInterval, syncedAt: Date = .now) throws {
        let start = window.start
        let end = window.end
        let cached = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate < end && $0.endDate > start }
        ))
        var cachedByKey = Dictionary(
            cached.map { (Key(sourceRaw: $0.sourceRaw, sourceID: $0.sourceID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for snapshot in fetched {
            let key = Key(sourceRaw: snapshot.source.rawValue, sourceID: snapshot.sourceID)
            if let row = cachedByKey.removeValue(forKey: key) {
                row.calendarTitle = snapshot.calendarTitle
                row.title = snapshot.title
                row.startDate = snapshot.startDate
                row.endDate = snapshot.endDate
                row.isAllDay = snapshot.isAllDay
                row.isRecurring = snapshot.isRecurring
                row.location = snapshot.location
                row.notes = snapshot.notes
                row.lastSyncedAt = syncedAt
            } else {
                context.insert(CalendarEvent(from: snapshot, syncedAt: syncedAt))
            }
        }

        // Whatever remains was in the window but not in the fetch: deleted upstream.
        cachedByKey.values.forEach(context.delete)
        try context.save()
    }

    private func row(id: UUID) throws -> CalendarEvent? {
        try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private struct Key: Hashable {
        let sourceRaw: String
        let sourceID: String
    }
}
```

Note the subtlety the last test pins: a fetched snapshot whose window membership changed (an event moved out of the window by an update) is handled by `apply` receiving the whole window's fetch, so pruning is correct as long as callers always pass the full sync window, which `CalendarSync` (Task 5) does.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CalendarStoreTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/CalendarStore.swift LifeOSKit/Tests/PersistenceTests/CalendarStoreTests.swift
git commit -m "feat(calendar): cache events with windowed queries, upsert, and pruning"
```

---

### Task 3: Free-slot computation

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/CalendarStore.swift` (add one public method and one internal static helper)
- Test: `LifeOSKit/Tests/PersistenceTests/CalendarFreeSlotTests.swift`

**Interfaces:**
- Consumes: `CalendarStore.events(from:to:)` from Task 2.
- Produces: `CalendarStore.freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval]` and internal `CalendarStore.freeSlots(in:busy:durationMinutes:)` (pure, tested directly). Phase B's `find_free_time` tool calls the public one.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/PersistenceTests/CalendarFreeSlotTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite struct CalendarFreeSlotTests {
    private let dayStart = Date(timeIntervalSince1970: 1_756_166_400)
    private var dayEnd: Date { dayStart.addingTimeInterval(86_400) }
    private var day: DateInterval { DateInterval(start: dayStart, end: dayEnd) }

    private func busy(_ startHour: Double, _ endHour: Double) -> DateInterval {
        DateInterval(
            start: dayStart.addingTimeInterval(startHour * 3_600),
            end: dayStart.addingTimeInterval(endHour * 3_600)
        )
    }

    @Test func anEmptyDayIsOneFreeSlot() {
        let slots = CalendarStore.freeSlots(in: day, busy: [], durationMinutes: 30)
        #expect(slots == [day])
    }

    @Test func aFullyBookedDayHasNoSlots() {
        let slots = CalendarStore.freeSlots(in: day, busy: [busy(0, 24)], durationMinutes: 30)
        #expect(slots.isEmpty)
    }

    @Test func gapsShorterThanTheDurationAreNotOffered() {
        // Free 9-9:20 between meetings; a 30 minute ask must skip it.
        let slots = CalendarStore.freeSlots(
            in: DateInterval(start: busy(8, 9).start, end: busy(10, 11).end),
            busy: [busy(8, 9), busy(9.34, 10)],
            durationMinutes: 30
        )
        #expect(slots == [busy(10, 11)])
    }

    @Test func overlappingBusyIntervalsAreMergedBeforeSubtracting() {
        let slots = CalendarStore.freeSlots(
            in: day,
            busy: [busy(9, 11), busy(10, 12), busy(12, 13)],
            durationMinutes: 60
        )
        #expect(slots == [busy(0, 9), busy(13, 24)])
    }

    @Test func aKnownDayOfEventsYieldsTheExpectedGaps() {
        let slots = CalendarStore.freeSlots(
            in: day,
            busy: [busy(9, 9.5), busy(11, 12), busy(15, 16.5)],
            durationMinutes: 60
        )
        #expect(slots == [busy(0, 9), busy(9.5, 11), busy(12, 15), busy(16.5, 24)])
    }

    @Suite @MainActor struct StoreBacked {
        @Test func allDayEventsDoNotBlockTime() throws {
            let container = try LifeOSContainer.make(inMemory: true)
            let store = CalendarStore(context: ModelContext(container))
            let dayStart = Date(timeIntervalSince1970: 1_756_166_400)
            let window = DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
            let allDay = CalendarEventSnapshot(
                id: UUID(), source: .eventKit, sourceID: "ek-1",
                calendarTitle: "Cal", title: "Anniversary",
                startDate: dayStart, endDate: dayStart.addingTimeInterval(86_400),
                isAllDay: true, isRecurring: false, location: nil, notes: nil
            )
            try store.apply([allDay], window: window)

            let slots = try store.freeSlots(from: dayStart, to: window.end, durationMinutes: 30)
            #expect(slots == [window])
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CalendarFreeSlotTests`
Expected: FAIL to compile with "type 'CalendarStore' has no member 'freeSlots'".

- [ ] **Step 3: Write the implementation**

Append to `CalendarStore.swift`:

```swift
extension CalendarStore {
    /// Open intervals of at least `durationMinutes` inside `[from, to)`.
    /// All-day events do not block time: "Anniversary" is context, not a
    /// meeting, and treating it as busy would zero out the whole day.
    public func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval] {
        let busy = try events(from: from, to: to)
            .filter { !$0.isAllDay }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return Self.freeSlots(
            in: DateInterval(start: from, end: to),
            busy: busy,
            durationMinutes: durationMinutes
        )
    }

    /// Pure core: merge busy intervals, subtract from the window, drop gaps
    /// shorter than the requested duration.
    static func freeSlots(in window: DateInterval, busy: [DateInterval], durationMinutes: Int) -> [DateInterval] {
        let minimum = TimeInterval(durationMinutes * 60)
        var merged: [DateInterval] = []
        for interval in busy.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        var slots: [DateInterval] = []
        var cursor = window.start
        for interval in merged {
            let gapEnd = min(interval.start, window.end)
            if gapEnd.timeIntervalSince(cursor) >= minimum {
                slots.append(DateInterval(start: cursor, end: gapEnd))
            }
            cursor = max(cursor, interval.end)
            if cursor >= window.end { return slots }
        }
        if window.end.timeIntervalSince(cursor) >= minimum {
            slots.append(DateInterval(start: cursor, end: window.end))
        }
        return slots
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CalendarFreeSlotTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the whole Persistence suite to check nothing regressed**

Run: `cd LifeOSKit && swift test --filter PersistenceTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/CalendarStore.swift LifeOSKit/Tests/PersistenceTests/CalendarFreeSlotTests.swift
git commit -m "feat(calendar): compute free slots from the local cache"
```

---

### Task 4: CalendarSource protocol and CalendarMerge

**Files:**
- Create: `LifeOSKit/Sources/Integrations/CalendarSource.swift`
- Create: `LifeOSKit/Sources/Integrations/CalendarMerge.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/CalendarMergeTests.swift`

**Interfaces:**
- Consumes: `CalendarEventSnapshot`, `CalendarEventDraft`, `CalendarEventSource` from Task 1 (via `import Persistence`).
- Produces: `CalendarSource` protocol exactly as below (Task 5's fakes and Task 6's `EventKitSource` conform to it), and `CalendarMerge.merge(eventKit:google:) -> [CalendarEventSnapshot]`.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/IntegrationsTests/CalendarMergeTests.swift
import Testing
import Foundation
import Persistence
@testable import Integrations

@Suite struct CalendarMergeTests {
    private let start = Date(timeIntervalSince1970: 1_756_200_000)

    private func snapshot(
        _ title: String, source: CalendarEventSource, sourceID: String, start: Date
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: title,
            startDate: start, endDate: start.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
    }

    @Test func aCollisionOnTitleAndStartKeepsTheEventKitCopy() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("standup", source: .google, sourceID: "g-1", start: start)]
        )
        #expect(merged.count == 1)
        #expect(merged[0].source == .eventKit)
    }

    @Test func theTitleMatchIsCaseInsensitiveButTheStartMustBeEqual() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("Standup", source: .google, sourceID: "g-1", start: start.addingTimeInterval(60))]
        )
        #expect(merged.count == 2)
    }

    @Test func nonCollidingEventsFromBothSourcesAllSurvive() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("A", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("B", source: .google, sourceID: "g-1", start: start)]
        )
        #expect(merged.map(\.title).sorted() == ["A", "B"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CalendarMergeTests`
Expected: FAIL to compile with "cannot find 'CalendarMerge' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Integrations/CalendarSource.swift
import Foundation
import Persistence

/// One calendar provider. `EventKitSource` today, `GoogleCalendarSource` in
/// Phase D, fakes in tests. Everything above this protocol is provider-blind.
public protocol CalendarSource: Sendable {
    var source: CalendarEventSource { get }
    var isAuthorized: Bool { get async }
    func requestAccess() async throws -> Bool
    func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot]
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func delete(sourceID: String) async throws
}
```

```swift
// LifeOSKit/Sources/Integrations/CalendarMerge.swift
import Foundation
import Persistence

/// DayGuide's dedup rule, kept verbatim: two events collide when the
/// lowercased title and the start date are both equal. EventKit wins because
/// that copy is writable offline and is what the OS shows elsewhere. When the
/// user's Google account is also added under iOS Settings this rule is the
/// only thing preventing every event from appearing twice.
public enum CalendarMerge {
    public static func merge(
        eventKit: [CalendarEventSnapshot],
        google: [CalendarEventSnapshot]
    ) -> [CalendarEventSnapshot] {
        struct Key: Hashable {
            let title: String
            let start: Date
        }
        let taken = Set(eventKit.map { Key(title: $0.title.lowercased(), start: $0.startDate) })
        let unique = google.filter { !taken.contains(Key(title: $0.title.lowercased(), start: $0.startDate)) }
        return eventKit + unique
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CalendarMergeTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/CalendarSource.swift LifeOSKit/Sources/Integrations/CalendarMerge.swift LifeOSKit/Tests/IntegrationsTests/CalendarMergeTests.swift
git commit -m "feat(calendar): define the source protocol and the dedup merge"
```

---

### Task 5: CalendarSync

**Files:**
- Create: `LifeOSKit/Sources/Integrations/CalendarSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift`

**Interfaces:**
- Consumes: `CalendarSource`, `CalendarMerge` (Task 4); `CalendarStore.apply`, `.snapshot(id:)`, `.events` (Tasks 2-3); `CalendarEventDraft` (Task 1).
- Produces: `CalendarSync` (`@MainActor final class`): `init(sources: [any CalendarSource], store: CalendarStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now })`, `sync() async`, `create(_:) async throws`, `update(id:with:) async throws`, `delete(id:) async throws`, `CalendarSyncError` enum. Phase B's `CalendarWriting` protocol will be satisfied by these three write methods; Phase C calls `sync()` from `scenePhase`.

Design note: the spec says "actor". The store it drives is `@MainActor` (it owns a `ModelContext`), so the class is `@MainActor` instead, which serializes passes exactly the way the spec wants and matches how `WhoopSync` is wired.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift
import Testing
import Foundation
import SwiftData
import Persistence
@testable import Integrations

/// A scriptable source. `final class` with internal state guarded by
/// MainActor: every test and every CalendarSync call runs on MainActor.
@MainActor
final class FakeSource: CalendarSource, @unchecked Sendable {
    nonisolated let source: CalendarEventSource
    var authorized = true
    var fetchResult: Result<[CalendarEventSnapshot], Error> = .success([])
    var created: [CalendarEventDraft] = []
    var updated: [(sourceID: String, draft: CalendarEventDraft)] = []
    var deleted: [String] = []

    nonisolated init(source: CalendarEventSource) { self.source = source }

    var isAuthorized: Bool { authorized }
    func requestAccess() async throws -> Bool { authorized }
    func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot] {
        try fetchResult.get()
    }
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        created.append(draft)
        return snapshot(sourceID: "\(source.rawValue)-new-\(created.count)", draft: draft)
    }
    func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        updated.append((sourceID, draft))
        return snapshot(sourceID: sourceID, draft: draft)
    }
    func delete(sourceID: String) async throws { deleted.append(sourceID) }

    private func snapshot(sourceID: String, draft: CalendarEventDraft) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: draft.title,
            startDate: draft.startDate, endDate: draft.endDate,
            isAllDay: draft.isAllDay, isRecurring: false,
            location: draft.location, notes: draft.notes
        )
    }
}

@Suite @MainActor struct CalendarSyncTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_756_209_600)

    private func make() throws -> (CalendarSync, CalendarStore, FakeSource, FakeSource) {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = CalendarStore(context: ModelContext(container), calendar: calendar)
        let eventKit = FakeSource(source: .eventKit)
        let google = FakeSource(source: .google)
        let sync = CalendarSync(sources: [eventKit, google], store: store,
                                calendar: calendar, now: { [now] in now })
        return (sync, store, eventKit, google)
    }

    private func snapshot(
        _ title: String, source: CalendarEventSource, sourceID: String, start: Date
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: title,
            startDate: start, endDate: start.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
    }

    @Test func aThrowingSourceDoesNotBlockTheOthers() async throws {
        let (sync, store, eventKit, google) = try make()
        eventKit.fetchResult = .failure(URLError(.notConnectedToInternet))
        google.fetchResult = .success([snapshot("Kept", source: .google, sourceID: "g-1", start: now)])

        await sync.sync()

        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Kept"])
    }

    @Test func anUnauthorizedSourceIsSkippedEntirely() async throws {
        let (sync, store, eventKit, google) = try make()
        google.authorized = false
        google.fetchResult = .success([snapshot("Hidden", source: .google, sourceID: "g-1", start: now)])
        eventKit.fetchResult = .success([snapshot("Shown", source: .eventKit, sourceID: "ek-1", start: now)])

        await sync.sync()

        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Shown"])
    }

    @Test func collidingEventsAcrossSourcesAreDeduplicatedEventKitFirst() async throws {
        let (sync, store, eventKit, google) = try make()
        eventKit.fetchResult = .success([snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: now)])
        google.fetchResult = .success([snapshot("standup", source: .google, sourceID: "g-1", start: now)])

        await sync.sync()

        let events = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400))
        #expect(events.count == 1)
        #expect(events[0].source == .eventKit)
    }

    @Test func createDispatchesToTheFirstAuthorizedSourceAndResyncs() async throws {
        let (sync, store, eventKit, _) = try make()
        let draft = CalendarEventDraft(title: "Dentist", startDate: now, endDate: now.addingTimeInterval(3_600))
        // After the write, the provider fetch reflects the created event.
        eventKit.fetchResult = .success([snapshot("Dentist", source: .eventKit, sourceID: "ek-new-1", start: now)])

        try await sync.create(draft)

        #expect(eventKit.created.map(\.title) == ["Dentist"])
        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Dentist"])
    }

    @Test func updateRoutesToTheSourceOwningTheEvent() async throws {
        let (sync, store, eventKit, google) = try make()
        google.fetchResult = .success([snapshot("Gym", source: .google, sourceID: "g-1", start: now)])
        await sync.sync()
        let id = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400))[0].id

        let moved = CalendarEventDraft(title: "Gym", startDate: now.addingTimeInterval(7_200), endDate: now.addingTimeInterval(10_800))
        google.fetchResult = .success([snapshot("Gym", source: .google, sourceID: "g-1", start: moved.startDate)])
        try await sync.update(id: id, with: moved)

        #expect(google.updated.map(\.sourceID) == ["g-1"])
        #expect(eventKit.updated.isEmpty)
    }

    @Test func deleteOfAnUnknownIDThrows() async throws {
        let (sync, _, _, _) = try make()
        await #expect(throws: CalendarSyncError.unknownEvent) {
            try await sync.delete(id: UUID())
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CalendarSyncTests`
Expected: FAIL to compile with "cannot find 'CalendarSync' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Integrations/CalendarSync.swift
import Foundation
import Persistence

public enum CalendarSyncError: Error, Equatable {
    /// The id does not name a cached event. Ids only ever come from the
    /// store, so this is a caller bug or a stale reference, never user input.
    case unknownEvent
    /// No source is authorized to accept the write.
    case noWritableSource
}

/// Pulls every authorized source, merges, and reconciles the cache; routes
/// writes back to the source owning the event, then re-syncs so the cache
/// reflects what the provider actually stored (providers normalise all-day
/// handling and timezones, so trusting the local draft would drift).
///
/// `@MainActor` rather than the spec's "actor": the store it drives owns a
/// `ModelContext`, and MainActor gives the same serialisation `WhoopSync`
/// already relies on.
@MainActor
public final class CalendarSync {
    private let sources: [any CalendarSource]
    private let store: CalendarStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        sources: [any CalendarSource],
        store: CalendarStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.sources = sources
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    /// 30 days back, 90 days forward, matching DayGuide.
    public var window: DateInterval {
        let today = calendar.startOfDay(for: now())
        return DateInterval(
            start: calendar.date(byAdding: .day, value: -30, to: today) ?? today,
            end: calendar.date(byAdding: .day, value: 90, to: today) ?? today
        )
    }

    /// One pass. A source that throws is skipped; partial data beats an
    /// empty screen. Errors are not surfaced here because sync is ambient
    /// (scene activation, post-write), never a user-visible request.
    public func sync() async {
        let window = window
        var bySource: [CalendarEventSource: [CalendarEventSnapshot]] = [:]
        for source in sources {
            guard await source.isAuthorized else { continue }
            do {
                bySource[source.source] = try await source.events(from: window.start, to: window.end)
            } catch {
                continue
            }
        }
        guard !bySource.isEmpty else { return }

        let merged = CalendarMerge.merge(
            eventKit: bySource[.eventKit] ?? [],
            google: bySource[.google] ?? []
        )
        try? store.apply(merged, window: window, syncedAt: now())
    }

    public func create(_ draft: CalendarEventDraft) async throws {
        for source in sources {
            guard await source.isAuthorized else { continue }
            _ = try await source.create(draft)
            await sync()
            return
        }
        throw CalendarSyncError.noWritableSource
    }

    public func update(id: UUID, with draft: CalendarEventDraft) async throws {
        let event = try existing(id: id)
        _ = try await owner(of: event).update(sourceID: event.sourceID, with: draft)
        await sync()
    }

    public func delete(id: UUID) async throws {
        let event = try existing(id: id)
        try await owner(of: event).delete(sourceID: event.sourceID)
        await sync()
    }

    private func existing(id: UUID) throws -> CalendarEventSnapshot {
        guard let event = try? store.snapshot(id: id) else {
            throw CalendarSyncError.unknownEvent
        }
        return event
    }

    private func owner(of event: CalendarEventSnapshot) throws -> any CalendarSource {
        guard let source = sources.first(where: { $0.source == event.source }) else {
            throw CalendarSyncError.noWritableSource
        }
        return source
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CalendarSyncTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/CalendarSync.swift LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift
git commit -m "feat(calendar): sync authorized sources into the cache and route writes back"
```

---

### Task 6: EventKitSource and the usage string

**Files:**
- Create: `LifeOSKit/Sources/Integrations/EventKitSource.swift`
- Modify: `Config/App-Info.plist` (add `NSCalendarsFullAccessUsageDescription`)

**Interfaces:**
- Consumes: `CalendarSource` protocol (Task 4), `CalendarEventSnapshot` / `CalendarEventDraft` (Task 1).
- Produces: `EventKitSource` (actor conforming to `CalendarSource`). No new names for later tasks; the app wires `CalendarSync(sources: [EventKitSource()], ...)` in Phase C.

No unit tests: `EKEventStore` cannot run under `swift test` (no calendar database, no permission UI), which is exactly why every consumer sits behind the protocol. The verification steps are a full-suite run plus an app build for the simulator. This matches the spec's Section 16, which lists no `EventKitSource` test.

- [ ] **Step 1: Write the implementation**

```swift
// LifeOSKit/Sources/Integrations/EventKitSource.swift
import EventKit
import Foundation
import Persistence

/// EventKit behind `CalendarSource`. An actor because `EKEventStore` is not
/// Sendable and wants all access on one executor.
public actor EventKitSource: CalendarSource {
    public nonisolated let source: CalendarEventSource = .eventKit
    private let store = EKEventStore()

    public init() {}

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Presents the system prompt. Callers decide when; per the spec that is
    /// the agenda card's empty state, never launch.
    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).compactMap { snapshot(of: $0) }
    }

    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        let event = try existing(sourceID)
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func delete(sourceID: String) async throws {
        try store.remove(try existing(sourceID), span: .thisEvent, commit: true)
    }

    private func existing(_ sourceID: String) throws -> EKEvent {
        guard let event = store.event(withIdentifier: sourceID) else {
            throw CalendarSyncError.unknownEvent
        }
        return event
    }

    private func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
    }

    /// An EKEvent with no identifier (possible for unsaved or broken rows)
    /// has no natural key and is dropped rather than cached unmatchable.
    private func snapshot(of event: EKEvent) -> CalendarEventSnapshot? {
        guard let identifier = event.eventIdentifier else { return nil }
        return CalendarEventSnapshot(
            id: UUID(),
            source: .eventKit,
            sourceID: identifier,
            calendarTitle: event.calendar?.title ?? "",
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            isRecurring: event.hasRecurrenceRules || event.isDetached,
            location: event.location,
            notes: event.notes
        )
    }
}
```

- [ ] **Step 2: Add the usage string**

In `Config/App-Info.plist`, inside the top-level `<dict>`, following the pattern of the existing usage keys:

```xml
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>LifeOS shows your day's schedule on Today and lets the assistant create and change events for you.</string>
```

- [ ] **Step 3: Run the full kit suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS, including every pre-existing suite.

- [ ] **Step 4: Build the app for the simulator**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/EventKitSource.swift Config/App-Info.plist
git commit -m "feat(calendar): put EventKit behind the source protocol"
```

---

## Out of scope for this plan (per spec Section 15)

- Phase B: `CoachTool`, `ToolLoop`, the `Assistant` target, the `coach` function's tool-calling shape, `ChatMessage`, `AssistantSheet`. Blocked on the coach's `Insights` skeleton.
- Phase C: `AgendaCard`, `EventSheet`, `TodaySnapshot.agenda`, wiring `CalendarSync` to `scenePhase`. Scheduled after the Project 1 restyle merges.
- Phase D: `GoogleCalendarSource` and Google OAuth.
