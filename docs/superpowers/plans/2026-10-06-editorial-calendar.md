# Editorial calendar screen with a Monthly | Weekly switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the pushed month screen and week schedule into one `CalendarScreen` with a `Monthly | Weekly` switch, where a tapped day opens its week in place, the chevrons and swipe step a month or a week by mode, and `Today` lives in the editorial header row instead of the system bar.

**Architecture:** The wording that can be wrong lives in a tested value, `CalendarHeadline` in `DesignSystem`, beside `TodayHeadline`. `MonthScreen.swift` is renamed to `CalendarScreen.swift` and gains a `CalendarMode` state, the switch, and a body that is either the existing two month blocks or `WeekBands`, which is `DayScheduleScreen.swift` renamed and stripped of its masthead and scroll view. `MonthViewModel` gains one method, `stepWeek(_:)`. Callers in `RootView`, `AssistantSheet` and the two DEBUG previews move to the new name; the dead `CalendarEventRow.swift` goes.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-06-editorial-calendar-find-ask-widget-design.md`, section 1 and the Monthly/Weekly parts of section 5. PR 1 of the five in section 6. The find-and-ask field (section 2) and the widget (section 3) are later PRs and are not built here.

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. The accent (`LifeOSTokens.accent`) appears only on today's cell, the hatch on past days, this month's name, and today's number on the bands. No new colours.
- No gradient field on this screen. Every button uses `.buttonStyle(.editorial(role))`; no bare system buttons in content. The system bar holds only Back.
- Fonts come only from `LifeOSType` or `Editorial.figure(_:)` / `Editorial.headline(_:)`; `scripts/check-typography.sh` must report nothing new versus the base commit.
- The Today tab (`TodayScreen`, `MonthCalendarView`, `DayDetailSheet`) is not touched.
- The Monthly body is the two month blocks exactly as PR #20 built them; the Weekly body is the bands exactly as PR #20 built them. This PR changes how they are composed and navigated, not how they look.
- `LifeOSKit` also builds for macOS (`swift test` runs there): nothing iOS-only goes into the package.
- `LIfeOS/` is a synchronized folder in the Xcode project: renames and deletions under it need no `project.pbxproj` edit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind.
- Work happens in the existing worktree `.claude/worktrees/editorial-calendar` on branch `feat/editorial-calendar`, cut from `origin/main` at `a4a7698` with the spec committed on top (`fa1525d`). `Config/Secrets.xcconfig` is already copied in.
- The simulator for builds and captures is `Editorial iPhone 17`, id `B16BEDD3-51EB-442D-B84B-81EDDB2DF923` (iOS 26.2). Peer sessions use the other iPhone 17; do not install on it.

## Review Focus

1. The Monthly eyebrow names the year of the shown month, not of today: step from December 2026 into January and it must read `MONTHLY · 2027`. `CalendarHeadlineTests.monthlyNamesTheShownYearNotToday` in Task 1.
2. The Weekly range crosses a month boundary correctly and the eyebrow names the selected day's month: a selection of October 1 reads `WEEKLY · OCTOBER` with `Sep 27 to Oct 3`. `CalendarHeadlineTests.weeklyRangeCrossesMonths` in Task 1.
3. Opening a week in the previous month moves the fetch window with it, so the bands show that month's events: the `schedule --select=2026-09-29` capture in Task 6 must show the 29th open with the fixture's `Dentist follow-up` row, which lives seven days before today.
4. `Today` is disabled exactly when there is nothing to return to: the `month` capture shows it dimmed, the `month --select=2027-01-15` capture shows it live; the `schedule` capture shows it dimmed, `schedule --select=2026-09-29` live. Task 6.
5. A tapped day in Monthly lands on Weekly with that day open, and the date picker keeps the mode. Simulator tap check in Task 6 step 5 (one tap, screenshot after).

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/CalendarHeadline.swift` (new) | `CalendarMode` and the masthead wording by mode |
| `LifeOSKit/Tests/DesignSystemTests/CalendarHeadlineTests.swift` (new) | Its tests |
| `LIfeOS/Features/Today/ViewModel/MonthViewModel.swift` | `stepWeek(_:)` |
| `LIfeOS/Features/Today/View/WeekBands.swift` (renamed from `DayScheduleScreen.swift`) | The seven bands as a body view driven by `model.selection` |
| `LIfeOS/Features/Today/View/CalendarScreen.swift` (renamed from `MonthScreen.swift`) | The screen: header row, switch, the two bodies, navigation |
| `LIfeOS/App/RootView.swift` | Opens `CalendarScreen` from the header button |
| `LIfeOS/Features/Assistant/View/AssistantSheet.swift` | The `Schedule` link opens `CalendarScreen` |
| `LIfeOS/Features/Health/View/CalendarHealthDesignPreview.swift` | Mounts `CalendarScreen` |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift` | `month` and `schedule` pages mount the screen in each mode, `--select=` opens a date |
| `LIfeOS/Features/Today/View/CalendarEventRow.swift` (deleted) | Dead since PR #20 |

---

### Task 0: Worktree and the typography baseline

- [ ] **Step 1: Confirm the worktree**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar
git status --short && git log --oneline -2 && ls Config/Secrets.xcconfig
```

Expected: a clean tree, `fa1525d docs(spec): one calendar screen with find, ask and a widget` over `a4a7698`, and the secrets file present. If the tree is not clean, stop and report what is in it.

- [ ] **Step 2: Record the typography baseline before any change**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar
scripts/check-typography.sh > /tmp/typo-calendar-base.txt 2>&1; echo "baseline lines: $(wc -l < /tmp/typo-calendar-base.txt)"
```

Expected: a line count. The script exits non-zero on existing violations; that is fine, the diff in Task 6 is what matters.

---

### Task 1: `CalendarHeadline`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/CalendarHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/CalendarHeadlineTests.swift`

**Interfaces:**
- Consumes: `WeekSpan.days(containing:calendar:)` from `LifeOSKit/Sources/DesignSystem/MonthDayState.swift`.
- Produces: `public enum CalendarMode: Hashable, Sendable { case monthly, weekly }` and `public struct CalendarHeadline { eyebrow: String; title: String; detail: String?; static func make(mode: CalendarMode, month: Date, selection: Date, calendar: Calendar = .current, locale: Locale = .current) -> CalendarHeadline }`. Task 4 uses both.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct CalendarHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    @Test func monthlyNamesTheShownYearNotToday() {
        let h = CalendarHeadline.make(mode: .monthly, month: date(2027, 1, 15), selection: date(2026, 10, 6),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Monthly · 2027")
        #expect(h.title == "Calendar")
        #expect(h.detail == nil)
    }

    @Test func weeklyFollowsTheSelection() {
        let h = CalendarHeadline.make(mode: .weekly, month: date(2026, 10, 1), selection: date(2026, 10, 6),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Weekly · October")
        #expect(h.title == "Calendar")
        #expect(h.detail == "Oct 4 to Oct 10")
    }

    @Test func weeklyRangeCrossesMonths() {
        let h = CalendarHeadline.make(mode: .weekly, month: date(2026, 10, 1), selection: date(2026, 10, 1),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Weekly · October")
        #expect(h.detail == "Sep 27 to Oct 3")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd LifeOSKit && swift test --filter CalendarHeadlineTests`
Expected: a compile error, `cannot find 'CalendarHeadline' in scope`.

- [ ] **Step 3: Write the value**

```swift
import Foundation

/// Which face the calendar screen shows: two months on grids, or the seven
/// days around the selected day as bands.
public enum CalendarMode: Hashable, Sendable {
    case monthly, weekly
}

/// The calendar screen's masthead by mode. The eyebrow names the mode and
/// the period, the title is always `Calendar`, and Weekly adds the week's
/// range as the detail line. A value so the wording is tested.
public struct CalendarHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String?

    public init(eyebrow: String, title: String, detail: String?) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    /// `month` is any day in the month Monthly shows; `selection` is the
    /// day Weekly is built around. Each mode reads only its own, so the
    /// Monthly year never follows today and the Weekly month never follows
    /// the grid.
    public static func make(
        mode: CalendarMode, month: Date, selection: Date,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> CalendarHeadline {
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        switch mode {
        case .monthly:
            return CalendarHeadline(
                eyebrow: "Monthly · \(month.formatted(style.year()))",
                title: "Calendar",
                detail: nil
            )
        case .weekly:
            let days = WeekSpan.days(containing: selection, calendar: calendar)
            let dayStyle = style.month(.abbreviated).day()
            let range: String? = if let first = days.first, let last = days.last {
                "\(first.formatted(dayStyle)) to \(last.formatted(dayStyle))"
            } else {
                nil
            }
            return CalendarHeadline(
                eyebrow: "Weekly · \(selection.formatted(style.month(.wide)))",
                title: "Calendar",
                detail: range
            )
        }
    }
}
```

The eyebrow is written in sentence case because `editorialEyebrow()` applies `.textCase(.uppercase)` when it draws, the same as `TodayHeadline`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd LifeOSKit && swift test --filter CalendarHeadlineTests`
Expected: `3 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/CalendarHeadline.swift LifeOSKit/Tests/DesignSystemTests/CalendarHeadlineTests.swift
git commit -m "feat(design): the calendar masthead by mode as a tested value

CalendarMode and CalendarHeadline: Monthly names the shown month's year,
Weekly names the selected day's month and carries the week's range."
```

---

### Task 2: `MonthViewModel.stepWeek`

**Files:**
- Modify: `LIfeOS/Features/Today/ViewModel/MonthViewModel.swift` (after `step(_:)`, before `goToToday()`)

**Interfaces:**
- Consumes: the existing `select(_:)`, `month`, `selection`, `load()`.
- Produces: `func stepWeek(_ weeks: Int)`. Task 4 calls it for the chevrons and the swipe in Weekly.

- [ ] **Step 1: Add the method**

Insert after the closing brace of `func step(_ months: Int)`:

```swift
    /// Steps a whole week and carries the selection with it.
    ///
    /// The selection is the anchor here, not the month: a week has no day
    /// number to keep, so the day simply moves by seven. The month follows
    /// the selection so the fetch window and the Monthly grid both land
    /// where the week did, and the reload runs only when the month changed,
    /// because the current window already covers the week either side.
    func stepWeek(_ weeks: Int) {
        guard let moved = calendar.date(byAdding: .day, value: 7 * weeks, to: selection) else { return }
        let monthChanged = !calendar.isDate(moved, equalTo: month, toGranularity: .month)
        select(moved)
        month = moved
        if monthChanged { load() }
    }
```

- [ ] **Step 2: Build the package-free part by compiling the app target**

Run from the worktree root:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet 2>&1 | grep -E "error:|warning: unused" | head -20; echo "build exit ${PIPESTATUS[0]}"
```

Expected: `build exit 0` and no `error:` lines.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Today/ViewModel/MonthViewModel.swift
git commit -m "feat(today): step the month model by a week

The selection moves by seven days and the month follows it; the fetch
reruns only when the month changed."
```

---

### Task 3: `WeekBands`

**Files:**
- Rename: `LIfeOS/Features/Today/View/DayScheduleScreen.swift` to `LIfeOS/Features/Today/View/WeekBands.swift`
- Modify: the renamed file in full

**Interfaces:**
- Consumes: `MonthViewModel.selection`, `MonthViewModel.events(on:)`, `MonthViewModel.select(_:)`; `WeekSpan`, `MonthDayState`, `Editorial`, `EditorialRow`, `EditorialTag`, `Hairline` from `DesignSystem`.
- Produces: `struct WeekBands: View { init(model: MonthViewModel, onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in }, onAddEvent: @escaping (Date) -> Void = { _ in }) }`. Task 4 places it as the Weekly body.

- [ ] **Step 1: Rename the file**

```bash
git mv LIfeOS/Features/Today/View/DayScheduleScreen.swift LIfeOS/Features/Today/View/WeekBands.swift
```

- [ ] **Step 2: Replace the file's contents**

The open band follows `model.selection` instead of a private `expanded` state, the number button calls `model.select`, and the masthead, scroll view, padding and background are gone because the screen owns them.

```swift
import SwiftUI
import DesignSystem
import Persistence

/// The week around the selected day, as stacked bands: the day's number
/// large, its events beside it. The selected day's band is open, with its
/// rows and an Add button; the others show their number and a count until
/// their number is tapped.
///
/// A body view, not a screen: `CalendarScreen` owns the masthead, the mode
/// switch and the scroll, so the bands can sit under them in place of the
/// month grids rather than on a pushed screen of their own.
struct WeekBands: View {
    let model: MonthViewModel
    var onTapEvent: (CalendarEventSnapshot) -> Void = { _ in }
    var onAddEvent: (Date) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var week: [Date] { WeekSpan.days(containing: model.selection, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(week, id: \.self) { date in
                band(date)
                Hairline()
            }
        }
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
        let isOpen = calendar.isDate(date, inSameDayAs: model.selection)
        return HStack(alignment: .top, spacing: Space.x2) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { model.select(date) }
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
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])

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

- [ ] **Step 3: Do not build yet**

`MonthScreen.swift` still constructs `DayScheduleScreen`, so the app does not compile until Task 4 replaces it. Move straight on; Task 4 builds both.

- [ ] **Step 4: Commit**

```bash
git add -A LIfeOS/Features/Today/View/DayScheduleScreen.swift LIfeOS/Features/Today/View/WeekBands.swift
git commit -m "refactor(today): the week schedule as a body view, WeekBands

Renamed from DayScheduleScreen. The open band follows the month model's
selection and the masthead and scroll move to the calendar screen. Does
not build alone; the next commit replaces its last caller."
```

---

### Task 4: `CalendarScreen`

**Files:**
- Rename: `LIfeOS/Features/Today/View/MonthScreen.swift` to `LIfeOS/Features/Today/View/CalendarScreen.swift`
- Modify: the renamed file in full

**Interfaces:**
- Consumes: `CalendarMode`, `CalendarHeadline` (Task 1); `MonthViewModel.stepWeek` (Task 2); `WeekBands` (Task 3); `UnderlinePicker`, `EditorialMasthead`, `WeekdayHeader`, `MonthGridLayout`, `MonthDayState`, `HatchedCell`, `WeekSpan` from `DesignSystem`.
- Produces: `struct CalendarScreen: View { init(initialMode: CalendarMode = .monthly, initialSelection: Date? = nil, onTapEvent: ..., onAddEvent: ..., isCalendarConnected: Bool = true, onConnectCalendar: ...) }`. Task 5 moves every caller onto it.

- [ ] **Step 1: Rename the file**

```bash
git mv LIfeOS/Features/Today/View/MonthScreen.swift LIfeOS/Features/Today/View/CalendarScreen.swift
```

- [ ] **Step 2: Replace the file's contents**

What changes against `MonthScreen`: the mode state and the switch; the header gains `Today` and loses the system toolbar item; the body is either the month blocks or `WeekBands`; a day tap selects and switches instead of pushing; `openDay`, `ScheduleDay` and the `navigationDestination` go; the swipe and chevrons step by mode. The month block, the day cell, the connect card and the date picker sheet are kept as they were.

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// The calendar behind the header's calendar button: one screen, two faces.
///
/// Monthly is this month and the next on hairline grids, past days hatched,
/// today in the accent, a dot on days with events. Weekly is the seven days
/// around the selected day as stacked bands. The switch moves between them
/// in place, and a tapped day in Monthly opens its week; nothing is pushed,
/// so the way back is always the one Back button.
struct CalendarScreen: View {
    @State private var model = MonthViewModel()
    @State private var mode: CalendarMode
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var showDatePicker = false

    /// A day to open on instead of today. For previews and deep links; the
    /// header button passes nothing.
    private let initialSelection: Date?
    var onTapEvent: (CalendarEventSnapshot) -> Void
    var onAddEvent: (Date) -> Void
    var isCalendarConnected: Bool
    var onConnectCalendar: () -> Void

    init(
        initialMode: CalendarMode = .monthly,
        initialSelection: Date? = nil,
        onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
        onAddEvent: @escaping (Date) -> Void = { _ in },
        isCalendarConnected: Bool = true,
        onConnectCalendar: @escaping () -> Void = {}
    ) {
        _mode = State(initialValue: initialMode)
        self.initialSelection = initialSelection
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
        self.isCalendarConnected = isCalendarConnected
        self.onConnectCalendar = onConnectCalendar
    }

    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }

    private var months: [Date] {
        [model.month, calendar.date(byAdding: .month, value: 1, to: model.month) ?? model.month]
    }

    private var headline: CalendarHeadline {
        CalendarHeadline.make(mode: mode, month: model.month, selection: model.selection, calendar: calendar)
    }

    /// Nothing to go back to: the shown month is this month, or the shown
    /// week holds today.
    private var isOnToday: Bool {
        switch mode {
        case .monthly:
            calendar.isDate(model.month, equalTo: .now, toGranularity: .month)
        case .weekly:
            WeekSpan.days(containing: model.selection, calendar: calendar).contains { calendar.isDateInToday($0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                header
                UnderlinePicker(
                    selection: $mode.animation(.snappy(duration: 0.22)),
                    options: [(.monthly, "Monthly"), (.weekly, "Weekly")]
                )
                if !isCalendarConnected { connectCard }
                switch mode {
                case .monthly:
                    VStack(alignment: .leading, spacing: Space.x4) {
                        ForEach(months, id: \.self) { month in
                            monthBlock(month)
                        }
                    }
                case .weekly:
                    WeekBands(model: model, onTapEvent: onTapEvent, onAddEvent: onAddEvent)
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
                        step(value.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .background(paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            model.attach(context)
            if let initialSelection { model.goTo(initialSelection) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.load()
        }
    }

    /// One step in whichever unit the mode shows: a month on the grids, a
    /// week on the bands.
    private func step(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            switch mode {
            case .monthly: model.step(direction)
            case .weekly: model.stepWeek(direction)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            Button("Today") {
                withAnimation(.easeOut(duration: 0.18)) { model.goToToday() }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .disabled(isOnToday)
            .accessibilityHint(mode == .monthly ? "Shows this month" : "Shows this week")
            stepButton("chevron.left", direction: -1, label: mode == .monthly ? "Previous month" : "Previous week")
            stepButton("chevron.right", direction: 1, label: mode == .monthly ? "Next month" : "Next week")
        }
    }

    private func stepButton(_ icon: String, direction: Int, label: String) -> some View {
        Button { step(direction) } label: {
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
            WeekdayHeader(calendar: calendar, today: isCurrent ? .now : nil, spacing: 0)
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

    /// A tap selects the day and turns the screen to its week. Nothing is
    /// pushed: the week appears under the same masthead, with this day's
    /// band open.
    private func dayCell(_ date: Date) -> some View {
        let state = MonthDayState.of(date, calendar: calendar)
        let count = model.events(on: date).count
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
        .accessibilityHint("Shows its week")
        .accessibilityAddTraits(state == .today ? [.isSelected] : [])
    }
}
```

- [ ] **Step 3: Build**

The build fails here only because `RootView`, `AssistantSheet` and the two previews still name `MonthScreen` and `DayScheduleScreen`. Run it anyway to confirm those are the only errors:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet 2>&1 | grep "error:" | head -20
```

Expected: errors only of the form `cannot find 'MonthScreen' in scope` or `cannot find 'DayScheduleScreen' in scope`, in `RootView.swift`, `AssistantSheet.swift`, `CalendarHealthDesignPreview.swift` and `TodayDesignPreview.swift`. Any other error is a mistake in this file; fix it before moving on.

- [ ] **Step 4: Commit**

```bash
git add -A LIfeOS/Features/Today/View/MonthScreen.swift LIfeOS/Features/Today/View/CalendarScreen.swift
git commit -m "feat(calendar): one calendar screen with a Monthly | Weekly switch

Renamed from MonthScreen. The week is a mode of this screen rather than a
pushed one: a tapped day opens its week in place, the chevrons and the
swipe step a month or a week by mode, and Today sits in the header row as
an editorial button instead of a system bar item. Callers follow in the
next commit."
```

---

### Task 5: Callers, previews and the dead row

**Files:**
- Modify: `LIfeOS/App/RootView.swift:427-434`
- Modify: `LIfeOS/Features/Assistant/View/AssistantSheet.swift:56-62`
- Modify: `LIfeOS/Features/Health/View/CalendarHealthDesignPreview.swift:23`
- Modify: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`
- Delete: `LIfeOS/Features/Today/View/CalendarEventRow.swift`

**Interfaces:**
- Consumes: `CalendarScreen(initialMode:initialSelection:onTapEvent:onAddEvent:isCalendarConnected:onConnectCalendar:)` from Task 4.
- Produces: the DEBUG pages `month` and `schedule` now mount `CalendarScreen` in each mode and honour `--select=YYYY-MM-DD`. Task 6 captures them.

- [ ] **Step 1: RootView**

In `RootView.swift`, inside `.navigationDestination(isPresented: $showMonth)`, change `MonthScreen(` to `CalendarScreen(`. The four arguments stay as they are:

```swift
                    .navigationDestination(isPresented: $showMonth) {
                        CalendarScreen(
                            onTapEvent: { eventSheet = .edit($0) },
                            onAddEvent: { eventSheet = .create(on: $0) },
                            isCalendarConnected: today.snapshot.calendarAccess == .authorized,
                            onConnectCalendar: { requestCalendarAccess() }
                        )
                    }
```

- [ ] **Step 2: AssistantSheet**

In the `topBarLeading` `NavigationLink`, change `MonthScreen(onTapEvent:` to `CalendarScreen(onTapEvent:`; the rest of the call is unchanged:

```swift
                    NavigationLink {
                        CalendarScreen(onTapEvent: { eventSheet = .edit($0) },
                                       onAddEvent: { eventSheet = .create(on: $0) },
                                       isCalendarConnected: model.isAuthorized,
                                       onConnectCalendar: { Task { await model.connectCalendar() } })
                    } label: { Label("Schedule", systemImage: "calendar") }
```

- [ ] **Step 3: CalendarHealthDesignPreview**

Line 23: `MonthScreen()` becomes `CalendarScreen()`.

- [ ] **Step 4: TodayDesignPreview**

Replace the `month` and `schedule` cases, add the `--select=` reader, and drop the fixture's now-unused `month` model. The header comment gains the new argument.

The two cases:

```swift
            case "month":
                NavigationStack { CalendarScreen(initialSelection: selected) }.modelContainer(fixture.container)
            case "schedule":
                NavigationStack { CalendarScreen(initialMode: .weekly, initialSelection: selected) }.modelContainer(fixture.container)
```

The reader, as a private computed property on `TodayDesignPreview` next to `page`:

```swift
    /// `--select=2026-09-29` opens the calendar pages on that day, so a week
    /// that straddles two months or a month in another year can be captured
    /// without a tap.
    private var selected: Date? {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--select=") })?.dropFirst(9) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter.date(from: String(raw))
    }
```

In `TodayFixture`, delete the line `let month = MonthViewModel()` and the two lines `month.attach(container.mainContext)` and `month.load()` in `init()`. Nothing else in the fixture referenced them.

Add one event a week back so the Weekly capture of the previous week has something to show, and the Monthly grid has a hatched past day with a dot. In the `events = [` list, after `at(-2, 9, 30, "Standup")`, add:

```swift
            at(-7, 11, 60, "Dentist follow-up"),
```

Update the doc comment at the top of the file so it reads:

```swift
/// Fixture pages for Today, the calendar screen, the day sheet and Notes,
/// mounted by `--design-preview` with `--page=today`, `today-empty`,
/// `today-done`, `month` (the calendar in Monthly), `schedule` (the calendar
/// in Weekly), `day`, `day-past`, `notes` or `notes-empty`. `--select=` opens
/// the calendar pages on a given day.
```

- [ ] **Step 5: Delete the dead row**

```bash
grep -rn "CalendarEventRow\|EventJourneyRow" --include='*.swift' LIfeOS | grep -v "Features/Today/View/CalendarEventRow.swift"
```

Expected: no output. Then:

```bash
git rm -q LIfeOS/Features/Today/View/CalendarEventRow.swift
```

- [ ] **Step 6: Build and run the package tests**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet 2>&1 | grep -E "error:" | head; echo "build exit ${PIPESTATUS[0]}"
grep -rn "MonthScreen\|DayScheduleScreen" --include='*.swift' LIfeOS LifeOSKit || echo "no stale names"
cd LifeOSKit && swift test 2>&1 | tail -3
```

Expected: `build exit 0`, `no stale names`, and the test summary ending in `passed` with no failures.

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/App/RootView.swift LIfeOS/Features/Assistant/View/AssistantSheet.swift LIfeOS/Features/Health/View/CalendarHealthDesignPreview.swift LIfeOS/Features/Today/View/TodayDesignPreview.swift
git commit -m "feat(calendar): open the calendar screen from the header and the assistant

The month and schedule preview pages mount it in each mode and take a
--select date. The event row dead since the month rewrite is deleted."
```

---

### Task 6: Captures and gates

**Files:** none changed unless a capture shows a fault.

- [ ] **Step 1: Build, install, capture**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/editorial-calendar/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B16BEDD3-51EB-442D-B84B-81EDDB2DF923
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/2742294b-e1ce-435a-8249-500b00fd3085/scratchpad
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { # name, then launch args
  local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-calendar-$name.png" >/dev/null
}
capture month --page=month
capture month-dark --page=month --dark
capture schedule --page=schedule
capture schedule-dark --page=schedule --dark
capture schedule-sep --page=schedule --select=2026-09-29
capture month-2027 --page=month --select=2027-01-15
ls -la $OUT/pr-calendar-*.png
```

If `APP` is empty the DerivedData folder for this worktree has a different path string in its `info.plist`; list them with `grep -l editorial-calendar ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist` and use that folder.

- [ ] **Step 2: Review each capture against the spec**

Open each PNG with the Read tool and check:

- `month`: `MONTHLY · 2026` / `Calendar`; the `Monthly | Weekly` switch under the masthead with `Monthly` underlined; `Today` dimmed beside the two chevrons, no glass capsule in the bar; October in the accent with hatched past days, today an accent cell, dots on event days; November in ink; `Go back` outlined at the foot.
- `schedule`: `WEEKLY · OCTOBER` / `Calendar` / `Oct 4 to Oct 10` (the current week's range); `Weekly` underlined; `Today` dimmed; seven bands with today's number in the accent, past numbers quiet, today's band open with its rows and `Add`, other days with a count tag.
- `schedule-sep`: `WEEKLY · SEPTEMBER` / `Sep 27 to Oct 3`; `Today` live; bands 27 to 3, the 29th open with the `11:00 · Dentist follow-up` row and `Add`, every other band with its number only. The `--select` date is today minus seven days when this plan runs on 2026-10-06; on another day pass that day's date minus seven instead, so the fixture event lands in the opened week.
- `month-2027`: `MONTHLY · 2027`; `Today` live; January and February, neither in the accent, no hatch, no today cell.
- Dark variants: paper near black, ink near white, hatch and today still in the accent, the switch underline visible.

Fix anything off in the owning file, commit with a `fix(calendar): ...` message, and repeat the capture.

- [ ] **Step 3: One tap: a day opens its week**

Read the Simulator's screen geometry and tap the cell for the 14th on the `month` page (one tap, then a screenshot), following the recipe in the `driving-lifeos-ios-simulator` memory: bring the Simulator frontmost immediately before the click, map pixels through the window's AXGroup, and use `cliclick`.

```bash
capture month-before-tap --page=month
osascript -e 'tell application "System Events" to set frontmost of process "Simulator" to true'
# Compute X,Y for the "14" cell from pr-calendar-month-before-tap.png and the AXGroup, then:
# cliclick -w 150 c:X,Y
perl -e 'select(undef,undef,undef,1.5)'
xcrun simctl io $SIM screenshot "$OUT/pr-calendar-month-after-tap.png" >/dev/null
```

Expected: the after capture shows `Weekly` underlined, `WEEKLY · OCTOBER` with the 14th's week as the range, and the 14th's band open. If two attempts do not land (the memory notes peers can steal focus), record that the tap check was not completed and rely on the `schedule` captures; do not spend more than two attempts.

- [ ] **Step 4: Gates**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar
(cd LifeOSKit && swift test 2>&1 | tail -2)
scripts/check-typography.sh > /tmp/typo-calendar.txt 2>&1
diff <(sed 's/^[^:]*://' /tmp/typo-calendar-base.txt | sort) <(sed 's/^[^:]*://' /tmp/typo-calendar.txt | sort) | grep '^>' || echo "typography: no new violations"
```

Expected: the test summary passes; `typography: no new violations`.

- [ ] **Step 5: Copy the captures into the review record**

Nothing is committed from the scratchpad; the PR body lists the capture names. Leave the PNGs in `$OUT` for the final report.

---

### Task 7: Open the pull request

- [ ] **Step 1: Rebase and push**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-calendar
git fetch origin
git rebase origin/main
git push -u origin feat/editorial-calendar
```

If the rebase conflicts, resolve in favour of keeping this branch's renames, rerun the Task 5 step 6 build, and continue the rebase.

- [ ] **Step 2: Open the PR** (base `main`; the body carries no attribution footer)

```bash
gh pr create --base main --head feat/editorial-calendar \
  --title "feat(calendar): one calendar screen with a Monthly | Weekly switch" \
  --body "$(cat <<'EOF'
## Summary

- The header's calendar button opens one `CalendarScreen` with a `Monthly | Weekly` underline switch. Monthly is the two hairline month grids from #20; Weekly is the stacked day bands from #20, now a body view (`WeekBands`) instead of a pushed screen.
- A tapped day in Monthly selects it and turns the screen to its week in place. The chevrons and the swipe step a month or a week by mode. `Today` moves out of the system bar into the header row as an editorial button, disabled when the shown month is this month or the shown week holds today.
- The masthead wording is a tested value, `CalendarHeadline`: Monthly names the shown month's year, Weekly names the selected day's month and carries the week's range.
- `MonthViewModel.stepWeek(_:)`; the assistant sheet's Schedule link opens the same screen; `--select=YYYY-MM-DD` on the `month` and `schedule` preview pages; the dead `CalendarEventRow.swift` is deleted.
- Spec: docs/superpowers/specs/2026-10-06-editorial-calendar-find-ask-widget-design.md (PR 1 of 5). Plan: docs/superpowers/plans/2026-10-06-editorial-calendar.md.

## Verification

- LifeOSKit `swift test`: all suites pass, including the three `CalendarHeadlineTests`.
- `scripts/check-typography.sh`: no new violations versus the base commit.
- Simulator design-preview pages `month`, `schedule`, light and dark, plus `schedule --select=2026-09-29` (a week across two months, Today live) and `month --select=2027-01-15` (another year, Today live), reviewed against the spec.
EOF
)"
```

- [ ] **Step 3: Report** the PR link, the capture paths under the scratchpad, the merge command `gh pr merge <n> --rebase --delete-branch`, and that PR 2 (`feat/editorial-coach`) is next and needs its plan written from the part-two spec §5 plus the spoken-track decision.
