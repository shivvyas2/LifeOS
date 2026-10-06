# Find and ask on the calendar screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `CalendarScreen` a hairline find-and-ask field: typing finds events locally and instantly, with the matches marked on the grid and the bands; Return or the arrow hands the words to the calendar assistant, whose reply lands on the same screen as a card and moves the calendar to the events it was about; an event the assistant creates counts as found.

**Architecture:** The Notes shelf's private search field becomes `HairlineField` in `DesignSystem`, and Notes adopts it. The matching lives in `ScheduleSearch` in `Persistence`, a pure function over the snapshots `MonthViewModel` already holds; the wording around it (eyebrow, scope sentence, overflow line, row label) is a tested value, `ScheduleFindText`, in `DesignSystem`. `CalendarScreen` gains a query, a results block and a reply card, both in a new `CalendarFindAsk.swift`, and takes the one `AssistantViewModel` the app already owns, so a question asked here is a turn in the same conversation the sheet shows. On the write side, `CalendarWriting.create` returns the created event as the cache holds it (the id a source hands back is provisional, so `CalendarSync` re-reads the row by its `(source, sourceID)` key after the sync), and `CreateEventTool` records it in the `CalendarEventCollector`, which is how the card lists it and the calendar jumps to it.

**Tech Stack:** SwiftUI, SwiftData, Foundation Models, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-06-editorial-calendar-find-ask-widget-design.md`, section 2 and the find-and-ask parts of section 5. PR 3 of the five in section 6. The widget (section 3) and the guide are later PRs and are not built here.

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. The accent (`LifeOSTokens.accent`) appears only on today's cell, the hatch on past days, this month's name, today's number on the bands, and now the number and dot of a day that matches a live query and the 6pt dot before a matching row. No new colours.
- No gradient field on this screen. Every button uses `.buttonStyle(.editorial(role))` or `.buttonStyle(.plain)` around editorial content; no bare system buttons in content. The system bar holds only Back.
- Fonts come only from `LifeOSType` or `Editorial.figure(_:)` / `Editorial.headline(_:)`; `scripts/check-typography.sh` must report nothing new versus the baseline in `$OUT/typo-base.txt`.
- The Today tab is not touched. The Monthly grid and the Weekly bands keep their look; this PR adds marks to them while a query is live, nothing else.
- `LifeOSKit` also builds for macOS (`swift test` runs there): nothing iOS-only goes into the package. `.submitLabel`, `.autocorrectionDisabled()` and `.textFieldStyle(.plain)` are fine; `.textInputAutocapitalization` is not.
- `LIfeOS/` is a synchronized folder in the Xcode project: new files, renames and deletions under it need no `project.pbxproj` edit.
- Find never calls a model. The device model answers an ask; the remote tier runs only when the project is configured for one, exactly as the sheet behaves today. Nothing changes in what the assistant sends or stores beyond returning the created event to its caller.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind in commits or the PR body.
- Work happens in the worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask` on branch `feat/editorial-calendar-ask`, cut from `origin/main` at `8ee7ae5`. `Config/Secrets.xcconfig` is already copied in and ignored. The baseline `swift test` there passes 1417 tests in 195 suites.
- `$OUT` is `/private/tmp/claude-501/-Users-shivvyas-LIfeOS/068489d1-9b0b-4686-8c3b-702504137000/scratchpad`; the typography baseline is `$OUT/typo-base.txt` (120 lines, all pre-existing).
- The simulator for builds and captures is `CalendarAsk iPhone 17`, id `B192EA65-BAA2-4814-A298-94A2F0C8FC87` (iOS 26.2). Peer sessions use the plain `iPhone 17` (`780ECD75`); do not install on it. The bundle id is `com.shivvyas.lifeos`.
- The plain `sleep` is blocked in the Bash tool; wait with `perl -e 'select(undef,undef,undef,4)'`.

## Review Focus

1. A multi-day event comes out of the day index once per day it covers, so a query that matches it must list it once and mark every day it starts on only once. `ScheduleSearchTests.resultsAreByStartThenTitleAndOncePerID` in Task 1.
2. `Café` must be found by `cafe` and `Dentist` by `DENT`: a person types fast and without accents. `ScheduleSearchTests.matchesIgnoreCaseAndDiacritics` in Task 1.
3. The event the assistant created must be findable by the id the card stores, or the card draws nothing and the calendar does not move: the source's id is provisional and the sync writes a different one. `CalendarSyncTests.createReturnsTheEventAsTheCacheHoldsIt` in Task 4 and `CalendarStoreLookupTests.aRowIsFoundByItsSourceKeyUnderTheStoredID` in Task 4.
4. The row label must read `Tue 13 · 10:00` with the weekday before the day in every locale; `Date.FormatStyle` puts the day first in `en_US`, so the two fields are formatted separately. `ScheduleFindTextTests.rowLabelPutsTheWeekdayFirstAndFollowsTheDeviceClock` in Task 2.
5. A query of spaces must show no results block and no marks, and a cleared field must take the marks with it, or the grid keeps accent numbers for nothing. `ScheduleSearchTests.anEmptyOrBlankQueryMatchesNothing` in Task 1, and the screen shows the block only while the trimmed query has text (Task 6), checked by the `calendar-find` capture against `month` in Task 8.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Persistence/ScheduleSearch.swift` (new) | `ScheduleSearch.matches(_:in:)`, the local find |
| `LifeOSKit/Tests/PersistenceTests/ScheduleSearchTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/ScheduleFindText.swift` (new) | The tested wording: placeholder, eyebrow, scope sentence, overflow line, row label, the needs-model line |
| `LifeOSKit/Tests/DesignSystemTests/ScheduleFindTextTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/HairlineField.swift` (new) | The field on a hairline with a glyph, a clear glyph and an accessory slot |
| `LIfeOS/Features/Notes/View/NoteShelfScreen.swift` | Notes adopts `HairlineField` |
| `LifeOSKit/Sources/Persistence/CalendarStore.swift` | `snapshot(source:sourceID:)`, the public lookup by natural key |
| `LifeOSKit/Tests/PersistenceTests/CalendarStoreLookupTests.swift` (new) | Its test |
| `LifeOSKit/Sources/Assistant/CalendarAccess.swift` | `CalendarWriting.create` returns the created snapshot |
| `LifeOSKit/Sources/Integrations/CalendarSync.swift` | `create` returns the row the sync wrote |
| `LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift` | The returned-id test |
| `LifeOSKit/Sources/Assistant/CalendarTools.swift` | `CreateEventTool` records the created event |
| `LifeOSKit/Sources/Assistant/AssistantContext.swift` | Passes the collector to `CreateEventTool` |
| `LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift` | `FakeCalendar.create` returns a snapshot; the collector test |
| `LifeOSKit/Sources/DesignSystem/Chat.swift` | `ChatConfirmation` gains `framed:` so it can sit inside another card |
| `LIfeOS/Features/Today/View/CalendarFindAsk.swift` (new) | `CalendarAsk`, `ScheduleResultsBlock`, `ScheduleResultRow`, `AssistantReplyCard` |
| `LIfeOS/Features/Today/View/CalendarScreen.swift` | The query, the field, the arrow, the results and reply blocks, the grid marks, the ask flow |
| `LIfeOS/Features/Today/View/WeekBands.swift` | `highlighted` rows draw the 6pt accent dot |
| `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift` | DEBUG `previewModelAvailable` |
| `LIfeOS/App/RootView.swift` | Passes `assistantModel` to the screen |
| `LIfeOS/Features/Assistant/View/AssistantSheet.swift` | Passes its model to the screen |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift` | `calendar-find` (`--query=`, `--no-model`) and `calendar-ask` pages, the seeded assistant |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Routes the two new pages |

---

### Task 0: Worktree, baseline and the plan

The worktree, the test baseline, the typography baseline and the simulator were set up before this plan was written. This task records them and commits the plan.

- [ ] **Step 1: Confirm the worktree and the baselines**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
git status --short && git log --oneline -1 && ls Config/Secrets.xcconfig
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/068489d1-9b0b-4686-8c3b-702504137000/scratchpad
tail -2 $OUT/baseline-tests.txt; echo "typography baseline lines: $(wc -l < $OUT/typo-base.txt)"
xcrun simctl list devices | grep "CalendarAsk"
```

Expected: a clean tree at `8ee7ae5`, the secrets file present, `Test run with 1417 tests in 195 suites passed`, `120`, and the `CalendarAsk iPhone 17` device.

- [ ] **Step 2: Commit the plan**

```bash
git add docs/superpowers/plans/2026-10-06-editorial-calendar-ask.md
git commit -m "docs(plans): find and ask on the calendar screen

The plan for PR 3 of the editorial calendar work: the hairline field,
local find with grid marks, the reply card, and the created event
counting as found."
```

---

### Task 1: `ScheduleSearch` in Persistence

**Files:**
- Create: `LifeOSKit/Sources/Persistence/ScheduleSearch.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/ScheduleSearchTests.swift`

**Interfaces:**
- Consumes: `CalendarEventSnapshot` (`id: UUID`, `title`, `location: String?`, `calendarTitle`, `startDate`) from `Persistence`.
- Produces: `public enum ScheduleSearch { public static func matches(_ query: String, in events: [CalendarEventSnapshot]) -> [CalendarEventSnapshot] }`. Task 6 calls it with `model.eventsByDay.values.flatMap { $0 }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Persistence

@Suite struct ScheduleSearchTests {
    private let noon = Date(timeIntervalSince1970: 1_791_900_000)

    private func event(_ title: String, id: UUID = UUID(), at offset: TimeInterval = 0,
                       location: String? = nil, calendar: String = "Work") -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: .eventKit, sourceID: title, calendarTitle: calendar, title: title,
            startDate: noon.addingTimeInterval(offset), endDate: noon.addingTimeInterval(offset + 3_600),
            isAllDay: false, isRecurring: false, location: location, notes: nil
        )
    }

    @Test func matchesIgnoreCaseAndDiacritics() {
        let events = [event("Dentist"), event("Café with Ana")]
        #expect(ScheduleSearch.matches("DENT", in: events).map(\.title) == ["Dentist"])
        #expect(ScheduleSearch.matches("cafe", in: events).map(\.title) == ["Café with Ana"])
    }

    @Test func aPlaceOrACalendarNameIsEnough() {
        let events = [event("Standup", location: "Room 4"), event("Birthday", calendar: "Family")]
        #expect(ScheduleSearch.matches("room 4", in: events).map(\.title) == ["Standup"])
        #expect(ScheduleSearch.matches("family", in: events).map(\.title) == ["Birthday"])
    }

    @Test func anEmptyOrBlankQueryMatchesNothing() {
        let events = [event("Dentist")]
        #expect(ScheduleSearch.matches("", in: events).isEmpty)
        #expect(ScheduleSearch.matches("   ", in: events).isEmpty)
    }

    @Test func resultsAreByStartThenTitleAndOncePerID() {
        // The day index hands a multi-day event back once per day it covers;
        // the person should see it once.
        let shared = UUID()
        let events = [
            event("Zoo day", id: shared, at: 0),
            event("Zoo day", id: shared, at: 0),
            event("Dentist", at: 86_400),
            event("Dinner", at: -86_400),
            event("Dance", at: -86_400),
        ]
        #expect(ScheduleSearch.matches("d", in: events).map(\.title) == ["Dance", "Dinner", "Zoo day", "Dentist"])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter ScheduleSearchTests`
Expected: compile error, `cannot find 'ScheduleSearch' in scope`.

- [ ] **Step 3: Write the search**

```swift
import Foundation

/// Finds events by the words a person would type: part of a title, a
/// place, or the name of the calendar. Local and instant; nothing here
/// fetches or asks a model.
public enum ScheduleSearch {
    /// Matches are case- and diacritic-insensitive (`localizedStandardContains`),
    /// sorted by start then title, and de-duplicated by id, because the
    /// day index hands a multi-day event back once per day it covers.
    public static func matches(_ query: String, in events: [CalendarEventSnapshot]) -> [CalendarEventSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var seen: Set<UUID> = []
        return events
            .filter { event in
                event.title.localizedStandardContains(needle)
                    || (event.location?.localizedStandardContains(needle) ?? false)
                    || event.calendarTitle.localizedStandardContains(needle)
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
            .filter { seen.insert($0.id).inserted }
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter ScheduleSearchTests`
Expected: `4 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/ScheduleSearch.swift LifeOSKit/Tests/PersistenceTests/ScheduleSearchTests.swift
git commit -m "feat(persistence): ScheduleSearch finds events by title, place or calendar

Case- and diacritic-insensitive, sorted by start then title, once per
id: the local find behind the calendar screen's field."
```

---

### Task 2: `ScheduleFindText`, the wording as a tested value

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/ScheduleFindText.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/ScheduleFindTextTests.swift`

**Interfaces:**
- Produces: `public enum ScheduleFindText` with `static let placeholder`, `static let needsModel`, `static func eyebrow(found: Int) -> String`, `static func scope(months: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String`, `static func more(_ hidden: Int) -> String`, `static func rowLabel(start: Date, isAllDay: Bool, calendar: Calendar = .current, locale: Locale = .current) -> String`. Tasks 6 and 7 draw these.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct ScheduleFindTextTests {
    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func eyebrowCountsOrSaysNothingFound() {
        #expect(ScheduleFindText.eyebrow(found: 0) == "Nothing found")
        #expect(ScheduleFindText.eyebrow(found: 1) == "Found 1")
        #expect(ScheduleFindText.eyebrow(found: 3) == "Found 3")
    }

    @Test func scopeNamesTheShownMonthsAcrossAYearBoundary() {
        #expect(ScheduleFindText.scope(months: [date(2026, 10, 1), date(2026, 11, 1)], calendar: calendar, locale: us)
                == "In October and November. Ask for anything further out.")
        #expect(ScheduleFindText.scope(months: [date(2026, 12, 1), date(2027, 1, 1)], calendar: calendar, locale: us)
                == "In December and January. Ask for anything further out.")
    }

    @Test func overflowLine() {
        #expect(ScheduleFindText.more(4) == "4 more")
        #expect(ScheduleFindText.more(1) == "1 more")
    }

    @Test func rowLabelPutsTheWeekdayFirstAndFollowsTheDeviceClock() {
        // 13 October 2026 is a Tuesday. en_US would print the day before
        // the weekday if the two were one format; they are two.
        let start = date(2026, 10, 13, hour: 10)
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: false, calendar: calendar, locale: gb) == "Tue 13 · 10:00")
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: false, calendar: calendar, locale: us).hasPrefix("Tue 13 · 10:00"))
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: true, calendar: calendar, locale: us) == "All day")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter ScheduleFindTextTests`
Expected: compile error, `cannot find 'ScheduleFindText' in scope`.

- [ ] **Step 3: Write the values**

```swift
import Foundation

/// The wording around finding events on the calendar screen, as tested
/// values: the field's placeholder, the eyebrow over the results, the
/// sentence that names the scope, the overflow line, each result's
/// day-and-time label, and the line shown when asking is not possible.
public enum ScheduleFindText {
    public static let placeholder = "Find or ask about your schedule"
    public static let needsModel = "Asking needs Apple Intelligence on this device."
    static let askFurther = "Ask for anything further out."

    /// `Found 3`, or `Nothing found`. Drawn through `editorialEyebrow()`,
    /// which uppercases it.
    public static func eyebrow(found count: Int) -> String {
        count == 0 ? "Nothing found" : "Found \(count)"
    }

    /// `In October and November. Ask for anything further out.`: the months
    /// the find covers, so a miss reads as "not here", not "not anywhere".
    public static func scope(months: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let names = months.map { $0.formatted(style.month(.wide)) }
        guard let last = names.last else { return askFurther }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return "In \(list). \(askFurther)"
    }

    /// `4 more`, under the eighth row.
    public static func more(_ hidden: Int) -> String { "\(hidden) more" }

    /// `Tue 13 · 10:00`, or `All day`: the day a person scans for, then the
    /// time the way the device shows it. Weekday and day are formatted
    /// separately because one format puts the day first in some locales.
    public static func rowLabel(start: Date, isAllDay: Bool, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard !isAllDay else { return "All day" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let weekday = start.formatted(style.weekday(.abbreviated))
        let day = start.formatted(style.day())
        let time = start.formatted(style.hour().minute())
        return "\(weekday) \(day) · \(time)"
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter ScheduleFindTextTests`
Expected: `4 tests ... passed`. If the `en_GB` time renders as `10:00` but the `en_US` one fails the prefix, the hour is being printed with a leading zero in one of them; print both and adjust the test's `us` expectation to `.contains("Tue 13 · ")` plus `.contains("10:00")` rather than changing the value.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/ScheduleFindText.swift LifeOSKit/Tests/DesignSystemTests/ScheduleFindTextTests.swift
git commit -m "feat(design): the find-and-ask wording as a tested value

Eyebrow, scope sentence, overflow line and the row label with the
weekday ahead of the day in every locale."
```

---

### Task 3: `HairlineField` in DesignSystem, and Notes adopts it

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/HairlineField.swift`
- Modify: `LIfeOS/Features/Notes/View/NoteShelfScreen.swift:122-141` (the private `searchField`)

**Interfaces:**
- Consumes: `Hairline`, `Editorial.quietInk`, `LifeOSType.body`, `Space`.
- Produces: `public struct HairlineField<Accessory: View>: View` with `init(text: Binding<String>, placeholder: String, glyph: String = "magnifyingglass", submitLabel: SubmitLabel = .search, focus: FocusState<Bool>.Binding? = nil, onSubmit: @escaping () -> Void = {}, @ViewBuilder accessory: () -> Accessory)` and the `Accessory == EmptyView` overload without the trailing closure. Task 6 uses it with the ask arrow as the accessory.

There is no view test in the package; the gate is `swift build` for the package, the app build in Step 4, and the `notes` capture in Task 8.

- [ ] **Step 1: Write the field**

```swift
import SwiftUI

/// A field on a hairline: a leading glyph, the text, a clear glyph while
/// there is text, room for one accessory (the calendar's ask arrow), and a
/// rule underneath. Notes searches with it; the calendar finds and asks.
public struct HairlineField<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    let glyph: String
    let submitLabel: SubmitLabel
    let focus: FocusState<Bool>.Binding?
    let onSubmit: () -> Void
    let accessory: Accessory
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String, glyph: String = "magnifyingglass",
                submitLabel: SubmitLabel = .search, focus: FocusState<Bool>.Binding? = nil,
                onSubmit: @escaping () -> Void = {}, @ViewBuilder accessory: () -> Accessory) {
        _text = text; self.placeholder = placeholder; self.glyph = glyph
        self.submitLabel = submitLabel; self.focus = focus; self.onSubmit = onSubmit
        self.accessory = accessory()
    }

    public var body: some View {
        let quiet = Editorial.quietInk(scheme)
        VStack(spacing: Space.half) {
            HStack(spacing: Space.x1) {
                Image(systemName: glyph).foregroundStyle(quiet)
                field
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(LifeOSType.body)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .onSubmit(onSubmit)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(quiet)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                accessory
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(placeholder, text: $text).focused(focus).submitLabel(submitLabel)
        } else {
            TextField(placeholder, text: $text).submitLabel(submitLabel)
        }
    }
}

extension HairlineField where Accessory == EmptyView {
    public init(text: Binding<String>, placeholder: String, glyph: String = "magnifyingglass",
                submitLabel: SubmitLabel = .search, focus: FocusState<Bool>.Binding? = nil,
                onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, placeholder: placeholder, glyph: glyph, submitLabel: submitLabel,
                  focus: focus, onSubmit: onSubmit) { EmptyView() }
    }
}
```

- [ ] **Step 2: Build the package**

Run: `cd LifeOSKit && swift build 2>&1 | grep -E "error:|Compiling|Build complete" | tail -3`
Expected: `Build complete!`, no `error:` lines.

- [ ] **Step 3: Notes adopts it**

In `LIfeOS/Features/Notes/View/NoteShelfScreen.swift`, replace the whole private `searchField` (the `VStack(spacing: Space.half) { HStack(spacing: Space.x1) { Image(systemName: "magnifyingglass") ... } Hairline() }` block, lines 122 to 141) with:

```swift
    private var searchField: some View {
        HairlineField(text: $model.query, placeholder: "Search all pages", focus: $searchFocused)
    }
```

The call site on line 37 (`searchField`) and the focus bridging on lines 114 to 119 stay as they are. If `secondary` (the `LifeOSTokens.secondaryText` colour) is now unused in the file, delete its declaration on line 18; check with `grep -n "secondary" LIfeOS/Features/Notes/View/NoteShelfScreen.swift` first, it is used by the no-results card on line 72.

- [ ] **Step 4: Build the app**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet 2>&1 | grep -E "error:" | head; echo "build exit ${PIPESTATUS[0]}"
```

Expected: `build exit 0`, no `error:` lines. The first build in a fresh worktree resolves packages and takes several minutes; run it with a 600000 ms timeout.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/HairlineField.swift LIfeOS/Features/Notes/View/NoteShelfScreen.swift
git commit -m "feat(design): HairlineField, the search field on a rule, and Notes adopts it

A glyph, the text, a clear glyph while there is text, an accessory slot
and a hairline underneath, lifted out of the Notes shelf so the calendar
can find and ask with the same field."
```

---

### Task 4: The created event comes back as the cache holds it

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/CalendarStore.swift:39-41` (beside `snapshot(id:)`)
- Test: `LifeOSKit/Tests/PersistenceTests/CalendarStoreLookupTests.swift` (new)
- Modify: `LifeOSKit/Sources/Assistant/CalendarAccess.swift:19-23` (`CalendarWriting`)
- Modify: `LifeOSKit/Sources/Integrations/CalendarSync.swift:71-79` (`create`)
- Test: `LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift` (new test after `createDispatchesToTheFirstAuthorizedSourceAndResyncs`)
- Modify: `LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift:28-30` (`FakeCalendar.create`)

**Interfaces:**
- Consumes: `CalendarStore.rowByKey(sourceRaw:sourceID:)` (private, already there), `CalendarSource.create(_:) async throws -> CalendarEventSnapshot`.
- Produces: `CalendarStore.snapshot(source: CalendarEventSource, sourceID: String) throws -> CalendarEventSnapshot?`; `CalendarWriting.create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot` (`@discardableResult`); `CalendarSync.create` with the same signature. Task 5's `CreateEventTool` records what `create` returns. `AssistantViewModel.save` keeps calling `sync.create(draft)` and ignoring the result.

- [ ] **Step 1: Write the failing store test**

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarStoreLookupTests {
    /// The id a provider hands back from a write is provisional; the row
    /// the sync wrote is the one the app can find by id, and this is how a
    /// caller gets to it.
    @Test func aRowIsFoundByItsSourceKeyUnderTheStoredID() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = CalendarStore(context: ModelContext(container))
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let fetched = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-9", calendarTitle: "Cal", title: "Dentist",
            startDate: now, endDate: now.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
        try store.apply([fetched], window: DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400)))

        let found = try #require(try store.snapshot(source: .eventKit, sourceID: "ek-9"))
        #expect(found.id == fetched.id)
        #expect(found.title == "Dentist")
        #expect(try store.snapshot(source: .google, sourceID: "ek-9") == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter CalendarStoreLookupTests`
Expected: compile error, `no exact matches in call to instance method 'snapshot'`.

- [ ] **Step 3: Add the lookup**

In `CalendarStore.swift`, after `snapshot(id:)` (line 41):

```swift
    /// The cached row for a provider's event, by its natural key. The id a
    /// source hands back from a write is provisional; this is how a caller
    /// finds the id the rest of the app can look the event up by.
    public func snapshot(source: CalendarEventSource, sourceID: String) throws -> CalendarEventSnapshot? {
        try rowByKey(sourceRaw: source.rawValue, sourceID: sourceID)?.snapshot()
    }
```

- [ ] **Step 4: Run it to see it pass**

Run: `cd LifeOSKit && swift test --filter CalendarStoreLookupTests`
Expected: `1 test ... passed`.

- [ ] **Step 5: Write the failing sync test**

In `CalendarSyncTests.swift`, after `createDispatchesToTheFirstAuthorizedSourceAndResyncs`:

```swift
    @Test func createReturnsTheEventAsTheCacheHoldsIt() async throws {
        let (sync, store, eventKit, _) = try make()
        let draft = CalendarEventDraft(title: "Dentist", startDate: now, endDate: now.addingTimeInterval(3_600))
        // The fake's create answers with sourceID "eventKit-new-1" under a
        // throwaway id; the fetch after the write reports the same key under
        // another. The caller must get the one the cache kept.
        eventKit.fetchResult = .success([snapshot("Dentist", source: .eventKit, sourceID: "eventKit-new-1", start: now)])

        let created = try await sync.create(draft)

        let stored = try #require(try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).first)
        #expect(created.id == stored.id)
        #expect(created.title == "Dentist")
    }
```

- [ ] **Step 6: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter CalendarSyncTests`
Expected: compile error on `let created = try await sync.create(draft)`, `constant 'created' inferred to have type '()'` or similar.

- [ ] **Step 7: Return the created event from the protocol and the sync**

In `LifeOSKit/Sources/Assistant/CalendarAccess.swift`, change `CalendarWriting` to:

```swift
public protocol CalendarWriting: Sendable {
    /// The event as the cache holds it after the write, so a caller can show
    /// it and find it again by id.
    @discardableResult
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func update(id: UUID, with draft: CalendarEventDraft) async throws
    func delete(id: UUID) async throws
}
```

In `LifeOSKit/Sources/Integrations/CalendarSync.swift`, replace `create` (lines 71 to 79) with:

```swift
    /// Writes through the first authorized source and returns the event as
    /// the cache holds it after the sync. The snapshot a source hands back
    /// carries a provisional id; the row the sync wrote is the one the rest
    /// of the app can find by id, so that is what goes back.
    @discardableResult
    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        for source in sources {
            guard await source.isAuthorized else { continue }
            let created = try await source.create(draft)
            await sync()
            return (try? store.snapshot(source: created.source, sourceID: created.sourceID)) ?? created
        }
        throw CalendarSyncError.noWritableSource
    }
```

In `LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift`, replace `FakeCalendar.create` (lines 28 to 30) with:

```swift
    nonisolated func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        await MainActor.run {
            created.append(draft)
            return CalendarEventSnapshot(
                id: UUID(), source: .eventKit, sourceID: "ek-created-\(created.count)",
                calendarTitle: "Cal", title: draft.title,
                startDate: draft.startDate, endDate: draft.endDate,
                isAllDay: draft.isAllDay, isRecurring: false,
                location: draft.location, notes: draft.notes
            )
        }
    }
```

- [ ] **Step 8: Run the three suites to see them pass**

Run: `cd LifeOSKit && swift test --filter "CalendarSyncTests|CalendarToolsTests|CalendarStoreLookupTests"`
Expected: every test passes, including the existing `createDispatchesToTheFirstAuthorizedSourceAndResyncs` (its `try await sync.create(draft)` now discards a result) and `createEventMapsItsArgumentsOntoTheDraft`.

- [ ] **Step 9: Build the app**

`AssistantViewModel.swift:10` declares `extension CalendarSync: CalendarWriting {}`; the signatures now match, and `save(_:editing:)` ignores the result. Confirm:

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet 2>&1 | grep -E "error:" | head; echo "build exit ${PIPESTATUS[0]}"
```

Expected: `build exit 0`.

- [ ] **Step 10: Commit**

```bash
git add LifeOSKit/Sources/Persistence/CalendarStore.swift LifeOSKit/Tests/PersistenceTests/CalendarStoreLookupTests.swift \
  LifeOSKit/Sources/Assistant/CalendarAccess.swift LifeOSKit/Sources/Integrations/CalendarSync.swift \
  LifeOSKit/Tests/IntegrationsTests/CalendarSyncTests.swift LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift
git commit -m "feat(calendar): create returns the event as the cache holds it

A source answers a write with a provisional id and the sync writes
another, so CalendarSync re-reads the row by its source key and hands
that back; CalendarWriting carries the result so a tool can show it."
```

---

### Task 5: `CreateEventTool` records the created event

**Files:**
- Modify: `LifeOSKit/Sources/Assistant/CalendarTools.swift:137-158` (`CreateEventTool`)
- Modify: `LifeOSKit/Sources/Assistant/AssistantContext.swift:6-23` (`CalendarAssistant.tools`)
- Test: `LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift` (new test after `createEventMapsItsArgumentsOntoTheDraft`)

**Interfaces:**
- Consumes: `CalendarWriting.create` returning the snapshot (Task 4), `CalendarEventCollector.record(_:)` and `collected()`.
- Produces: `CreateEventTool(writing:collector:)`; `CalendarAssistant.tools(reading:writing:collector:)` passes the collector to it. `AssistantViewModel.send()` already stores `collector.collected()` ids on the reply, so the created event reaches `eventsByMessage` with no view-model change.

- [ ] **Step 1: Write the failing test**

```swift
    @Test func createEventRecordsTheNewEventForTheReplyCard() async throws {
        let fake = FakeCalendar()
        let collector = CalendarEventCollector()
        let tools = CalendarAssistant.tools(reading: fake, writing: fake, collector: collector)
        let create = try #require(tools.first { $0.name == "create_event" })
        _ = try await create.call(arguments([
            "title": "Dentist", "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        let collected = await collector.collected()
        #expect(collected.map(\.title) == ["Dentist"])
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter CalendarToolsTests/createEventRecordsTheNewEventForTheReplyCard`
Expected: FAIL, `collected.map(\.title) == []`.

- [ ] **Step 3: Record the created event**

In `CalendarTools.swift`, change `CreateEventTool` to:

```swift
struct CreateEventTool: CoachTool {
    let writing: any CalendarWriting
    /// The created event joins the reply's cards, so the person sees what
    /// was made and the calendar can jump to it. Optional for the same
    /// reason as on `GetEventsTool`.
    var collector: CalendarEventCollector?
    let name = "create_event"
    let description = "Create a calendar event."
    var parameters: GenerationSchema { EventDraftArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Created an event" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try EventDraftArguments(arguments)
        let draft = CalendarEventDraft(
            title: args.title,
            startDate: try ToolDates.parse(args.start),
            endDate: try ToolDates.parse(args.end),
            isAllDay: args.isAllDay,
            location: args.location.isEmpty ? nil : args.location,
            notes: args.notes.isEmpty ? nil : args.notes
        )
        let created = try await writing.create(draft)
        await collector?.record([created])
        return "Created \"\(args.title)\"."
    }
}
```

In `AssistantContext.swift`, change the `CreateEventTool(writing: writing),` line in `tools(reading:writing:collector:)` to:

```swift
            CreateEventTool(writing: writing, collector: collector),
```

- [ ] **Step 4: Run the suite to see it pass**

Run: `cd LifeOSKit && swift test --filter CalendarToolsTests`
Expected: all tests pass, `thereAreSixToolsAndOnlyWritesAreGated` included.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Assistant/CalendarTools.swift LifeOSKit/Sources/Assistant/AssistantContext.swift LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift
git commit -m "feat(assistant): a created event counts as found

CreateEventTool records what it made in the turn's collector, so the
reply's card lists it and the calendar can jump to it."
```

---

### Task 6: Find as you type: the field, the results block and the marks

**Files:**
- Create: `LIfeOS/Features/Today/View/CalendarFindAsk.swift` (the `ScheduleResultsBlock` and `ScheduleResultRow` parts; Task 7 adds the rest)
- Modify: `LIfeOS/Features/Today/View/CalendarScreen.swift`
- Modify: `LIfeOS/Features/Today/View/WeekBands.swift`
- Modify: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:101`

**Interfaces:**
- Consumes: `ScheduleSearch.matches(_:in:)` (Task 1), `ScheduleFindText` (Task 2), `HairlineField` (Task 3), `EditorialRow`, `Hairline`, `MonthViewModel.eventsByDay` and `select(_:)`.
- Produces: `CalendarScreen(initialQuery:)`; `WeekBands(model:highlighted:onTapEvent:onAddEvent:)`; `ScheduleResultsBlock(results:months:onSelect:)`; `ScheduleResultRow(event:action:)` (Task 7 reuses it in the reply card); the private `reveal(_:)` on the screen (Task 7 calls it when a reply lands); preview page `calendar-find` with `--query=`.

- [ ] **Step 1: The results block and row**

Create `LIfeOS/Features/Today/View/CalendarFindAsk.swift`:

```swift
import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The block under the field while a query is live: an eyebrow with the
/// count, one quiet sentence naming the months the find covers, then up to
/// eight rows and a `4 more` line. A row tap shows the event's week.
struct ScheduleResultsBlock: View {
    let results: [CalendarEventSnapshot]
    let months: [Date]
    var onSelect: (CalendarEventSnapshot) -> Void
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current
    private static let limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(ScheduleFindText.eyebrow(found: results.count)).editorialEyebrow()
            Text(ScheduleFindText.scope(months: months, calendar: calendar))
                .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.prefix(Self.limit)) { event in
                        ScheduleResultRow(event: event) { onSelect(event) }
                    }
                }
                .padding(.top, Space.x1)
                if results.count > Self.limit {
                    Text(ScheduleFindText.more(results.count - Self.limit))
                        .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                        .padding(.top, Space.x1)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One found event: `Tue 13 · 10:00` in quiet ink, the title in ink, an
/// arrow, a hairline underneath. The same row the week bands draw, so a
/// result and a band entry read as the same thing.
struct ScheduleResultRow: View {
    let event: CalendarEventSnapshot
    var action: () -> Void

    private var label: String {
        ScheduleFindText.rowLabel(start: event.startDate, isAllDay: event.isAllDay)
    }

    var body: some View {
        Button(action: action) {
            EditorialRow(label) {
                HStack(spacing: Space.half) {
                    Text(event.title).lineLimit(2)
                    Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(label)")
        .accessibilityHint("Shows its week")
    }
}
```

- [ ] **Step 2: The bands mark matching rows**

In `WeekBands.swift`, add the stored property after `let model: MonthViewModel`:

```swift
    let model: MonthViewModel
    /// Ids of the events a live query matched; their rows get a 6pt accent
    /// dot before the time. Empty when nothing is being found.
    var highlighted: Set<UUID> = []
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }
```

and change the event row inside `band(_:)` from

```swift
                    ForEach(rows) { event in
                        Button { onTapEvent(event) } label: {
                            EditorialRow(event.timeLabel) {
                                HStack(spacing: Space.half) {
                                    Text(event.title).lineLimit(2)
                                    Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.title), \(event.spanLabel)")
                    }
```

to

```swift
                    ForEach(rows) { event in
                        Button { onTapEvent(event) } label: {
                            HStack(alignment: .center, spacing: Space.half) {
                                if highlighted.contains(event.id) {
                                    Circle().fill(LifeOSTokens.accent).frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                }
                                EditorialRow(event.timeLabel) {
                                    HStack(spacing: Space.half) {
                                        Text(event.title).lineLimit(2)
                                        Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.title), \(event.spanLabel)")
                    }
```

- [ ] **Step 3: The screen: query, field, results and marks**

In `CalendarScreen.swift`:

(a) After `@State private var showDatePicker = false`, add:

```swift
    /// What the person is finding. Trimmed for matching; the block and the
    /// marks show only while the trimmed text is not empty.
    @State private var query: String
```

(b) Change the init to take an initial query (for previews) and seed the state:

```swift
    init(
        initialMode: CalendarMode = .monthly,
        initialSelection: Date? = nil,
        initialQuery: String = "",
        onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
        onAddEvent: @escaping (Date) -> Void = { _ in },
        isCalendarConnected: Bool = true,
        onConnectCalendar: @escaping () -> Void = {}
    ) {
        _mode = State(initialValue: initialMode)
        _query = State(initialValue: initialQuery)
        self.initialSelection = initialSelection
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self.isCalendarConnected = isCalendarConnected
        self.onConnectCalendar = onConnectCalendar
    }
```

(c) After `isOnToday`, add the find state:

```swift
    private var quiet: Color { Editorial.quietInk(scheme) }

    private var isFinding: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Everything the model holds: the two shown months and their padding.
    /// Nothing is fetched on a keystroke.
    private var results: [CalendarEventSnapshot] {
        guard isFinding else { return [] }
        return ScheduleSearch.matches(query, in: model.eventsByDay.values.flatMap { $0 })
    }

    /// Shows the week of an event: a result tap, and later a reply's events.
    /// The query stays so several results can be visited.
    private func reveal(_ event: CalendarEventSnapshot) {
        withAnimation(.snappy(duration: 0.22)) {
            model.select(event.startDate)
            mode = .weekly
        }
    }
```

(d) Replace the body's `ScrollView { VStack(alignment: .leading, spacing: Space.x3) { header ... } ... }` top section so the field and the results sit between the switch and the connect card, and the marks reach the grid and the bands. The new `ScrollView` content, down to the `Go back` button, is:

```swift
            ScrollView {
                let found = results
                let matchingDays = Set(found.map { calendar.startOfDay(for: $0.startDate) })
                VStack(alignment: .leading, spacing: Space.x3) {
                    header
                    UnderlinePicker(
                        selection: $mode.animation(.snappy(duration: 0.22)),
                        options: [(.monthly, "Monthly"), (.weekly, "Weekly")]
                    )
                    findField
                    if isFinding {
                        ScheduleResultsBlock(results: found, months: months, onSelect: reveal)
                    }
                    if !isCalendarConnected { connectCard }
                    switch mode {
                    case .monthly:
                        VStack(alignment: .leading, spacing: Space.x4) {
                            ForEach(months, id: \.self) { month in
                                monthBlock(month, matching: matchingDays)
                            }
                        }
                    case .weekly:
                        WeekBands(model: model, highlighted: Set(found.map(\.id)),
                                  onTapEvent: onTapEvent, onAddEvent: onAddEvent)
                    }
                    Button("Go back") { dismiss() }
                        .buttonStyle(.editorial(.secondary, fullWidth: true))
                }
```

Everything after the `VStack` (the frame, padding, gesture, background, sheet, task, onReceive, onChange) stays as it is.

(e) After `connectCard`, add the field:

```swift
    private var findField: some View {
        HairlineField(text: $query, placeholder: ScheduleFindText.placeholder)
    }
```

(f) Change `monthBlock` to take the matching days and pass each cell's:

```swift
    private func monthBlock(_ month: Date, matching: Set<Date>) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Editorial.headline(34)).tracking(-1)
                .foregroundStyle(isCurrent ? LifeOSTokens.accent : ink)
                .accessibilityAddTraits(.isHeader)
            WeekdayHeader(calendar: calendar, today: isCurrent ? .now : nil, spacing: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(MonthGridLayout.cells(monthContaining: month, calendar: calendar, today: .now, status: { _ in .noData })) { cell in
                    if let date = cell.date {
                        dayCell(date, isMatch: matching.contains(calendar.startOfDay(for: date)))
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
        }
    }
```

(g) Change `dayCell` so a matching day draws its number and dot in the accent, with the today cell's number staying paper:

```swift
    private func dayCell(_ date: Date, isMatch: Bool) -> some View {
        let state = MonthDayState.of(date, calendar: calendar)
        let count = model.events(on: date).count
        let mark: Color = state == .today ? paper : (isMatch ? LifeOSTokens.accent : ink)
        return Button {
            model.select(date)
            withAnimation(.snappy(duration: 0.22)) { mode = .weekly }
        } label: {
            ZStack {
                if state == .today { Rectangle().fill(LifeOSTokens.accent) }
                if state == .past {
                    HatchedCell().stroke(LifeOSTokens.accent, lineWidth: 1).opacity(0.55)
                }
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(state == .today || isMatch ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(mark)
                    Circle()
                        .fill(mark)
                        .frame(width: 3, height: 3)
                        .opacity(count > 0 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme), lineWidth: 0.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(count) events")
        .accessibilityHint("Shows its week")
        .accessibilityAddTraits(state == .today ? [.isSelected] : [])
    }
```

- [ ] **Step 4: The preview page**

In `TodayDesignPreview.swift`:

(a) Extend the doc comment on lines 7 to 11 to list the new page:

```swift
/// Fixture pages for Today, the calendar screen, the day sheet and Notes,
/// mounted by `--design-preview` with `--page=today`, `today-empty`,
/// `today-done`, `month` (the calendar in Monthly), `schedule` (the calendar
/// in Weekly), `calendar-find` (the calendar with `--query=` live), `day`,
/// `day-past`, `notes` or `notes-empty`. `--select=` opens the calendar
/// pages on a given day.
```

(b) After the `selected` property, add:

```swift
    /// `--query=den` opens the calendar with that text in the field, so the
    /// results block and the grid marks can be captured without typing.
    private var query: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--query=") })?.dropFirst(8).description ?? ""
    }
```

(c) After the `case "schedule":` line pair, add:

```swift
            case "calendar-find":
                NavigationStack { CalendarScreen(initialSelection: selected, initialQuery: query) }.modelContainer(fixture.container)
```

In `HealthActivityDesignPreview.swift` line 101, add `"calendar-find"` to the array after `"schedule"`:

```swift
            else if ["today", "today-empty", "today-done", "month", "schedule", "calendar-find", "day", "day-past", "notes", "notes-empty"].contains(page) { TodayDesignPreview(page: page) }
```

- [ ] **Step 5: Build the app**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet 2>&1 | grep -E "error:" | head; echo "build exit ${PIPESTATUS[0]}"
```

Expected: `build exit 0`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Today/View/CalendarFindAsk.swift LIfeOS/Features/Today/View/CalendarScreen.swift \
  LIfeOS/Features/Today/View/WeekBands.swift LIfeOS/Features/Today/View/TodayDesignPreview.swift \
  LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(calendar): find events as you type from the calendar screen

A hairline field over the grid; typing matches titles, places and
calendar names across the shown months, lists up to eight with a count
and the scope, marks matching days in the accent and matching band rows
with a dot, and a result tap opens its week."
```

---

### Task 7: Ask: the arrow, the reply card, and the calendar follows the answer

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/Chat.swift:128-155` (`ChatConfirmation`)
- Modify: `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift:28-35,78-80` (DEBUG preview override)
- Modify: `LIfeOS/Features/Today/View/CalendarFindAsk.swift` (add `CalendarAsk` and `AssistantReplyCard`)
- Modify: `LIfeOS/Features/Today/View/CalendarScreen.swift`
- Modify: `LIfeOS/App/RootView.swift:431-436`
- Modify: `LIfeOS/Features/Assistant/View/AssistantSheet.swift:67-71`
- Modify: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:101`

**Interfaces:**
- Consumes: `AssistantViewModel` (`draft`, `send()`, `appear()`, `isThinking`, `isAuthorized`, `modelAvailable`, `messages: [ChatMessageSnapshot]`, `eventsByMessage: [UUID: [CalendarEventSnapshot]]`, `pending: [PendingWrite]`, `confirm(_:)`, `cancel(_:)`), `ChatThinking`, `ChatToolTags`, `ChatConfirmation`, `ScheduleResultRow` and `reveal(_:)` from Task 6.
- Produces: `struct CalendarAsk: Equatable { let question: String; var replyID: UUID? }`; `AssistantReplyCard(ask:assistant:onSelect:onClear:)`; `CalendarScreen(assistant:initialQuestion:)`; `ChatConfirmation(lines:framed:onConfirm:onCancel:)`; `AssistantViewModel.previewModelAvailable` (DEBUG); preview page `calendar-ask`, and `--no-model` on both calendar pages.

- [ ] **Step 1: `ChatConfirmation` can sit inside another card**

In `Chat.swift`, change `ChatConfirmation` to:

```swift
/// A write the assistant wants to make, awaiting a yes or a no. Framed as
/// its own card in a transcript; unframed inside the calendar's reply card.
public struct ChatConfirmation: View {
    let lines: [String]
    let framed: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(lines: [String], framed: Bool = true,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.lines = lines; self.framed = framed
        self.onConfirm = onConfirm; self.onCancel = onCancel
    }

    public var body: some View {
        if framed {
            content.editorialCard()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: Space.half) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.x1) {
                Button("Confirm", action: onConfirm).buttonStyle(.editorial(.primary, size: .compact))
                Button("Cancel", action: onCancel).buttonStyle(.editorial(.secondary, size: .compact))
            }
        }
    }
}
```

Run: `cd LifeOSKit && swift build 2>&1 | grep -E "error:|Build complete" | tail -2`
Expected: `Build complete!`.

- [ ] **Step 2: The DEBUG model-availability override**

In `AssistantViewModel.swift`, inside the existing `#if DEBUG` block after `previewAuthorized`, add:

```swift
    /// Design previews run on a simulator without the model; this answers
    /// `modelAvailable` so the ask arrow can be drawn, or hidden on purpose.
    var previewModelAvailable: Bool?
```

and change `modelAvailable` to:

```swift
    var modelAvailable: Bool {
        #if DEBUG
        if let previewModelAvailable { return previewModelAvailable }
        #endif
        return ModelAvailability.from(SystemLanguageModel.default.availability) == .available
    }
```

- [ ] **Step 3: `CalendarAsk` and the reply card**

Append to `CalendarFindAsk.swift`:

```swift
/// One question asked from the calendar: the words, and once the assistant
/// has answered, the id of its reply in the shared conversation.
struct CalendarAsk: Equatable {
    let question: String
    var replyID: UUID?
}

/// The reply, on the calendar: the question as a quiet line, `Thinking…`
/// until the answer lands, the answer, the events it was about as the same
/// rows the find draws, what the tools did as tags, any write awaiting a
/// yes, and `Clear`. The conversation itself stays in the assistant sheet.
struct AssistantReplyCard: View {
    let ask: CalendarAsk
    let assistant: AssistantViewModel
    var onSelect: (CalendarEventSnapshot) -> Void
    var onClear: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var reply: ChatMessageSnapshot? {
        guard let id = ask.replyID else { return nil }
        return assistant.messages.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Assistant").editorialEyebrow()
            Text(ask.question)
                .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if reply == nil, assistant.isThinking, assistant.pending.isEmpty {
                ChatThinking()
            }
            if let reply {
                Text(reply.text)
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let events = assistant.eventsByMessage[reply.id], !events.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            ScheduleResultRow(event: event) { onSelect(event) }
                        }
                    }
                }
                if !reply.toolSummaries.isEmpty {
                    ChatToolTags(reply.toolSummaries)
                }
            }
            ForEach(assistant.pending) { write in
                ChatConfirmation(lines: write.preview, framed: false,
                                 onConfirm: { assistant.confirm(write.id) },
                                 onCancel: { assistant.cancel(write.id) })
            }
            Button("Clear", action: onClear)
                .buttonStyle(.editorial(.quiet, size: .compact))
                .accessibilityHint("Hides the reply; the conversation stays in the assistant")
        }
        .editorialCard()
    }
}
```

- [ ] **Step 4: The screen asks**

In `CalendarScreen.swift`:

(a) After `@State private var query: String`, add:

```swift
    /// The question asked from here and, once answered, its reply. While
    /// set, the reply card stands where the results block would.
    @State private var asked: CalendarAsk?

    /// The one assistant the app owns; nil in previews that never ask.
    private let assistant: AssistantViewModel?
    /// For the `calendar-ask` preview: adopt the conversation's last reply
    /// as the answer to this question on appear, so no model runs.
    private let initialQuestion: String?
```

(b) Change the init to:

```swift
    init(
        assistant: AssistantViewModel? = nil,
        initialMode: CalendarMode = .monthly,
        initialSelection: Date? = nil,
        initialQuery: String = "",
        initialQuestion: String? = nil,
        onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
        onAddEvent: @escaping (Date) -> Void = { _ in },
        isCalendarConnected: Bool = true,
        onConnectCalendar: @escaping () -> Void = {}
    ) {
        _mode = State(initialValue: initialMode)
        _query = State(initialValue: initialQuery)
        self.assistant = assistant
        self.initialSelection = initialSelection
        self.initialQuestion = initialQuestion
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self.isCalendarConnected = isCalendarConnected
        self.onConnectCalendar = onConnectCalendar
    }
```

(c) After `reveal(_:)`, add the ask state and flow:

```swift
    /// An assistant was passed, the device model is there, and the calendar
    /// is connected. Find works without any of these.
    private var canAsk: Bool {
        guard let assistant else { return false }
        return assistant.modelAvailable && assistant.isAuthorized
    }

    /// The calendar is connected but the model is not on this device: say
    /// so under the field once there is text, instead of a dead arrow.
    private var needsModel: Bool {
        guard let assistant, isFinding else { return false }
        return assistant.isAuthorized && !assistant.modelAvailable
    }

    /// Hands the words to the assistant as a turn in the one conversation
    /// the sheet shows, then adopts its reply.
    private func ask() async {
        guard let assistant, canAsk, !assistant.isThinking else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        query = ""
        asked = CalendarAsk(question: text, replyID: nil)
        assistant.draft = text
        await assistant.send()
        adoptReply(for: text)
    }

    /// The reply is the conversation's last assistant turn. The calendar
    /// follows it: the earliest event it was about opens in Weekly.
    private func adoptReply(for question: String) {
        guard let assistant,
              let reply = assistant.messages.last(where: { $0.role == .assistant })
        else { return }
        asked = CalendarAsk(question: question, replyID: reply.id)
        if let first = assistant.eventsByMessage[reply.id]?.first {
            reveal(first)
        }
    }
```

(d) In the body, replace

```swift
                    findField
                    if isFinding {
                        ScheduleResultsBlock(results: found, months: months, onSelect: reveal)
                    }
```

with

```swift
                    findField
                    if let asked, let assistant {
                        AssistantReplyCard(ask: asked, assistant: assistant, onSelect: reveal,
                                           onClear: { self.asked = nil })
                    } else if isFinding {
                        ScheduleResultsBlock(results: found, months: months, onSelect: reveal)
                    }
```

(e) Replace `findField` with the field, the arrow and the needs-model line:

```swift
    private var findField: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HairlineField(text: $query, placeholder: ScheduleFindText.placeholder,
                          onSubmit: { Task { await ask() } }) {
                if isFinding, canAsk { askArrow }
            }
            if needsModel {
                Text(ScheduleFindText.needsModel)
                    .font(LifeOSType.caption).foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// An ink circle with `arrow.up` in paper: the composer's send, at the
    /// field's size.
    private var askArrow: some View {
        Button { Task { await ask() } } label: {
            Image(systemName: "arrow.up")
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(paper)
                .frame(width: 32, height: 32)
                .background(Circle().fill(ink))
        }
        .buttonStyle(.plain)
        .disabled(assistant?.isThinking ?? true)
        .accessibilityLabel("Ask")
    }
```

(f) Change the `.task` so the assistant appears and the preview question is adopted:

```swift
            .task {
                model.attach(context)
                if let initialSelection { model.goTo(initialSelection) }
                await assistant?.appear()
                if let initialQuestion { adoptReply(for: initialQuestion) }
            }
```

- [ ] **Step 5: One assistant, from both callers**

In `RootView.swift`, the `navigationDestination(isPresented: $showMonth)` block becomes:

```swift
                    .navigationDestination(isPresented: $showMonth) {
                        CalendarScreen(
                            assistant: assistantModel,
                            onTapEvent: { eventSheet = .edit($0) },
                            onAddEvent: { eventSheet = .create(on: $0) },
                            isCalendarConnected: today.snapshot.calendarAccess == .authorized,
                            onConnectCalendar: { requestCalendarAccess() }
                        )
                    }
```

In `AssistantSheet.swift`, the `Schedule` link's destination becomes:

```swift
                    NavigationLink {
                        CalendarScreen(assistant: model,
                                       onTapEvent: { eventSheet = .edit($0) },
                                       onAddEvent: { eventSheet = .create(on: $0) },
                                       isCalendarConnected: model.isAuthorized,
                                       onConnectCalendar: { Task { await model.connectCalendar() } })
                    } label: { Label("Schedule", systemImage: "calendar") }
```

- [ ] **Step 6: The preview pages**

In `TodayDesignPreview.swift`:

(a) The doc comment gains the page: after `calendar-find` (the calendar with `--query=` live), add `calendar-ask` (the reply card from a seeded conversation; `--no-model` on either calendar page hides the arrow and shows the needs-model line).

(b) Replace the `calendar-find` case and add `calendar-ask`:

```swift
            case "calendar-find":
                NavigationStack {
                    CalendarScreen(assistant: fixture.assistant, initialSelection: selected, initialQuery: query)
                }
                .modelContainer(fixture.container)
            case "calendar-ask":
                NavigationStack {
                    CalendarScreen(assistant: fixture.assistant, initialSelection: selected,
                                   initialQuestion: TodayFixture.question)
                }
                .modelContainer(fixture.container)
```

(c) In `TodayFixture`, after `let events: [CalendarEventSnapshot]`, add the seeded assistant. It is lazy so the Today and Notes pages never touch the conversation key:

```swift
    static let question = "When is the dentist?"

    /// The calendar pages share one assistant, seeded with a question about
    /// the dentist and its answer under the conversation id the model loads,
    /// so the reply card draws without a model turn. `--no-model` hides the
    /// ask arrow the way a device without Apple Intelligence would.
    private(set) lazy var assistant: AssistantViewModel = {
        let model = AssistantViewModel(context: container.mainContext)
        model.previewAuthorized = true
        model.previewModelAvailable = !ProcessInfo.processInfo.arguments.contains("--no-model")
        let id = UUID()
        UserDefaults.currentAccount.set(id.uuidString, forKey: "assistant.conversationID")
        let chat = ChatStore(context: container.mainContext)
        try! chat.append(conversationID: id, role: .user, text: Self.question)
        try! chat.append(conversationID: id, role: .assistant,
                         text: "Your dentist is tomorrow at 10:00, for an hour. Nothing else is booked that morning.",
                         toolSummaries: ["Checked your calendar"],
                         eventIDs: [events.first { $0.title == "Dentist" }!.id])
        return model
    }()
```

In `HealthActivityDesignPreview.swift` line 101, add `"calendar-ask"` after `"calendar-find"`.

- [ ] **Step 7: Build the app**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet 2>&1 | grep -E "error:" | head; echo "build exit ${PIPESTATUS[0]}"
```

Expected: `build exit 0`.

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/Chat.swift LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift \
  LIfeOS/Features/Today/View/CalendarFindAsk.swift LIfeOS/Features/Today/View/CalendarScreen.swift \
  LIfeOS/App/RootView.swift LIfeOS/Features/Assistant/View/AssistantSheet.swift \
  LIfeOS/Features/Today/View/TodayDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(calendar): ask the assistant from the calendar screen

Return or the arrow hands the words to the one assistant the app owns;
the reply lands on the screen as a card with the events it was about,
the tool tags and any write awaiting a yes, and the calendar opens the
week of the earliest event. Without the device model the arrow is
hidden and a line says so."
```

---

### Task 8: Gates and captures

- [ ] **Step 1: The whole package and the typography gate**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
(cd LifeOSKit && swift test 2>&1 | tail -2)
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/068489d1-9b0b-4686-8c3b-702504137000/scratchpad
scripts/check-typography.sh > $OUT/typo-ask.txt 2>&1
diff <(sed 's/^[^:]*://' $OUT/typo-base.txt | sort) <(sed 's/^[^:]*://' $OUT/typo-ask.txt | sort) | grep '^>' || echo "typography: no new violations"
```

Expected: `Test run with 1428 tests in 198 suites passed` (1417 plus the eleven added here, three of them in new suites) and `typography: no new violations`.

- [ ] **Step 2: Install and capture**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/editorial-calendar-ask/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B192EA65-BAA2-4814-A298-94A2F0C8FC87
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/068489d1-9b0b-4686-8c3b-702504137000/scratchpad
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-ask-$name.png" >/dev/null; }
capture month --page=month
capture schedule --page=schedule
capture find --page=calendar-find --query=den
capture find-dark --page=calendar-find --query=den --dark
capture find-weekly --page=calendar-find --query=den --select=$(date -v+1d +%F)
capture find-nothing --page=calendar-find --query=zzz
capture find-nomodel --page=calendar-find --query=den --no-model
capture ask --page=calendar-ask
capture ask-dark --page=calendar-ask --dark
capture notes --page=notes
ls -la $OUT/pr-ask-*.png
```

Open each capture with the Read tool and check:
- `month` and `schedule`: the field sits under the switch with the placeholder, no arrow, no block; the grid and bands look as before.
- `find`: `FOUND 2`, the scope sentence naming this month and next, rows `Dentist` tomorrow and `Dentist follow-up` seven days ago with `Wed 7 · 10:00`-style labels, the arrow in the field, tomorrow's number and dot in the accent on the grid.
- `find-weekly`: tomorrow open with a 6pt accent dot before the `Dentist` row's time.
- `find-nothing`: `NOTHING FOUND` and the scope sentence, no rows, no marks.
- `find-nomodel`: no arrow; the quiet line `Asking needs Apple Intelligence on this device.` under the field.
- `ask`: the card with `ASSISTANT`, the question in quiet ink, the reply, the `Dentist` row, the `Checked your calendar` tag, `Clear`; the calendar in Weekly with tomorrow open.
- `notes`: the shelf's search field on a hairline with `xmark.circle` absent (no text), unchanged otherwise.

If `find` shows `FOUND 1`, the follow-up seven days ago fell outside the month's padding week; that is correct for a date more than seven days into the month and needs no change.

- [ ] **Step 3: Type and tap on the simulator**

One typing check and one tap, each with a screenshot after. Follow the recipe in memory (`driving-lifeos-ios-simulator`): make the Simulator frontmost right before each `cliclick`, read the window's AXGroup for the scale, and measure on the full-resolution screenshot. Launch `--page=month`, tap the field, type `den` with `cliclick t:den`, screenshot (`pr-ask-typed.png`), tap the `Dentist` row, screenshot (`pr-ask-tapped.png`): Weekly, tomorrow open, the query still in the field. If two taps in a row leave the screenshot unchanged, stop: the `find` and `find-weekly` captures already cover the states, and the tap path is the same `reveal(_:)` the preview exercises.

- [ ] **Step 4: Record the outcome**

Note in the PR body which captures were made and whether the tap check ran.

---

### Task 9: Open the pull request

- [ ] **Step 1: Rebase on the latest main and re-run the package tests**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar-ask
git fetch origin && git rebase origin/main && (cd LifeOSKit && swift test 2>&1 | tail -1)
```

Expected: a clean rebase (or none needed) and the same pass line.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin feat/editorial-calendar-ask
gh pr create --base main --title "feat(calendar): find and ask from the calendar screen" --body-file $OUT/pr-body.md
```

The body (written to `$OUT/pr-body.md` first) has three sections in the house style, `## Summary`, `## Verification`, `## Deferred minors`, and names the spec and this plan. No attribution footer.

- [ ] **Step 3: Update memory**

Update `editorial-part-two-progress.md`: PR 3 of the calendar work is open as PR #N on `feat/editorial-calendar-ask` (worktree `.claude/worktrees/editorial-calendar-ask`, simulator `CalendarAsk iPhone 17`); next is `feat/editorial-calendar-widget` (spec section 3) from `main` once this merges.
