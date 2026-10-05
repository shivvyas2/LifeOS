# Editorial Today, Notes, month and schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Today tab, the Notes shelf, the month screen behind the calendar button, the day schedule, and the dot-grid day sheet onto the editorial mono theme, with teaching empty states and preview pages to prove it.

**Architecture:** Every piece of wording or date logic that can be wrong lives in a small pure value in `DesignSystem` with tests (`TodayHeadline`, `MonthDayState`, `WeekSpan`, `NotesHeadline`); the screens are composed from the existing `Editorial.swift` pieces plus PR 1's `EditorialEmptyState`, a `HatchedCell` shape, and an `ink` style on `TrendStatTile`. The month screen gains a pushed `DayScheduleScreen` that reads the same `MonthViewModel`. Fixture-fed DEBUG preview pages render each screen without sign-in.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md`, sections 3 (Today), "Month and schedule", 4 (Notes), 7 and 8 (PR 2). PR 1 (`feat/editorial-shell-life`, GitHub #19) is the base.

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. The accent (`LifeOSTokens.accent`) appears only on today's calendar cell, the hatch on past days, and today's number on the schedule. No new colours.
- One gradient field per screen at most: Today's agenda is its field; the month screen, the schedule, the day sheet and Notes have none.
- Every button uses `.buttonStyle(.editorial(role))`. No bare accent capsules, no `CapsuleButton`.
- Fonts come only from `LifeOSType` or `Editorial.figure(_:)` / `Editorial.headline(_:)`; `scripts/check-typography.sh` must report nothing new versus the base branch. Semantic fonts such as `.largeTitle`, `.subheadline`, `.caption`, `.title3` in the files this plan touches are replaced with scale steps.
- The Today dot grid (`MonthCalendarView`) is not touched.
- `DayPart.hue` and the module pastels leave the Today feature; `EventJourneyRow` is deleted once nothing uses it.
- `LifeOSKit` also builds for macOS (`swift test` runs there): iOS-only APIs stay out of the package or go under `#if os(iOS)`.
- `LIfeOS/` is a synchronized folder in the Xcode project: new files under it need no `project.pbxproj` edit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind.
- Work happens in a new worktree `.claude/worktrees/editorial-today-notes` on branch `feat/editorial-today-notes`, cut from `feat/editorial-shell-life` (or from `main` once PR #19 has merged; rebase onto main at the end either way). Copy `Config/Secrets.xcconfig` in from the main checkout first.

## Review Focus

1. A past day's eyebrow carries no weekday ("Oct 3"), today's does ("Today · Monday, Oct 5"): `TodayHeadlineTests.pastDayHasNoWeekday` in Task 1.
2. A one-day streak reads "1-day streak", never "1-days streak", and no streak reads "Start a streak today": `TodayHeadlineTests.streakWording` in Task 1.
3. Today at 23:59 is still today, not past, and tomorrow at 00:00 is future: `MonthDayStateTests.todayIsTodayUntilMidnight` in Task 2.
4. The schedule's week starts on the calendar's first weekday (Sunday in en_US, Monday in en_GB), seven days long, containing the chosen day: `WeekSpanTests.weekFollowsTheCalendar` in Task 2.
5. The Notes eyebrow pluralises ("No pages", "1 page", "24 pages"): `NotesHeadlineTests.countWording` in Task 7.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/TodayHeadline.swift` (new) | Today's masthead text |
| `LifeOSKit/Tests/DesignSystemTests/TodayHeadlineTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/MonthDayState.swift` (new) | Past/today/future, `WeekSpan`, `HatchedCell` shape |
| `LifeOSKit/Tests/DesignSystemTests/MonthDayStateTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/NotesHeadline.swift` (new) | Notes eyebrow wording |
| `LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/TrendStatTile.swift` | `Style.ink` |
| `LIfeOS/Features/Today/View/TodayScreen.swift` | Masthead, tiles, cards |
| `LIfeOS/Features/Today/View/AgendaCard.swift` | The agenda field, teaching state, upcoming card |
| `LIfeOS/Features/Today/View/MonthScreen.swift` | Editorial month blocks, hatched grid, push to schedule |
| `LIfeOS/Features/Today/ViewModel/MonthViewModel.swift` | Loads two months |
| `LIfeOS/Features/Today/View/DayScheduleScreen.swift` (new) | The week of stacked day bands |
| `LIfeOS/Features/Today/View/DayDetailSheet.swift` | Editorial rows and habits |
| `LIfeOS/Features/Notes/View/NoteShelfScreen.swift` | Masthead, search, section header, rows, empty state |
| `LIfeOS/Features/Notes/View/NoteCard.swift` | Scale fonts, arrow |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift` (new, DEBUG) | Pages `today`, `today-empty`, `month`, `schedule`, `day`, `notes`, `notes-empty` |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Routes those pages |

---

### Task 0: Worktree

- [ ] **Step 1: Create the worktree from PR 1's branch**

```bash
cd /Users/shivvyas/LIfeOS
git fetch origin
git worktree add .claude/worktrees/editorial-today-notes -b feat/editorial-today-notes feat/editorial-shell-life
cp Config/Secrets.xcconfig .claude/worktrees/editorial-today-notes/Config/
cd .claude/worktrees/editorial-today-notes && git log --oneline -1
```

Expected: HEAD is PR 1's last commit (`fix(life): name the newest closed month...` or later).

---

### Task 1: `TodayHeadline`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/TodayHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/TodayHeadlineTests.swift`

**Interfaces:**
- Produces: `TodayHeadline.make(date:now:streak:calendar:locale:) -> TodayHeadline { eyebrow, title, detail }`. Task 4 renders it.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodayHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func date(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func todayNamesTheDayAndGreetsByHour() {
        let h = TodayHeadline.make(date: date(5), now: date(5, hour: 9), streak: 6, calendar: calendar, locale: en)
        #expect(h.eyebrow == "Today · Monday, Oct 5")
        #expect(h.title == "Good morning")
        #expect(h.detail == "6-day streak")
        #expect(TodayHeadline.make(date: date(5), now: date(5, hour: 14), streak: 6, calendar: calendar, locale: en).title == "Good afternoon")
        #expect(TodayHeadline.make(date: date(5), now: date(5, hour: 19), streak: 6, calendar: calendar, locale: en).title == "Good evening")
    }

    @Test func pastDayHasNoWeekday() {
        let h = TodayHeadline.make(date: date(3), now: date(5), streak: 6, calendar: calendar, locale: en)
        #expect(h.eyebrow == "Oct 3")
        #expect(h.title == "Saturday")
    }

    @Test func streakWording() {
        #expect(TodayHeadline.make(date: date(5), now: date(5), streak: 1, calendar: calendar, locale: en).detail == "1-day streak")
        #expect(TodayHeadline.make(date: date(5), now: date(5), streak: 0, calendar: calendar, locale: en).detail == "Start a streak today")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd LifeOSKit && swift test --filter TodayHeadlineTests`
Expected: `cannot find 'TodayHeadline' in scope`.

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/DesignSystem/TodayHeadline.swift
import Foundation

/// Today's masthead: which day, a greeting for today or the weekday for
/// any other day, and the streak. A value so the wording is tested.
public struct TodayHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public static func make(
        date: Date, now: Date = .now, streak: Int,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> TodayHeadline {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        let eyebrow = isToday
            ? "Today · \(date.formatted(style.weekday(.wide).month(.abbreviated).day()))"
            : date.formatted(style.month(.abbreviated).day())
        let title: String
        if isToday {
            let hour = calendar.component(.hour, from: now)
            title = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        } else {
            title = date.formatted(style.weekday(.wide))
        }
        let detail = streak > 0 ? "\(streak)-day streak" : "Start a streak today"
        return TodayHeadline(eyebrow: eyebrow, title: title, detail: detail)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd LifeOSKit && swift test --filter TodayHeadlineTests`
Expected: `Test run with 3 tests in 1 suite passed`. (If "Monday, Oct 5" comes out as "Mon, Oct 5" or with a different separator, adjust the expectation to what `en_US` actually produces and keep the weekday-wide intent; note it in the ledger.)

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/TodayHeadline.swift LifeOSKit/Tests/DesignSystemTests/TodayHeadlineTests.swift
git commit -m "feat(design): derive Today's masthead as a tested value"
```

---

### Task 2: `MonthDayState`, `WeekSpan`, `HatchedCell`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/MonthDayState.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/MonthDayStateTests.swift`

**Interfaces:**
- Produces: `MonthDayState.of(_:today:calendar:) -> .past | .today | .future`; `WeekSpan.days(containing:calendar:) -> [Date]` (7 start-of-days); `HatchedCell: Shape`. Tasks 5 and 6 use them.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftUI
@testable import DesignSystem

@Suite struct MonthDayStateTests {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = firstWeekday; return c
    }
    private func date(_ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour, minute: minute))!
    }

    @Test func todayIsTodayUntilMidnight() {
        let today = date(5, hour: 23, minute: 59)
        #expect(MonthDayState.of(date(5), today: today, calendar: calendar()) == .today)
        #expect(MonthDayState.of(date(4, hour: 23, minute: 59), today: today, calendar: calendar()) == .past)
        #expect(MonthDayState.of(date(6), today: today, calendar: calendar()) == .future)
    }

    /// Sunday first in en_US, Monday first in en_GB: the week is the calendar's.
    @Test func weekFollowsTheCalendar() {
        let wednesday = date(7)
        let sundayFirst = WeekSpan.days(containing: wednesday, calendar: calendar(firstWeekday: 1))
        let mondayFirst = WeekSpan.days(containing: wednesday, calendar: calendar(firstWeekday: 2))
        #expect(sundayFirst.count == 7 && mondayFirst.count == 7)
        #expect(sundayFirst.first == date(4))
        #expect(mondayFirst.first == date(5))
        #expect(sundayFirst.contains(wednesday) && mondayFirst.contains(wednesday))
    }

    @Test func hatchDrawsInsideItsCell() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 48)
        let path = HatchedCell().path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd LifeOSKit && swift test --filter MonthDayStateTests`
Expected: `cannot find 'MonthDayState' in scope`.

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/DesignSystem/MonthDayState.swift
import SwiftUI

/// Where a calendar day stands against today. The month grid hatches the
/// past, fills today, and leaves the future on paper.
public enum MonthDayState: Equatable, Sendable {
    case past, today, future

    public static func of(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> MonthDayState {
        if calendar.isDate(date, inSameDayAs: today) { return .today }
        return date < calendar.startOfDay(for: today) ? .past : .future
    }
}

/// The seven days of the week a date falls in, as start-of-day dates, in
/// the calendar's own order.
public enum WeekSpan {
    public static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
}

/// Three thin diagonals across a cell, the reference's mark for a day that
/// has gone. Stroke it in the accent.
public struct HatchedCell: Shape {
    let lines: Int

    public init(lines: Int = 3) { self.lines = lines }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        let step = inset.width / CGFloat(lines + 1)
        for index in 1...max(lines, 1) {
            let x = inset.minX + step * CGFloat(index)
            // Each stroke runs up and to the right at 45°, clipped to the inset box.
            let run = min(inset.height, inset.maxX - x + step)
            path.move(to: CGPoint(x: x - step * 0.5, y: inset.maxY))
            path.addLine(to: CGPoint(x: x - step * 0.5 + run, y: inset.maxY - run))
        }
        return path
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd LifeOSKit && swift test --filter MonthDayStateTests`
Expected: `Test run with 3 tests in 1 suite passed`. If `hatchDrawsInsideItsCell` fails on the bounding rect, shrink `run` (the strokes must stay inside the inset box); do not widen the assertion.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/MonthDayState.swift LifeOSKit/Tests/DesignSystemTests/MonthDayStateTests.swift
git commit -m "feat(design): day state, week span and the hatched cell for the month grid"
```

---

### Task 3: `TrendStatTile` ink style

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/TrendStatTile.swift`

**Interfaces:**
- Produces: `TrendStatTile.Style` (`.module`, `.ink`) and a trailing `style: Style = .module` init parameter. Task 4 passes `style: .ink`. Health keeps the default.

- [ ] **Step 1: Add the style**

Add inside the struct, before the stored properties:

```swift
    /// The module look keeps the icon circle and the hue; ink is the editorial
    /// tile: an eyebrow, a light figure, bars in ink, and an arrow that says
    /// the tile opens.
    public enum Style: Sendable, Equatable { case module, ink }
```

Add `private let style: Style` after `baseline`, add `style: Style = .module` as the last init parameter, assign it, and change `body` to:

```swift
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch style {
            case .module: header; numeral
            case .ink: inkHeader; inkFigure
            }
            if series.hasAnyReading {
                chart
            } else {
                Color.clear.frame(height: chartHeight)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Editorial.rule(scheme)))
    }

    private var inkHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).editorialEyebrow()
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(LifeOSType.caption.weight(.semibold))
                .foregroundStyle(Editorial.quietInk(scheme))
                .accessibilityHidden(true)
        }
    }

    private var inkFigure: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.half) {
            Text(value ?? "—")
                .font(Editorial.figure(34)).tracking(Editorial.figureTracking(34))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
            if let unit, value != nil {
                Text(unit).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
```

and `chart` to pick the bar style:

```swift
    private var chart: some View {
        RoundedBarChart(
            bars: series.points.map {
                RoundedBarChart.Bar(id: $0.date, label: Self.initial(of: $0.date, calendar), value: $0.value)
            },
            style: style == .ink ? .ink : .hue(hue),
            goal: goal,
            baseline: baseline,
            spacing: layout.isRegular ? 8 : 5,
            height: chartHeight
        )
    }
```

- [ ] **Step 2: Build the package**

Run: `cd LifeOSKit && swift build`
Expected: builds; every existing `TrendStatTile(...)` call compiles unchanged (the new parameter has a default and is last).

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/TrendStatTile.swift
git commit -m "feat(design): ink style for the trend tile"
```

---

### Task 4: Today screen and the agenda field

**Files:**
- Modify: `LIfeOS/Features/Today/View/TodayScreen.swift`
- Modify: `LIfeOS/Features/Today/View/AgendaCard.swift`

**Interfaces:**
- Consumes: `TodayHeadline` (Task 1), `TrendStatTile(style: .ink)` (Task 3), `EditorialField`, `EditorialRow`, `EditorialSectionHeader`, `EditorialEmptyState`, `editorialCard()`.
- `AgendaCard`'s public init is unchanged: `AgendaCard(access:agenda:upcoming:onConnect:onAddEvent:onTapEvent:onOpenToday:)`.

- [ ] **Step 1: Rewrite `AgendaCard`'s views**

Keep the `CalendarEventSnapshot` extension (`timeLabel`, `durationLabel`, `spanLabel`) and the `DayPart` enum's `title`, `icon` and `of(_:calendar:)`; delete `DayPart.hue`. Replace everything from `struct AgendaCard: View {` to the end of the file with:

```swift
struct AgendaCard: View {
    let access: CalendarAccessState
    let agenda: [CalendarEventSnapshot]
    let upcoming: [UpcomingEvent]
    let onConnect: () -> Void
    let onAddEvent: () -> Void
    let onTapEvent: (CalendarEventSnapshot) -> Void
    let onOpenToday: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    private let calendar = Calendar.current
    private static let maxAgendaRows = 4
    private static let maxUpcomingRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            switch access {
            case .authorized: field
            case .notDetermined: teaching
            case .denied: denied
            }
            if access == .authorized, !upcoming.isEmpty { upcomingCard }
        }
    }

    /// The screen's one field: what is next, then the rest of the day.
    private var field: some View {
        let next = agenda.first
        let rest = Array(agenda.dropFirst().prefix(Self.maxAgendaRows))
        return EditorialField(.dusk) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next up").editorialEyebrow()
                Spacer(minLength: Space.x1)
                Button(action: onOpenToday) {
                    HStack(spacing: Space.half) {
                        Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                        Image(systemName: "chevron.down")
                    }
                }
                .buttonStyle(.editorial(.quiet, size: .compact))
                .accessibilityLabel("Open today's day view")
            }
            // The headline is the next event, and tapping it opens that event.
            Button { if let next { onTapEvent(next) } } label: {
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(next?.title ?? "Nothing scheduled")
                        .font(Editorial.headline(28)).tracking(-0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next?.spanLabel ?? "Add a plan when you're ready.")
                        .font(LifeOSType.secondary)
                        .opacity(0.75)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(next == nil)
            .accessibilityLabel(next.map { "\($0.title), \($0.spanLabel)" } ?? "Nothing scheduled")
            ForEach(rest) { event in
                Button { onTapEvent(event) } label: {
                    EditorialRow(event.timeLabel) {
                        HStack(spacing: Space.half) {
                            Text(event.title).lineLimit(1)
                            Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(event.spanLabel)")
            }
            if agenda.count > Self.maxAgendaRows + 1 {
                Button("+\(agenda.count - Self.maxAgendaRows - 1) more", action: onOpenToday)
                    .buttonStyle(.editorial(.quiet, size: .compact))
            }
            Button("Add", action: onAddEvent)
                .buttonStyle(.editorial(.secondary, size: .compact))
        }
    }

    /// Not connected: a ghost of the field and the one action that fills it.
    private var teaching: some View {
        EditorialEmptyState(
            sentence: "Your day's events, with the next one first.",
            action: "Connect calendar",
            onAction: onConnect
        ) {
            VStack(alignment: .leading, spacing: 0) {
                EditorialRow("09:00", value: "Standup")
                EditorialRow("12:30", value: "Lunch with Sam")
                EditorialRow("16:00", value: "Design review")
            }
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Calendar access is off.")
                .font(LifeOSType.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
        }
        .editorialCard()
    }

    private var upcomingCard: some View {
        let visible = Array(upcoming.prefix(Self.maxUpcomingRows))
        var groups: [(label: String, rows: [UpcomingEvent])] = []
        for row in visible {
            if groups.last?.label == row.dayLabel {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((row.dayLabel, [row]))
            }
        }
        return VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Upcoming")
            ForEach(groups, id: \.label) { group in
                Text(group.label).editorialEyebrow()
                ForEach(group.rows) { row in
                    Button { onTapEvent(row.event) } label: {
                        EditorialRow(row.event.timeLabel) {
                            HStack(spacing: Space.half) {
                                Text(row.event.title).lineLimit(1)
                                Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.event.title), \(row.event.spanLabel)")
                }
            }
            if upcoming.count > Self.maxUpcomingRows {
                Text("+\(upcoming.count - Self.maxUpcomingRows) more")
                    .font(LifeOSType.label)
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
        }
        .editorialCard()
    }
}
```

Delete `EventJourneyRow` from this file. Then `grep -rn 'EventJourneyRow\|DayPart.hue' LIfeOS` must show only `DayDetailSheet.swift` (handled in Task 8); if it shows anything else, keep `EventJourneyRow` until that caller is moved and note it in the ledger.

- [ ] **Step 2: Rewrite `TodayScreen`'s layout**

Replace `layoutBody`, `healthPrompt`, `scheduledWorkout`, `statGrid`, `tile` and `streakLine` with:

```swift
    @ViewBuilder
    private var layoutBody: some View {
        if layout.isRegular {
            HStack(alignment: .top, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    masthead
                    agendaCard
                    month
                    scheduledWorkout
                }
                .frame(maxWidth: 520)
                VStack(alignment: .leading, spacing: Space.x3) {
                    if showsHealthPrompt { healthPrompt }
                    statGrid(columns: 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.x3) {
                masthead
                agendaCard
                month
                scheduledWorkout
                if showsHealthPrompt { healthPrompt }
                statGrid(columns: layout.statColumns)
            }
        }
    }

    private var masthead: some View {
        let headline = TodayHeadline.make(date: snapshot.date, streak: snapshot.streak, calendar: calendar)
        return EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
    }

    private var showsHealthPrompt: Bool {
        snapshot.hasNoHealthData && !isHealthConnected
    }

    private var healthPrompt: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("No health data yet").font(LifeOSType.rowTitle)
            Text("Steps, sleep, weight and recovery come from Apple Health and Whoop. Connect one and this fills in.")
                .font(LifeOSType.secondary)
                .foregroundStyle(Editorial.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect Apple Health", action: onConnectHealth)
                .buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    @ViewBuilder
    private var scheduledWorkout: some View {
        if let title = snapshot.scheduledWorkoutTitle {
            VStack(alignment: .leading, spacing: Space.half) {
                EditorialRow("Scheduled workout", value: title)
                Text("In Workout library").font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
            .editorialCard()
            .accessibilityElement(children: .combine)
        }
    }

    /// Ghosted sample figures while nothing is connected: the tiles show
    /// what they will hold, and the card above says how to fill them.
    private func statGrid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(TodayMetric.allCases) { metric in
                Button { onSelectMetric(metric) } label: {
                    tile(metric)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(metric))
                .accessibilityHint("Opens \(metric.title.lowercased()) history")
            }
        }
        .opacity(showsHealthPrompt ? 0.35 : 1)
        .allowsHitTesting(!showsHealthPrompt)
        .accessibilityHidden(showsHealthPrompt)
    }

    private func tile(_ metric: TodayMetric) -> some View {
        TrendStatTile(
            icon: metric.icon,
            hue: metric.hue,
            label: metric.title,
            value: (showsHealthPrompt ? sample(metric) : latest(metric)).map(metric.format),
            unit: metric.unit,
            series: showsHealthPrompt ? sampleSeries : series(metric),
            goal: goal(metric),
            baseline: metric.baseline,
            style: .ink
        )
    }

    private func sample(_ metric: TodayMetric) -> Double {
        switch metric {
        case .steps: 8_240
        case .sleep: 432
        case .weight: 77.4
        case .recovery: 82
        }
    }

    private var sampleSeries: TrendSeries {
        TrendSeries(points: (0..<7).map { offset in
            TrendPoint(date: calendar.date(byAdding: .day, value: offset - 6, to: snapshot.date) ?? snapshot.date,
                       value: Double(60 + (offset * 7) % 30))
        })
    }
```

Keep `latest`, `series`, `goal`, `accessibilityLabel`, `agendaCard`, `month` and `duration` as they are. Change the outer padding `.padding(.top, 24)` to `.padding(.top, Space.x3)`.

- [ ] **Step 3: Build**

Run from the worktree root: `xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet`
Expected: zero errors. `grep -c 'SoftCard\|CapsuleButton\|streakLine' LIfeOS/Features/Today/View/TodayScreen.swift LIfeOS/Features/Today/View/AgendaCard.swift` prints `0` for both.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/TodayScreen.swift LIfeOS/Features/Today/View/AgendaCard.swift
git commit -m "feat(today): masthead, the agenda as the one field, ink tiles and a teaching state"
```

---

### Task 5: Month screen on hairlines

**Files:**
- Modify: `LIfeOS/Features/Today/View/MonthScreen.swift`
- Modify: `LIfeOS/Features/Today/ViewModel/MonthViewModel.swift` (the `load()` window)

**Interfaces:**
- Consumes: `MonthDayState`, `HatchedCell` (Task 2), `WeekdayHeader(calendar:today:spacing:)`, `MonthGridLayout.cells(monthContaining:calendar:today:status:)`, `MonthViewModel` (`month`, `events(on:)`, `step(_:)`, `goTo(_:)`, `goToToday()`, `attach`, `load`).
- Produces: pushes `DayScheduleScreen(model:day:onTapEvent:onAddEvent:)` (Task 6) through `navigationDestination(item:)`. To build Task 5 alone, add Task 6's file first; the two are built together.

- [ ] **Step 1: Load two months**

In `MonthViewModel.load()`, the window ends seven days after the end of the month. Change the `endOfMonth` line so it ends after the following month:

```swift
              let endOfMonth = calendar.date(byAdding: .month, value: 2, to: startOfMonth),
```

and add the comment above the `guard`:

```swift
        // Two months, not one: the screen shows this month and the next, the
        // way the reference stacks October over November.
```

- [ ] **Step 2: Rewrite `MonthScreen`**

Replace the whole file body after the imports with:

```swift
/// Two months on hairlines: this one and the next. Past days are hatched,
/// today is the accent, a dot marks a day with events, and a tap pushes the
/// week's schedule at that day.
struct MonthScreen: View {
    @State private var model = MonthViewModel()
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var showDatePicker = false
    @State private var openDay: ScheduleDay?

    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }
    var isCalendarConnected = true
    var onConnectCalendar: () -> Void = {}

    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }

    /// A pushed day. `Date` is not `Identifiable`, and the push needs one.
    struct ScheduleDay: Identifiable, Hashable {
        let date: Date
        var id: Date { date }
    }

    private var months: [Date] {
        [model.month, calendar.date(byAdding: .month, value: 1, to: model.month) ?? model.month]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x4) {
                header
                if !isCalendarConnected { connectCard }
                ForEach(months, id: \.self) { month in
                    monthBlock(month)
                }
                Button("Go back") { dismiss() }
                    .buttonStyle(.editorial(.secondary, fullWidth: true))
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.step(value.translation.width < 0 ? 1 : -1)
                        }
                    }
            )
        }
        .background(paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { model.goToToday() }
                    .disabled(calendar.isDate(model.month, equalTo: .now, toGranularity: .month))
            }
        }
        .navigationDestination(item: $openDay) { day in
            DayScheduleScreen(model: model, day: day.date, onTapEvent: onTapEvent, onAddEvent: onAddEvent)
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Go to date", selection: Binding(get: { model.selection }, set: {
                    model.goTo($0)
                    showDatePicker = false
                }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Go to date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                } }
            }
            .presentationDetents([.medium, .large])
        }
        .task { model.attach(context) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.load()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: "Monthly · \(model.month.formatted(.dateTime.year()))", title: "Calendar")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            stepButton("chevron.left", months: -1, label: "Previous month")
            stepButton("chevron.right", months: 1, label: "Next month")
        }
    }

    private func stepButton(_ icon: String, months: Int, label: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { model.step(months) }
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
        .accessibilityLabel(label)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Connect your calendar to see and manage your events here.")
                .font(LifeOSType.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect calendar", action: onConnectCalendar)
                .buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    private func monthBlock(_ month: Date) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Editorial.headline(34)).tracking(-1)
                .foregroundStyle(isCurrent ? LifeOSTokens.accent : ink)
                .accessibilityAddTraits(.isHeader)
            WeekdayHeader(calendar: calendar, today: month, spacing: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(MonthGridLayout.cells(monthContaining: month, calendar: calendar, today: .now, status: { _ in .noData })) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let state = MonthDayState.of(date, calendar: calendar)
        let count = model.events(on: date).count
        return Button {
            openDay = ScheduleDay(date: date)
        } label: {
            ZStack {
                if state == .today { Rectangle().fill(LifeOSTokens.accent) }
                if state == .past {
                    HatchedCell().stroke(LifeOSTokens.accent, lineWidth: 1).opacity(0.55)
                }
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(state == .today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(state == .today ? paper : ink)
                    Circle()
                        .fill(state == .today ? paper : ink)
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
        .accessibilityAddTraits(state == .today ? [.isSelected] : [])
    }
}
```

The old `calendarPanel`, `grid`, `agenda`, `primary`/`secondary` and the selected-day panel are gone with this. `CalendarEventRow` stays in its own file (the assistant uses it).

- [ ] **Step 3: Build** (after Task 6's file exists)

Expected: zero errors. `grep -c '\.title2\|\.subheadline\|\.headline' LIfeOS/Features/Today/View/MonthScreen.swift` prints `0`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/MonthScreen.swift LIfeOS/Features/Today/ViewModel/MonthViewModel.swift
git commit -m "feat(today): the month screen as two hairline grids with hatched past days"
```

---

### Task 6: `DayScheduleScreen`

**Files:**
- Create: `LIfeOS/Features/Today/View/DayScheduleScreen.swift`

**Interfaces:**
- Consumes: `WeekSpan.days(containing:calendar:)`, `MonthDayState`, `MonthViewModel.events(on:)`, `CalendarEventSnapshot.timeLabel/spanLabel`.
- Produces: `DayScheduleScreen(model:day:onTapEvent:onAddEvent:)`, pushed by Task 5.

- [ ] **Step 1: Write the screen**

```swift
import SwiftUI
import DesignSystem
import Persistence

/// The week around a day, as stacked bands: the day's number large, its
/// events beside it. The chosen day opens with its rows and an Add button;
/// the others show their number and a count until tapped.
struct DayScheduleScreen: View {
    let model: MonthViewModel
    let day: Date
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    @State private var expanded: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private let calendar = Calendar.current

    init(model: MonthViewModel, day: Date,
         onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
         onAddEvent: @escaping (Date) -> Void = { _ in }) {
        self.model = model
        self.day = day
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        _expanded = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var week: [Date] { WeekSpan.days(containing: day, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialMasthead(eyebrow: "Weekly · \(day.formatted(.dateTime.month(.wide)))",
                                  title: weekTitle)
                    .padding(.bottom, Space.x2)
                ForEach(week, id: \.self) { date in
                    band(date)
                    Hairline()
                }
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekTitle: String {
        guard let first = week.first, let last = week.last else { return "" }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.formatted(style)) to \(last.formatted(style))"
    }

    private func events(on date: Date) -> [CalendarEventSnapshot] {
        model.events(on: date).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
    }

    private func numberInk(_ date: Date) -> Color {
        switch MonthDayState.of(date, calendar: calendar) {
        case .today: LifeOSTokens.accent
        case .past: quiet
        case .future: ink
        }
    }

    private func band(_ date: Date) -> some View {
        let rows = events(on: date)
        let isOpen = calendar.isDate(date, inSameDayAs: expanded)
        return HStack(alignment: .top, spacing: Space.x2) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { expanded = calendar.startOfDay(for: date) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(date.formatted(.dateTime.day()))
                        .font(Editorial.figure(64)).tracking(Editorial.figureTracking(64))
                        .monospacedDigit()
                        .foregroundStyle(numberInk(date))
                    Text(date.formatted(.dateTime.weekday(.wide))).editorialEyebrow()
                }
                .frame(width: 96, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day())), \(rows.count) events")
            .accessibilityHint(isOpen ? "Showing its events" : "Shows its events")

            VStack(alignment: .leading, spacing: Space.x1) {
                if isOpen {
                    if rows.isEmpty {
                        Text("Nothing scheduled").font(LifeOSType.secondary).foregroundStyle(quiet)
                            .padding(.top, Space.x2)
                    }
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
                    Button("Add") { onAddEvent(date) }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                        .padding(.top, Space.x1)
                } else if !rows.isEmpty {
                    EditorialTag(rows.count == 1 ? "1 event" : "\(rows.count) events")
                        .padding(.top, Space.x2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.x2)
    }
}
```

- [ ] **Step 2: Build** (with Task 5)

Run the app build. Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Today/View/DayScheduleScreen.swift
git commit -m "feat(today): the week as stacked day bands with their events"
```

---

### Task 7: `NotesHeadline` and the Notes shelf

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/NotesHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift`
- Modify: `LIfeOS/Features/Notes/View/NoteShelfScreen.swift`
- Modify: `LIfeOS/Features/Notes/View/NoteCard.swift`

**Interfaces:**
- Produces: `NotesHeadline.eyebrow(count:) -> String` ("Notes · No pages", "Notes · 1 page", "Notes · 24 pages"; `editorialEyebrow()` uppercases it).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import DesignSystem

@Suite struct NotesHeadlineTests {
    @Test func countWording() {
        #expect(NotesHeadline.eyebrow(count: 0) == "Notes · No pages")
        #expect(NotesHeadline.eyebrow(count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(count: 24) == "Notes · 24 pages")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd LifeOSKit && swift test --filter NotesHeadlineTests`
Expected: `cannot find 'NotesHeadline' in scope`.

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/DesignSystem/NotesHeadline.swift
/// The Notes masthead eyebrow, so "1 pages" never ships.
public enum NotesHeadline {
    public static func eyebrow(count: Int) -> String {
        switch count {
        case 0: "Notes · No pages"
        case 1: "Notes · 1 page"
        default: "Notes · \(count) pages"
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes, then commit**

Run: `cd LifeOSKit && swift test --filter NotesHeadlineTests` → `1 test ... passed`.

```bash
git add LifeOSKit/Sources/DesignSystem/NotesHeadline.swift LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift
git commit -m "feat(design): the Notes eyebrow wording"
```

- [ ] **Step 5: Rewrite the shelf's body**

In `NoteShelfScreen.swift`, replace the `ScrollView`'s inner `VStack(alignment: .leading, spacing: 20) { ... }` with:

```swift
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .top, spacing: Space.x2) {
                    if let onToggleLibrary {
                        Button(action: onToggleLibrary) {
                            Image(systemName: "sidebar.leading")
                        }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                        .accessibilityLabel(isLibraryVisible ? "Hide library" : "Show library")
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                    EditorialMasthead(eyebrow: NotesHeadline.eyebrow(count: model.cards.count),
                                      title: model.headerTitle)
                    creationMenu
                }

                searchField

                EditorialSectionHeader(title: "Pages") {
                    HStack(spacing: Space.x1) {
                        if model.selection.bucket != nil || model.selection.folderID != nil {
                            Menu {
                                Picker("Page type", selection: $model.filter) {
                                    ForEach(NoteShelfFilter.allCases) { filter in
                                        Label(filter.title, systemImage: filter.systemImage).tag(filter)
                                    }
                                }
                            } label: {
                                Text(model.filter.title)
                            }
                            .buttonStyle(.editorial(.quiet, size: .compact))
                            .accessibilityLabel("Filter pages")
                        }
                        Menu {
                            Picker("Sort pages", selection: $model.sort) {
                                ForEach(NoteSort.allCases) { sort in
                                    Label(sort.title, systemImage: sort.systemImage).tag(sort)
                                }
                            }
                        } label: {
                            Text(model.sort.title)
                        }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                        .accessibilityLabel("Sort: \(model.sort.title)")
                    }
                }

                if model.cards.isEmpty {
                    if model.isSearching {
                        VStack(alignment: .leading, spacing: Space.x2) {
                            Text("No matching pages").font(LifeOSType.rowTitle)
                            Text("Try another title or a word from your notes.")
                                .font(LifeOSType.secondary).foregroundStyle(secondary)
                            Button("Clear search") { model.query = "" }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                        }
                        .editorialCard()
                    } else {
                        EditorialEmptyState(
                            sentence: "Pages, journals and task lists, all in one place.",
                            action: "Create a page",
                            onAction: { open(model.createNote()) }
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                EditorialRow("Monday journal", value: "Today")
                                EditorialRow("Groceries", value: "3 of 8")
                                EditorialRow("Ideas for the trip", value: "Yesterday")
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.cards) { card in
                            NoteCard(card: card, isOpen: card.id == openPageID,
                                onOpen: { onOpen(card.id) },
                                onFavorite: { model.toggleFavorite(card.id) },
                                onArchive: { model.toggleArchive(card.id) },
                                onDelete: { model.delete(card.id) },
                                moveTargets: moveTargets,
                                onMove: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) })
                            Hairline()
                        }
                    }
                }

                Spacer(minLength: layout.contentBottomInset)
            }
```

Replace `searchField` and `creationMenu` with:

```swift
    private var searchField: some View {
        VStack(spacing: Space.half) {
            HStack(spacing: Space.x1) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                TextField("Search all pages", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused).submitLabel(.search)
                    .autocorrectionDisabled()
                    .font(LifeOSType.body)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    private var creationMenu: some View {
        Menu {
            Button("Blank page", systemImage: "doc") { open(model.createNote(kind: .note)) }
            Button("Today's journal", systemImage: "book.closed") { open(model.openTodaysJournal()) }
            Button("Task list", systemImage: "checklist") { open(model.createNote(kind: .task)) }
            Divider()
            Button("New folder", systemImage: "folder.badge.plus") { onNewFolder(model.activeBucket) }
        } label: {
            Text("New page")
        }
        .buttonStyle(.editorial(.primary, size: .compact))
        .accessibilityLabel("Create a page or folder")
    }
```

Change the outer `.padding(.horizontal, layout.isRegular ? 24 : 20)` to `.padding(.horizontal, layout.gutter)` and `.padding(.top, 16)` to `.padding(.top, Space.x2)`. Remove `.tint(LifeOSTokens.accent)` (the asset carries it).

- [ ] **Step 6: Bring `NoteCard` onto the scale**

In `NoteCard.swift`'s label: `.font(.title3)` → `.font(LifeOSType.sectionTitle)`; the icon's `.foregroundStyle(LifeOSTokens.accent)` → `.foregroundStyle(ink)`; `.font(.body.weight(.semibold))` → `.font(LifeOSType.rowTitle)`; the star's `.font(.caption)` → `.font(LifeOSType.caption)` and its colour → `ink`; the excerpt `.font(.subheadline)` → `.font(LifeOSType.secondary)`; the meta row `.font(.caption)` → `.font(LifeOSType.caption)`; `.padding(16)` → `.padding(.vertical, Space.x2)`; the open background `LifeOSTokens.accent.opacity(0.09)` → `LifeOSTokens.cardSurface.resolve(scheme)`. After `Spacer(minLength: 0)` add:

```swift
                Image(systemName: "arrow.right")
                    .font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(Editorial.quietInk(scheme))
                    .padding(.top, Space.half)
                    .accessibilityHidden(true)
```

- [ ] **Step 7: Build**

Expected: zero errors. `grep -cE '\.largeTitle|\.subheadline|\.title3|\.caption\)|\.body\.weight' LIfeOS/Features/Notes/View/NoteShelfScreen.swift LIfeOS/Features/Notes/View/NoteCard.swift` prints `0` for both.

- [ ] **Step 8: Commit**

```bash
git add LIfeOS/Features/Notes/View/NoteShelfScreen.swift LIfeOS/Features/Notes/View/NoteCard.swift
git commit -m "feat(notes): masthead, hairline search, numbered pages and a teaching state"
```

---

### Task 8: The day sheet on rows

**Files:**
- Modify: `LIfeOS/Features/Today/View/DayDetailSheet.swift`
- Modify: `LIfeOS/Features/Today/View/AgendaCard.swift` (delete `EventJourneyRow` if Task 4 left it)

- [ ] **Step 1: Rewrite the sheet's content**

Replace the `ScrollView`'s inner `VStack` and the `schedule`, `metrics`, `habits` members with:

```swift
                VStack(alignment: .leading, spacing: Space.x3) {
                    EditorialMasthead(
                        eyebrow: snapshot.isToday ? "Today" : "Day",
                        title: snapshot.date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        detail: habitsLine
                    )
                    ForEach(Array(sections.enumerated()), id: \.element) { offset, section in
                        VStack(alignment: .leading, spacing: Space.x2) {
                            EditorialSectionHeader(index: offset + 1, title: section.title)
                            content(section)
                        }
                    }
                }
                .padding(.horizontal, Space.x3)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x5)
```

```swift
    private enum Section: Hashable {
        case schedule, readings, habits
        var title: String {
            switch self {
            case .schedule: "Schedule"
            case .readings: "Readings"
            case .habits: "Habits"
            }
        }
    }

    private var sections: [Section] {
        var list: [Section] = []
        if !snapshot.events.isEmpty { list.append(.schedule) }
        list.append(.readings)
        list.append(.habits)
        return list
    }

    private var habitsLine: String? {
        guard !snapshot.habits.isEmpty else { return nil }
        let done = snapshot.habits.filter(\.isDone).count
        return "\(done) of \(snapshot.habits.count) \(snapshot.habits.count == 1 ? "habit" : "habits")"
    }

    @ViewBuilder
    private func content(_ section: Section) -> some View {
        switch section {
        case .schedule:
            ForEach(snapshot.events) { event in
                EditorialRow(event.timeLabel, value: event.title)
            }
        case .readings:
            EditorialRow("Steps", value: snapshot.steps.map { "\($0.formatted()) of \(snapshot.stepsTarget.formatted())" } ?? "—")
            EditorialRow("Sleep", value: snapshot.sleepMinutes.map { "\(TodayScreen.duration($0)) of \(TodayScreen.duration(snapshot.sleepTargetMinutes))" } ?? "—")
            EditorialRow("Weight", value: snapshot.weightKg.map { String(format: "%.1f kg", $0) } ?? "—")
            EditorialRow("Recovery", value: snapshot.recoveryPct.map { "\(Int($0))%" } ?? "—")
        case .habits:
            if snapshot.habits.isEmpty {
                Text("No habits yet. Add one on the Notes tab.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(Editorial.quietInk(scheme))
            } else {
                ForEach(snapshot.habits) { habit in
                    habitRow(habit)
                }
            }
        }
    }
```

Keep `habitRow` and `habitLabel` but change `habitLabel` to a hairline row:

```swift
    private func habitLabel(_ habit: HabitRow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.x2) {
                Image(systemName: habit.isDone ? "checkmark.square.fill" : "square")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(habit.isDone ? LifeOSTokens.primaryText.resolve(scheme) : Editorial.quietInk(scheme))
                Text(habit.title)
                    .font(LifeOSType.secondary)
                    .strikethrough(habit.isDone)
                    .foregroundStyle(habit.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            Hairline()
        }
        .contentShape(.rect)
    }
```

Delete the old `icon(for:)` helper, `MetricRow` and any `SoftCard` use in this file. Keep the `Done` toolbar item and the inline title but set `.navigationTitle("")` (the masthead carries the date).

- [ ] **Step 2: Delete `EventJourneyRow` and `DayPart.hue`** if still present (`grep -rn 'EventJourneyRow\|DayPart.hue' LIfeOS` must print nothing after this step; if a caller outside Today exists, leave the struct and ledger it).

- [ ] **Step 3: Build**

Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/DayDetailSheet.swift LIfeOS/Features/Today/View/AgendaCard.swift
git commit -m "feat(today): the day sheet as a masthead and numbered rows"
```

---

### Task 9: Preview pages and the screenshot review

**Files:**
- Create: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` (page routing, one line)

- [ ] **Step 1: Write the preview and its fixture**

```swift
#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Fixture pages for Today, the month screen, the schedule, the day sheet
/// and Notes, mounted by `--design-preview` with `--page=today`,
/// `today-empty`, `month`, `schedule`, `day`, `notes` or `notes-empty`.
struct TodayDesignPreview: View {
    let page: String
    @State private var fixture = TodayFixture()

    var body: some View {
        Group {
            switch page {
            case "today-empty":
                NavigationStack { TodayScreen(snapshot: fixture.emptySnapshot, onSelectDay: { _ in }, onConnectCalendar: {}, onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {}).shellToolbar() }
            case "month":
                NavigationStack { MonthScreen() }.modelContainer(fixture.container)
            case "schedule":
                NavigationStack { DayScheduleScreen(model: fixture.month, day: .now) }.modelContainer(fixture.container)
            case "day":
                DayDetailSheet(snapshot: fixture.day, onToggleHabit: { _ in })
            case "notes":
                NavigationStack { NoteShelfScreen(model: fixture.notes, onOpen: { _ in }, onNewFolder: { _ in }).shellToolbar() }
                    .modelContainer(fixture.container)
            case "notes-empty":
                NavigationStack { NoteShelfScreen(model: fixture.emptyNotes, onOpen: { _ in }, onNewFolder: { _ in }).shellToolbar() }
                    .modelContainer(fixture.emptyContainer)
            default:
                NavigationStack {
                    TodayScreen(snapshot: fixture.snapshot, onSelectDay: { _ in }, onConnectCalendar: {}, onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {}, isHealthConnected: true)
                        .shellToolbar()
                }
            }
        }
        .environment(\.quickActions, LifeDesignPreview.actions)
        .environment(\.shellProfile, ShellProfile(photo: nil, open: {}))
    }
}

@MainActor private final class TodayFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let emptyContainer = try! LifeOSContainer.make(inMemory: true)
    let month = MonthViewModel()
    let notes = NotesViewModel()
    let emptyNotes = NotesViewModel()
    let calendar = Calendar.current
    let events: [CalendarEventSnapshot]

    init() {
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minutes: Int, _ title: String) -> CalendarEventSnapshot {
            let start = calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: dayOffset, to: today)!)!
            return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Work", title: title,
                                         startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
                                         isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        events = [
            at(0, 9, 30, "Standup"), at(0, 12, 60, "Lunch with Sam"), at(0, 16, 90, "Design review"),
            at(1, 10, 60, "Dentist"), at(2, 19, 120, "Dinner with Alice"), at(3, 8, 60, "Programming class"),
            at(6, 19, 180, "Professional party"), at(-2, 9, 30, "Standup"), at(14, 9, 60, "Flight to Lisbon"),
        ]
        let window = DateInterval(start: calendar.date(byAdding: .day, value: -40, to: today)!,
                                  end: calendar.date(byAdding: .day, value: 70, to: today)!)
        try! CalendarStore(context: container.mainContext, calendar: calendar).apply(events, window: window)
        month.attach(container.mainContext)
        month.load()
        notes.attach(container.mainContext)
        _ = notes.createNote(kind: .note, title: "Marathon block, week four")
        _ = notes.createNote(kind: .task, title: "Groceries")
        _ = notes.openTodaysJournal()
        notes.load()
        emptyNotes.attach(emptyContainer.mainContext)
        emptyNotes.load()
    }

    var snapshot: TodaySnapshot {
        var s = TodaySnapshot()
        s.cells = (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) }
        s.streak = 6; s.steps = 8_432; s.sleepMinutes = 432; s.weightKg = 77.4; s.recoveryPct = 82
        s.calendarAccess = .authorized
        s.agenda = events.filter { calendar.isDateInToday($0.startDate) }
        s.upcoming = events.filter { $0.startDate > calendar.date(byAdding: .day, value: 1, to: today)! }
            .prefix(3).map { UpcomingEvent(event: $0, dayLabel: $0.startDate.formatted(.dateTime.weekday(.wide))) }
        s.scheduledWorkoutTitle = "Lower body, 35 min"
        return s
    }

    private var today: Date { calendar.startOfDay(for: .now) }

    var emptySnapshot: TodaySnapshot {
        var s = TodaySnapshot()
        s.cells = (0..<35).map { DotCell(id: $0, date: nil, state: $0 == 10 ? .today : .future) }
        s.calendarAccess = .notDetermined
        return s
    }

    var day: DayDetailSnapshot {
        DayDetailSnapshot(date: today, isToday: true, steps: 8_432, stepsTarget: 10_000, sleepMinutes: 432,
                          sleepTargetMinutes: 480, weightKg: 77.4, recoveryPct: 82,
                          habits: [HabitRow(id: UUID(), title: "5km run", isDone: true),
                                   HabitRow(id: UUID(), title: "Read 10 pages", isDone: false),
                                   HabitRow(id: UUID(), title: "Walk the dog", isDone: false)],
                          events: events.filter { calendar.isDateInToday($0.startDate) })
    }
}
#endif
```

Check the exact member names against `TodaySnapshot.swift` and `UpcomingEvent` (`event`, `dayLabel`) before building; the `TodayScreen` `#Preview` at the foot of `TodayScreen.swift` shows the initialiser forms that compile. `NotesViewModel.attach(_:sync:)` takes an optional sync; pass only the context.

- [ ] **Step 2: Route the pages**

In `HealthActivityDesignPreview.swift`, after the `life`/`shell` line:

```swift
            else if ["today", "today-empty", "month", "schedule", "day", "notes", "notes-empty"].contains(page) { TodayDesignPreview(page: page) }
```

- [ ] **Step 3: Build, install, capture light and dark**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q editorial-today-notes "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4
xcrun simctl install $SIM "$APP"
for page in today today-empty month schedule day notes notes-empty; do
  for mode in "" "--dark"; do
    xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
    xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview --page=$page $mode >/dev/null
    perl -e 'select(undef,undef,undef,4)'
    xcrun simctl io $SIM screenshot "/private/tmp/claude-501/-Users-shivvyas-LIfeOS/540be88d-a1c8-4704-b181-241ac1f7aebf/scratchpad/pr2-$page$mode.png" >/dev/null
  done
done
```

Check each against the spec:
- `today`: masthead `TODAY · <weekday, Mon d>` / `Good <part>` / `6-day streak`; the dusk agenda field with `NEXT UP`, the next event's title large, rows with arrows, an outlined `Add`; the dot grid unchanged; the scheduled workout row; four ink tiles with eyebrows, light figures, ink bars and the arrow.
- `today-empty`: the teaching field (ghost rows, `Connect calendar`), the health card above ghosted tiles at 35%.
- `month`: `MONTHLY · <year>` / `Calendar`; this month's name in the accent, next month's in ink; hairline grid; hatched past days; today an accent cell; dots on event days; `Go back` outlined at the foot.
- `schedule`: `WEEKLY · <Month>`; seven bands; today's number in the accent, past numbers quiet; the chosen day's rows and `Add`; other days with a count tag.
- `day`: masthead with the date and `1 of 3 habits`; `01 Schedule`, `02 Readings`, `03 Habits` with checkbox rows.
- `notes`: `NOTES · 3 PAGES` / `Projects`; the ink `New page` capsule; the hairline search; `Pages` header with filter and sort as text; rows with arrows and hairlines.
- `notes-empty`: the ghost rows and `Create a page`.
- Dark variants: no light boxes, legible ink, the dusk field's ink near white.

Fix anything off and repeat.

- [ ] **Step 4: Gates**

```bash
cd LifeOSKit && swift test && cd .. && scripts/check-typography.sh > /tmp/typo-pr2.txt 2>&1; diff <(sed 's/^[^:]*://' /tmp/typo-main.txt | sort) <(sed 's/^[^:]*://' /tmp/typo-pr2.txt | sort) | grep '^>' || echo "typography: no new violations"
```

(`/tmp/typo-main.txt` is the guard's output on `origin/main`; regenerate it from the main checkout if missing.)

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Today/View/TodayDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(today): design-preview pages for Today, the month, the schedule, the day and Notes"
```

---

### Task 10: Open the pull request

- [ ] **Step 1: Rebase and push**

```bash
git fetch origin
# If PR #19 has merged, rebase onto main; otherwise stay on top of feat/editorial-shell-life.
git merge-base --is-ancestor origin/feat/editorial-shell-life origin/main 2>/dev/null && git rebase origin/main || git rebase origin/feat/editorial-shell-life
git push -u origin feat/editorial-today-notes
```

- [ ] **Step 2: Open the PR** (base `main` if #19 merged, else `feat/editorial-shell-life`; no attribution footer)

```bash
gh pr create --base <base> --head feat/editorial-today-notes \
  --title "feat(today): Today, Notes, the month screen and the day schedule on the editorial theme" \
  --body "$(cat <<'EOF'
## Summary

- Today: a masthead with the day, a greeting and the streak; the agenda as the screen's one dusk field with the next event first; ink metric tiles; a teaching empty state when the calendar is not connected, with ghosted tiles while Health is not.
- Month screen: this month and the next on hairline grids, past days hatched in the accent, today an accent cell, a dot on days with events, and a tap that pushes the week's schedule.
- Day schedule: seven stacked bands, the day's number large, its events as rows with an Add button on the chosen day.
- Day sheet from the dot grid: masthead and numbered rows for schedule, readings and habits.
- Notes: masthead, an ink New page capsule, hairline search, a Pages header with filter and sort, hairline rows with arrows, and a teaching empty state.
- Design system: `TodayHeadline`, `MonthDayState`, `WeekSpan`, `HatchedCell`, `NotesHeadline`, `TrendStatTile` ink style, all tested where there is logic.
- Spec: docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md (PR 2 of 4). Plan: docs/superpowers/plans/2026-10-05-editorial-today-notes.md.

## Verification

- LifeOSKit `swift test`: all suites pass, including the new headline, day-state, week-span, hatch and Notes-eyebrow tests.
- `scripts/check-typography.sh`: no new violations.
- Simulator design-preview pages `today`, `today-empty`, `month`, `schedule`, `day`, `notes`, `notes-empty`, light and dark, reviewed against the spec.
EOF
)"
```

- [ ] **Step 3: Report** the PR link, the screenshot paths, the merge command, and that PR 3 (chat) is next.
