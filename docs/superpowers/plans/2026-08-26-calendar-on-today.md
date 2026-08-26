# Calendar on Today (Phase C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The calendar becomes visible on the app's home surface: an agenda card directly under the month dot grid, an Upcoming section after it, the day's schedule inside the dot-tap sheet, and an event sheet to add and edit events.

**Architecture:** All app-target work; the kit (Phase A/B) already provides `CalendarStore`, `CalendarSync`, `EventKitSource`. `RootView` owns one `CalendarSync` and triggers passes on scene activation and after writes; sync saves fire the existing `ModelContext.didSave` reload loop, so `TodayViewModel` just reads the store during `load()` like every other feature. Views stay pure functions of snapshots.

**Tech Stack:** SwiftUI, EventKit (authorization status only, in the app), the LifeOSKit local package.

**Spec:** `docs/superpowers/specs/2026-08-25-calendar-and-assistant-design.md` Section 13.1 and Phase C of Section 15, extended by the user's direction: the agenda UI sits directly after the dots, a dot tap shows that day's schedule, and an Upcoming section follows the agenda.

## Global Constraints

- The EventKit permission prompt fires ONLY from the agenda card's connect button. Never at launch, never on tab switch.
- Views never hold SwiftData objects: only `CalendarEventSnapshot` values reach them (Phase A rule).
- Denied access is a first-class state: the card explains and links to Settings.
- With access granted and no events, the card says so rather than disappearing (spec 13.1).
- Recurring events are read-only in the event sheet: editing a series is out of scope (spec S17); the sheet says to edit it in the calendar app.
- Match the app idiom: `LifeOSTokens` colors resolved per scheme, `SoftCard` containers, section headers as small semibold secondary text, no new design language.
- The kit is untouched: if a task seems to need a `LifeOSKit` change, stop and report instead.
- `swift test` (kit, 627 green) and `xcodebuild ... build` must pass at every commit.
- Commits: conventional, no em dashes, no trailers. Branch work only, never on main.

---

### Task 1: Calendar data reaches the Today snapshots

**Files:**
- Modify: `LIfeOS/Features/Today/Model/TodaySnapshot.swift`
- Modify: `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`
- Modify: `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift`
- Modify: `LIfeOS/App/RootView.swift`

**Interfaces:**
- Produces (Task 2 and 3 consume): `CalendarAccessState` (`.notDetermined`, `.denied`, `.authorized`, static `var current`), `TodaySnapshot.calendarAccess/agenda/upcoming`, `UpcomingEvent` (`id`, `dayLabel: String`, `event: CalendarEventSnapshot`), `DayDetailSnapshot.events`, and on `RootView`: a `calendarSync: CalendarSync?` + `eventKitSource: EventKitSource?` pair built in `attachAll()`, `syncCalendar()`, `requestCalendarAccess()`.

- [ ] **Step 1: Extend the snapshots**

In `TodaySnapshot.swift` add `import Persistence` and `import EventKit`, then:

```swift
/// Where calendar permission stands. Read synchronously so `load()` stays
/// synchronous; the prompt itself is only ever triggered from the agenda
/// card's connect button.
enum CalendarAccessState: Equatable {
    case notDetermined, denied, authorized

    static var current: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

/// One row of the Upcoming list: an event plus the day label it renders
/// under, precomputed so the view does no date math.
struct UpcomingEvent: Equatable, Identifiable {
    let id: UUID
    let dayLabel: String
    let event: CalendarEventSnapshot
}
```

and three fields on `TodaySnapshot`:

```swift
    var calendarAccess: CalendarAccessState = .notDetermined
    /// Today's events, sorted by start.
    var agenda: [CalendarEventSnapshot] = []
    /// The next seven days after today, flattened and capped by the view.
    var upcoming: [UpcomingEvent] = []
```

In `DayDetailSnapshot.swift` add `import Persistence` and one field (defaulted, so existing previews and call sites keep compiling):

```swift
    /// That day's schedule. Empty when access is missing or nothing is on.
    var events: [CalendarEventSnapshot] = []
```

(If the struct has a memberwise-style init that previews call, add `events: [CalendarEventSnapshot] = []` as a defaulted parameter in the same position.)

- [ ] **Step 2: Read the calendar in TodayViewModel**

In `TodayViewModel.load()`, after the metrics work and before building `snapshot`, read the store (add `import Persistence` if missing — it is already there):

```swift
            let calendarStore = CalendarStore(context: context, calendar: calendar)
            let dayStart = calendar.startOfDay(for: .now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let weekOut = calendar.date(byAdding: .day, value: 8, to: dayStart) ?? tomorrow
            let agenda = (try? calendarStore.events(from: dayStart, to: tomorrow)) ?? []
            let upcoming = ((try? calendarStore.events(from: tomorrow, to: weekOut)) ?? [])
                .map { event in
                    UpcomingEvent(
                        id: event.id,
                        dayLabel: event.startDate.formatted(.dateTime.weekday(.abbreviated).day()),
                        event: event
                    )
                }
```

and set the new snapshot fields alongside the existing ones:

```swift
                calendarAccess: CalendarAccessState.current,
                agenda: agenda,
                upcoming: upcoming,
```

(Place them in the `TodaySnapshot(...)` call right after `streak:`, adding the parameters to the struct in the matching position, or assign after construction — whichever keeps the diff smallest given the struct uses vars with defaults: `snapshot.calendarAccess = ...` style assignments after the existing `snapshot = TodaySnapshot(...)` block are fine and smaller.)

In `select(_:)`, add the day's events to the detail snapshot:

```swift
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let events = (try? CalendarStore(context: context, calendar: calendar)
                .events(from: day, to: dayEnd)) ?? []
```

and pass `events: events` into `DayDetailSnapshot(...)`.

- [ ] **Step 3: RootView owns sync**

In `RootView`:

- Add state, following the `assistantModel` precedent and comment style:

```swift
    // Calendar sync is owned here so one pass serves Today's agenda, the
    // day sheet, and the assistant alike; every trigger funnels through
    // `syncCalendar()`. Built in `attachAll()` because it needs the context.
    @State private var eventKitSource: EventKitSource?
    @State private var calendarSync: CalendarSync?
```

- In `attachAll()`, after the assistant model creation, using the same `ModelContext` the other view models attach:

```swift
        if calendarSync == nil {
            let source = EventKitSource()
            eventKitSource = source
            calendarSync = CalendarSync(
                sources: [source],
                store: CalendarStore(context: context)
            )
        }
```

(match the actual local variable name for the context in `attachAll()`; add `import Integrations` and `import Persistence` to RootView if not present).

- Add the two funnels:

```swift
    /// Ambient: fires on scene activation and after any calendar write. The
    /// pass saves through the store, `ModelContext.didSave` fires, and
    /// `reloadAll()` refreshes every snapshot; nothing polls.
    private func syncCalendar() {
        guard CalendarAccessState.current == .authorized, let calendarSync else { return }
        Task { await calendarSync.sync() }
    }

    /// The one place the EventKit prompt is allowed to originate.
    private func requestCalendarAccess() {
        guard let eventKitSource else { return }
        Task {
            _ = try? await eventKitSource.requestAccess()
            syncCalendar()
        }
    }
```

- Call `syncCalendar()` in the existing `.task { attachAll(); reloadAll() }` block (after `reloadAll()`) and in the existing `.onChange(of: scenePhase)` active branch after `reloadAll()`.

- [ ] **Step 4: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Also `cd LifeOSKit && swift test` stays 627 green (no kit changes).

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Today LIfeOS/App/RootView.swift
git commit -m "feat(calendar): surface agenda, upcoming, and day events in Today's snapshots"
```

---

### Task 2: The agenda card, the Upcoming section, and the day sheet's schedule

**Files:**
- Create: `LIfeOS/Features/Today/View/AgendaCard.swift`
- Modify: `LIfeOS/Features/Today/View/TodayScreen.swift`
- Modify: `LIfeOS/Features/Today/View/DayDetailSheet.swift`

**Interfaces:**
- Consumes: Task 1's snapshot fields.
- Produces: `AgendaCard(access:agenda:upcoming:onConnect:onAddEvent:onTapEvent:onOpenToday:)` and `TodayScreen` gains four matching closures (`onConnectCalendar`, `onAddEvent`, `onTapEvent: (CalendarEventSnapshot) -> Void`, `onOpenToday`), which Task 3 wires in RootView.

Design, binding:

- `AgendaCard` sits in `layoutBody` DIRECTLY after `month` in both arrangements (before `streakLine`).
- Card chrome is a `SoftCard`. Header row: `"TODAY"` in `.system(size: 12, weight: .semibold)` secondary color with tracking, a spacer, and the event count (`"3 events"`, hidden when zero).
- Up to four event rows: time column (start, `HH:mm` via `Date.FormatStyle` `.dateTime.hour().minute()`, or `"all day"`), title (primary, medium), duration (secondary, e.g. `"45m"`, `"1h 30m"` — reuse `TodayScreen.duration` for the minutes math). Rows are tappable → `onTapEvent(event)`.
- More than four → a final `"+N more"` row → `onOpenToday()` (opens today's day sheet, which lists everything).
- Below the rows a `"+ Add event"` button (accent color, plain style) → `onAddEvent()`.
- `access == .notDetermined` → body is one sentence ("See your day's schedule here.") plus a "Connect calendar" bordered-prominent button → `onConnect()`.
- `access == .denied` → one sentence ("Calendar access is off.") plus a "Open Settings" button using `UIApplication.openSettingsURLString` via `Link`/`openURL`.
- `access == .authorized && agenda.isEmpty` → "Nothing scheduled today." with the add button still present, so the affordance stays discoverable (spec).
- **Upcoming** renders inside the same file as a second section under the card (its own `SoftCard`, header `"UPCOMING"`), shown only when `!upcoming.isEmpty` and access is authorized: up to five rows of `dayLabel · start time · title`, tappable → `onTapEvent`. More than five → `"+N more"` static text (no navigation; the assistant and day sheets cover depth).
- `DayDetailSheet`: add a `schedule` section rendered FIRST (above `metrics`) when `snapshot.events` is non-empty: header `"Schedule"` in the same style as the habits count line, then a `SoftCard` of rows (time column + title + duration, divider-separated, non-tappable here). A day with no events shows no schedule section at all — the sheet predates calendars and must not grow noise.

- [ ] **Step 1: Build `AgendaCard.swift`** with the states above. Keep every subview `private`; the only public-ish surface is the card's init. Use `@Environment(\.colorScheme)` + `LifeOSTokens` exactly like `DayDetailSheet` does.

- [ ] **Step 2: Wire `TodayScreen`**: add the four closures as `let` properties (after `onSelectDay`), insert `AgendaCard` after `month` in both `layoutBody` branches, passing `snapshot.calendarAccess`, `snapshot.agenda`, `snapshot.upcoming`. Update the `#Preview` with the new arguments (empty closures, `.authorized`, two fake events built inline with `CalendarEventSnapshot`).

- [ ] **Step 3: Extend `DayDetailSheet`** with the schedule section per the design.

- [ ] **Step 4: Compile check** — `TodayScreen`'s call site in RootView does not compile yet (missing arguments). For THIS task only, pass inert closures at the call site (`onConnectCalendar: {}` etc.) so the app builds; Task 3 replaces them with real wiring. Run the xcodebuild check; expect `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Today LIfeOS/App/RootView.swift
git commit -m "feat(calendar): show the agenda, upcoming, and day schedule on Today"
```

---

### Task 3: The event sheet and the real wiring

**Files:**
- Create: `LIfeOS/Features/Today/View/EventSheet.swift`
- Modify: `LIfeOS/App/RootView.swift`

**Interfaces:**
- Consumes: everything above plus `CalendarSync.create/update/delete` and `CalendarEventDraft` from the kit.
- Produces: UI only.

Design, binding:

- `EventSheet` presents in two modes driven by an optional event: `nil` → create, `some` → view/edit.
- Fields: Title (`TextField`), All-day (`Toggle`), Starts / Ends (`DatePicker`, date+time, hour-minute hidden when all-day), Location (`TextField`), Notes (`TextField`, axis .vertical). Defaults for create: next full hour, one hour long.
- Toolbar: Cancel (dismiss) and Save (disabled on empty title). Edit mode additionally shows a red "Delete event" button at the bottom.
- A recurring event (`isRecurring`) renders read-only: fields disabled, Save hidden, a footnote "This repeats. Edit the series in your calendar app." Delete hidden too.
- Ends before starts is clamped on save (end = max(end, start + 15 min)), not an error state.
- Writes go through closures injected by RootView (`onSave: (CalendarEventDraft) -> Void`, `onDelete: () -> Void`); the sheet never touches `CalendarSync` directly, keeping it previewable.
- RootView wiring:
  - `@State private var eventSheet: EventSheetPresentation?` where `EventSheetPresentation: Identifiable` is a small enum-with-id (`case create`, `case edit(CalendarEventSnapshot)`) defined beside the sheet.
  - `.sheet(item: $eventSheet)` presents `EventSheet`, whose `onSave` runs `Task { try? await calendarSync?.create(draft) }` for create, or `.update(id:with:)` for edit; `onDelete` runs `.delete(id:)`. Each completes by calling nothing else — the sync inside those methods saves, `didSave` fires, and every snapshot reloads. (Write errors are silently dropped this round; ledger it.)
  - The four `TodayScreen` closures become real: `onConnectCalendar: { requestCalendarAccess() }`, `onAddEvent: { eventSheet = .create }`, `onTapEvent: { eventSheet = .edit($0) }`, `onOpenToday: { today.select(.now) }` (the existing dot-tap path, which now includes the schedule).

- [ ] **Step 1: Build `EventSheet.swift`** per the design, with `#Preview`s for create, edit, and recurring.

- [ ] **Step 2: Wire RootView** per the design, replacing Task 2's inert closures.

- [ ] **Step 3: Build** — xcodebuild check green, kit suite untouched (627).

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/EventSheet.swift LIfeOS/App/RootView.swift
git commit -m "feat(calendar): add and edit events from the Today agenda"
```

---

## Out of scope

- Kit changes of any kind (Phase A/B own the calendar machinery).
- The Google source (Phase D), notifications, attendees, recurrence editing (spec S17).
- Write-error surfacing in the event sheet (silent this round; the next sync corrects the view). Deferred, not dropped.
- Restructuring the assistant's own `CalendarSync` to share RootView's instance — two instances upsert idempotently by natural key; unification is a cleanup for later.
