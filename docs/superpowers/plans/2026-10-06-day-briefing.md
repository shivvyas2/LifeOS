# Day briefing screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One pushed `DayScreen` for any day, replacing the day sheet: a masthead that says where the day sits, a weather card with a tested Wear line, the agenda, the day's journal page as an editable checklist joined by due tasks and habits, readings, spend and that day's LIFO nudges, reachable from the Today grid, the calendar's open band and a day link.

**Architecture:** The wording and the rules live as tested values in the package: `DayHeadline`, `DayPlacement`, `DaySections`, `WearText` and `DayLookText` in `DesignSystem`; `DayForecast` and the `SurfaceRoute.day` link in `AppSurfaces`; `DayChecklist` and three `NotesStore` additions in `Persistence`. The app adds a `Day` feature folder: providers for WeatherKit and one location fix behind two protocols (with stubs for previews), a `WeatherCache`, a `DayBriefing` value built by `DayViewModel` from the stores the app already has, and `DayScreen` with its section views. `DayDetailSheet`, `DayDetailSnapshot` and the day-sheet half of `TodayViewModel` are deleted; `RootView`, `WeekBands`, `CalendarScreen`, `AssistantSheet` and `DotGrid` gain the ways in.

**Tech Stack:** SwiftUI, SwiftData, WeatherKit, CoreLocation, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-06-day-briefing-design.md`, all of it. The GitHub card and the email feed are later specs.

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. The accent only on today and anything live. Every button is `.buttonStyle(.editorial(role))` or `.buttonStyle(.plain)` around editorial content. No new colours, no per-module palette.
- Fonts only from `LifeOSType`, `Editorial.figure(_:)` and `Editorial.headline(_:)`; `scripts/check-typography.sh` must report nothing new versus the baseline taken in Task 0.
- `LifeOSKit` also builds for macOS 26 (`swift test` runs there): nothing iOS-only, no `WeatherKit` or `CoreLocation` in the package. `DesignSystem` has no dependencies and `AppSurfaces` has none; keep it that way (the Wear and day-look rules take plain numbers).
- `LIfeOS/` is a synchronized folder: new files, renames and deletions under it need no `project.pbxproj` edit. `Config/App-Info.plist` and `LIfeOS/LIfeOS.entitlements` are edited by hand.
- WeatherKit's own type is named `DayWeather`; the shared value in `AppSurfaces` is `DayForecast` so a file importing both compiles.
- Nothing here calls a model. WeatherKit is the only network call, at most one per shown day per hour (`WeatherCache`), inside its free tier. Coordinates go only to Apple; nothing about weather or location reaches LifeOS's servers.
- The Today tab's own layout, the calendar's Monthly grid and Weekly bands (beyond the open band's number tap), Notes screens and Settings are not touched.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution in commits or the PR body.
- Work happens in the worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/day-briefing` on branch `feat/day-briefing`, rebased onto `main` after PR #25 (`feat/editorial-calendar-ask`) merges, because Task 8 edits the `WeekBands` and `CalendarScreen` that PR produced. `Config/Secrets.xcconfig` is copied in and ignored.
- The simulator for builds and captures is `CalendarAsk iPhone 17`, id `B192EA65-BAA2-4814-A298-94A2F0C8FC87` (iOS 26.2). Peer sessions use the plain `iPhone 17`; do not install on it. Bundle id `com.shivvyas.lifeos`. The plain `sleep` is blocked in the Bash tool; wait with `perl -e 'select(undef,undef,undef,4)'`.
- `$OUT` is this session's scratchpad directory; the executor sets it in Task 0.

## Review Focus

1. Opening a past day must never create a journal page: a person flipping back through the month would otherwise leave thirty empty pages in Notes. `NotesStoreJournalTests.readingADayCreatesNothing` in Task 4.
2. A to-do on the journal page that also carries today's due date must appear once, not as its own row and again under "due": `DayChecklistTests.aJournalToDoIsNotAlsoADueRow` in Task 4.
3. The day link must parse exactly `almanac://day?date=YYYY-MM-DD` and nothing looser, or a widget tap lands on the wrong day or nowhere: `SurfaceRouteTests` in Task 3 pins a good link, a bad date, a stray query on `today`, and a `day` with two queries.
4. The Wear line's umbrella must name the hour only when the rain is still ahead; a person already in the rain reads "an umbrella", not "after 15:00": `WearTextTests.umbrellaNamesTheHourOnlyWhenAhead` in Task 2.
5. A habit created after the day being viewed must not appear on that day's record: `DayChecklistTests.habitsCreatedLaterAreNotOnAnOldDay` in Task 4.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/DayHeadline.swift` (new) | `DayPlacement`, `DayHeadline`, `DaySection`, `DaySections` |
| `LifeOSKit/Tests/DesignSystemTests/DayHeadlineTests.swift` (new) | Their tests |
| `LifeOSKit/Sources/DesignSystem/WearText.swift` (new) | The Wear rule table and `DayLookText` |
| `LifeOSKit/Tests/DesignSystemTests/WearTextTests.swift` (new) | Their tests |
| `LifeOSKit/Sources/DesignSystem/DotGrid.swift` | `DotGrid.isOpenable(_:)` public, future days tappable, hint |
| `LifeOSKit/Tests/DesignSystemTests/DotGridTests.swift` (new) | The tap rule |
| `LifeOSKit/Sources/AppSurfaces/DayForecast.swift` (new) | The shared weather value |
| `LifeOSKit/Sources/AppSurfaces/SurfaceSnapshot.swift` | `SurfaceRoute.day(Date)` |
| `LifeOSKit/Tests/AppSurfacesTests/SurfaceRouteTests.swift` (new) | Route and forecast tests; the old `allCases` loop moves here |
| `LifeOSKit/Sources/Persistence/DayChecklist.swift` (new) | `ChecklistRow`, `DayChecklist.rows` |
| `LifeOSKit/Tests/PersistenceTests/DayChecklistTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/Persistence/NotesStore.swift` | `journalEntryIfPresent(on:)`, the Journal folder, `tasks(dueOn:)` |
| `LifeOSKit/Tests/PersistenceTests/NotesStoreJournalTests.swift` (new) | Their tests |
| `LIfeOS/Features/Day/Model/WeatherProviding.swift` (new) | `WeatherProviding`, `LocationProviding`, `LocationAccess`, `DayProviders` and its environment key |
| `LIfeOS/Features/Day/Model/WeatherKitProvider.swift` (new) | WeatherKit mapped to `DayForecast` |
| `LIfeOS/Features/Day/Model/LocationOnce.swift` (new) | One reduced-accuracy fix behind when-in-use access |
| `LIfeOS/Features/Day/Model/WeatherCache.swift` (new) | Per-account cache, fresh for an hour |
| `LIfeOS/Features/Day/Model/DayStubs.swift` (new, DEBUG) | `StubWeatherProvider`, `StubLocation` |
| `LIfeOS/Features/Day/Model/DayBriefing.swift` (new) | `DayBriefing`, `WeatherState`, `DayReadings`, `DaySpend` |
| `LIfeOS/Features/Day/ViewModel/DayViewModel.swift` (new) | Loads the briefing, ticks, adds, steps days |
| `LIfeOS/Features/Day/View/DayScreen.swift` (new) | The screen |
| `LIfeOS/Features/Day/View/DaySections.swift` (new) | `WeatherCard`, `ChecklistRows`, the readings, money and nudge sections |
| `LIfeOS/Features/Today/View/AgendaRow.swift` (new) | The event row the bands and the day share |
| `LIfeOS/Features/Today/View/WeekBands.swift` | Uses `AgendaRow`; `onOpenDay` on the open band's number |
| `LIfeOS/Features/Today/View/CalendarScreen.swift` | Forwards `onOpenDay` |
| `LIfeOS/Features/Assistant/View/AssistantSheet.swift` | Pushes `DayScreen` from its calendar |
| `LIfeOS/App/RootView.swift` | `openDay`, the destination, the providers, the route; the day sheet goes |
| `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift` | `detail`, `select`, `clearSelection`, `toggleHabit` deleted |
| `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift` (deleted) | |
| `LIfeOS/Features/Today/View/DayDetailSheet.swift` (deleted) | |
| `LIfeOS/Features/Notes/View/NotesHubScreen.swift` | `NoteEditorHost` no longer private |
| `LIfeOS/App/PushService.swift` | DEBUG `previewSeed(entries:)` |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift` | Six day pages and the fixture's readings, spend, habits, tasks and nudges |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Routes the day pages |
| `Config/App-Info.plist`, `LIfeOS/LIfeOS.entitlements` | Location purpose string; WeatherKit entitlement |

---

### Task 0: Rebase, worktree and baselines

This PR builds on PR #25. Do not start until `feat/editorial-calendar-ask` is on `main`.

- [ ] **Step 1: Rebase the spec branch onto main and set up the worktree**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/day-briefing
git fetch origin && git merge-base --is-ancestor origin/feat/editorial-calendar-ask origin/main && echo "PR 25 is on main" || echo "STOP: PR 25 not merged"
git rebase origin/main && git log --oneline -3
ls Config/Secrets.xcconfig || cp /Users/shivvyas/LIfeOS/Config/Secrets.xcconfig Config/Secrets.xcconfig
git check-ignore -q Config/Secrets.xcconfig && echo "secrets ignored"
grep -n "onOpenDay\|highlighted" LIfeOS/Features/Today/View/WeekBands.swift | head -3
```

Expected: `PR 25 is on main`, a clean rebase with the spec commit on top, the secrets file present and ignored, and `highlighted` found in `WeekBands` (proof the calendar PR's code is here).

- [ ] **Step 2: Baselines**

```bash
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/$(ls /private/tmp/claude-501/-Users-shivvyas-LIfeOS | head -1)/scratchpad; echo "OUT=$OUT"
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
scripts/check-typography.sh > $OUT/typo-day-base.txt 2>&1; echo "typography baseline lines: $(wc -l < $OUT/typo-day-base.txt)"
xcrun simctl list devices | grep "CalendarAsk" || xcrun simctl create "CalendarAsk iPhone 17" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
df -h / | tail -1
```

Expected: the suite passes (1429 tests or more), a baseline line count, the simulator present, and more than 10 GB free (see the DerivedData memory if not).

- [ ] **Step 3: Commit the plan**

```bash
git add docs/superpowers/plans/2026-10-06-day-briefing.md
git commit -m "docs(plans): the day briefing screen"
```

---

### Task 1: `DayPlacement`, `DayHeadline` and `DaySections`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/DayHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/DayHeadlineTests.swift`

**Interfaces:**
- Produces: `public enum DayPlacement: Equatable, Sendable { case past(daysAgo: Int), today, future(daysAhead: Int); static func of(_ date: Date, now: Date, calendar: Calendar) -> DayPlacement; var isEditable: Bool }`; `public struct DayHeadline { eyebrow: String; title: String; static func make(date:now:calendar:locale:) -> DayHeadline }`; `public enum DaySection: CaseIterable { weather, agenda, checklist, readings, money, nudges }`; `public enum DaySections { static let forecastDays = 10; static func visible(for: DayPlacement) -> [DaySection] }`. Tasks 6 and 7 consume all of them.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct DayHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    @Test func placementCountsWholeDays() {
        let today = date(2026, 10, 6, hour: 23)
        #expect(DayPlacement.of(date(2026, 10, 6, hour: 1), now: today, calendar: calendar) == .today)
        #expect(DayPlacement.of(date(2026, 10, 5), now: today, calendar: calendar) == .past(daysAgo: 1))
        #expect(DayPlacement.of(date(2026, 10, 9), now: today, calendar: calendar) == .future(daysAhead: 3))
        #expect(DayPlacement.past(daysAgo: 2).isEditable == false)
        #expect(DayPlacement.today.isEditable && DayPlacement.future(daysAhead: 1).isEditable)
    }

    @Test func eyebrowNamesWhereTheDaySits() {
        let today = date(2026, 10, 6)
        func eyebrow(_ d: Date) -> String { DayHeadline.make(date: d, now: today, calendar: calendar, locale: en).eyebrow }
        #expect(eyebrow(date(2026, 10, 6)) == "Today · 6 October")
        #expect(eyebrow(date(2026, 10, 5)) == "Yesterday · 5 October")
        #expect(eyebrow(date(2026, 10, 7)) == "Tomorrow · 7 October")
        #expect(eyebrow(date(2026, 10, 8)) == "In 2 days · 8 October")
        #expect(eyebrow(date(2026, 10, 12)) == "In 6 days · 12 October")
        #expect(eyebrow(date(2026, 10, 4)) == "2 days ago · 4 October")
        #expect(eyebrow(date(2026, 9, 30)) == "6 days ago · 30 September")
    }

    @Test func farDaysShowTheDateAndTheYearOnlyWhenItDiffers() {
        let today = date(2026, 10, 6)
        let h = DayHeadline.make(date: date(2026, 11, 14), now: today, calendar: calendar, locale: en)
        #expect(h.eyebrow == "14 November")
        #expect(h.title == "Saturday")
        #expect(DayHeadline.make(date: date(2027, 1, 14), now: today, calendar: calendar, locale: en).eyebrow == "14 January 2027")
        #expect(DayHeadline.make(date: date(2026, 9, 29), now: today, calendar: calendar, locale: en).eyebrow == "29 September")
    }

    @Test func sectionsFollowThePlacement() {
        #expect(DaySections.visible(for: .today) == DaySection.allCases)
        #expect(DaySections.visible(for: .past(daysAgo: 3)) == [.agenda, .checklist, .readings, .money, .nudges])
        #expect(DaySections.visible(for: .future(daysAhead: 3)) == [.weather, .agenda, .checklist])
        #expect(DaySections.visible(for: .future(daysAhead: 9)) == [.weather, .agenda, .checklist])
        #expect(DaySections.visible(for: .future(daysAhead: 10)) == [.agenda, .checklist])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter DayHeadlineTests`
Expected: compile errors, `cannot find 'DayPlacement' in scope`.

- [ ] **Step 3: Write the values**

```swift
import Foundation

/// Where a day sits relative to today. It decides the eyebrow, which
/// sections the day screen shows, and whether its checklist can change.
public enum DayPlacement: Equatable, Sendable {
    case past(daysAgo: Int)
    case today
    case future(daysAhead: Int)

    public static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> DayPlacement {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days == 0 { return .today }
        return days > 0 ? .future(daysAhead: days) : .past(daysAgo: -days)
    }

    /// A past day is a record; today and the days ahead can be planned.
    public var isEditable: Bool {
        if case .past = self { return false }
        return true
    }
}

/// The day screen's masthead: the eyebrow says where the day sits and the
/// date, the title is the weekday. A value so the wording is tested.
public struct DayHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String

    public init(eyebrow: String, title: String) {
        self.eyebrow = eyebrow; self.title = title
    }

    public static func make(date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> DayHeadline {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        // Day then month, built by hand: one format puts the month first in
        // some locales, and the eyebrow reads as a date either way.
        let dayMonth = "\(date.formatted(style.day())) \(date.formatted(style.month(.wide)))"
        let placement: String? = switch DayPlacement.of(date, now: now, calendar: calendar) {
        case .today: "Today"
        case .past(let n) where n == 1: "Yesterday"
        case .future(let n) where n == 1: "Tomorrow"
        case .past(let n) where n <= 6: "\(n) days ago"
        case .future(let n) where n <= 6: "In \(n) days"
        default: nil
        }
        let eyebrow: String
        if let placement {
            eyebrow = "\(placement) · \(dayMonth)"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            eyebrow = dayMonth
        } else {
            eyebrow = "\(dayMonth) \(date.formatted(style.year()))"
        }
        return DayHeadline(eyebrow: eyebrow, title: date.formatted(style.weekday(.wide)))
    }
}

/// The parts of the day screen, in order.
public enum DaySection: CaseIterable, Equatable, Sendable {
    case weather, agenda, checklist, readings, money, nudges
}

/// Which parts a day shows. A past day is a record without a forecast; a
/// day ahead is a plan without readings, spend or nudges; the forecast
/// reaches ten days.
public enum DaySections {
    public static let forecastDays = 10

    public static func visible(for placement: DayPlacement) -> [DaySection] {
        switch placement {
        case .past: [.agenda, .checklist, .readings, .money, .nudges]
        case .today: DaySection.allCases
        case .future(let days): days < forecastDays ? [.weather, .agenda, .checklist] : [.agenda, .checklist]
        }
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter DayHeadlineTests`
Expected: `4 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/DayHeadline.swift LifeOSKit/Tests/DesignSystemTests/DayHeadlineTests.swift
git commit -m "feat(design): where a day sits, its masthead and its sections, as tested values"
```

---

### Task 2: `WearText` and `DayLookText`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/WearText.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/WearTextTests.swift`

**Interfaces:**
- Produces: `public enum WearText { static func line(feelsLikeHighC:feelsLikeLowC:rainChanceByHour:windKph:uvIndex:wakingHours:currentHour:calendar:locale:) -> String; static func firstWetHour(_:wakingHours:) -> Int? }`; `public enum DayLookText { struct Weather { conditionSymbol, feelsLikeHighC, rainChanceByHour }; static func sentence(weather:agendaCount:firstStart:dueCount:currentHour:wakingHours:calendar:locale:) -> String? }`. Task 6 calls both with numbers from `DayForecast`; `currentHour` is the hour now on today and nil on other days.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct WearTextTests {
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func rain(at hours: Int...) -> [Double] {
        var r = Array(repeating: 0.1, count: 24)
        for h in hours { r[h] = 0.6 }
        return r
    }
    private func line(high: Double, low: Double = 8, rain: [Double] = Array(repeating: 0, count: 24),
                      wind: Double = 10, uv: Int = 2, currentHour: Int? = nil) -> String {
        WearText.line(feelsLikeHighC: high, feelsLikeLowC: low, rainChanceByHour: rain, windKph: wind, uvIndex: uv,
                      currentHour: currentHour, calendar: calendar, locale: gb)
    }

    @Test func theBandsAndThePinnedExamples() {
        #expect(line(high: 15, low: 10, rain: rain(at: 15)) == "A light jacket or a sweater, an umbrella after 15:00.")
        #expect(line(high: 2, low: -3, wind: 35) == "Coat, hat and gloves, a windproof layer.")
        #expect(line(high: 20, low: 14, uv: 7) == "A t-shirt, sunscreen.")
        #expect(line(high: 28, low: 20, uv: 8) == "Light clothes, and carry water, sunscreen.")
        #expect(line(high: 8, low: 4) == "A warm jacket.")
    }

    @Test func layersWhenTheMorningIsMuchColder() {
        #expect(line(high: 22, low: 9) == "A t-shirt, layers for the morning.")
        #expect(line(high: 10, low: -2) == "A warm jacket.")
    }

    @Test func umbrellaNamesTheHourOnlyWhenAhead() {
        #expect(line(high: 15, low: 12, rain: rain(at: 15), currentHour: 9) == "A light jacket or a sweater, an umbrella after 15:00.")
        #expect(line(high: 15, low: 12, rain: rain(at: 15), currentHour: 16) == "A light jacket or a sweater, an umbrella.")
        #expect(line(high: 15, low: 12, rain: rain(at: 7)) == "A light jacket or a sweater, an umbrella.")
        #expect(line(high: 15, low: 12, rain: rain(at: 3)) == "A light jacket or a sweater.")
    }
}

@Suite struct DayLookTextTests {
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour))!
    }
    private func weather(_ symbol: String, high: Double, wet: Int? = nil) -> DayLookText.Weather {
        var r = Array(repeating: 0.0, count: 24)
        if let wet { r[wet] = 0.7 }
        return DayLookText.Weather(conditionSymbol: symbol, feelsLikeHighC: high, rainChanceByHour: r)
    }

    @Test func everyClausePresent() {
        let s = DayLookText.sentence(weather: weather("sun.max", high: 9, wet: 15), agendaCount: 3, firstStart: at(9),
                                     dueCount: 2, currentHour: 8, calendar: calendar, locale: gb)
        #expect(s == "Cool and sunny, rain from 15:00. Three things on, first at 09:00, two tasks due.")
    }

    @Test func clausesDropOut() {
        #expect(DayLookText.sentence(weather: weather("cloud.rain", high: 3), agendaCount: 0, firstStart: nil, dueCount: 0,
                                     calendar: calendar, locale: gb) == "Cold and wet. Nothing on.")
        #expect(DayLookText.sentence(weather: nil, agendaCount: 1, firstStart: at(14), dueCount: 1,
                                     calendar: calendar, locale: gb) == "One thing on at 14:00, one task due.")
        #expect(DayLookText.sentence(weather: weather("cloud", high: 15), agendaCount: 0, firstStart: nil, dueCount: 1,
                                     calendar: calendar, locale: gb) == "Mild and cloudy. Nothing on, one task due.")
        #expect(DayLookText.sentence(weather: nil, agendaCount: 0, firstStart: nil, dueCount: 0,
                                     calendar: calendar, locale: gb) == nil)
    }

    @Test func rainAlreadyFallingIsNotAnnouncedAsAhead() {
        let s = DayLookText.sentence(weather: weather("cloud.rain", high: 12, wet: 8), agendaCount: 0, firstStart: nil,
                                     dueCount: 0, currentHour: 10, calendar: calendar, locale: gb)
        #expect(s == "Mild and wet. Nothing on.")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "WearTextTests|DayLookTextTests"`
Expected: compile errors, `cannot find 'WearText' in scope`.

- [ ] **Step 3: Write the rules**

```swift
import Foundation

/// What to wear, from the day's numbers. A rule table, not a model: the
/// same forecast always gives the same line, and the line is tested.
public enum WearText {
    /// The first waking hour whose rain chance is 0.4 or more, or nil.
    public static func firstWetHour(_ rainChanceByHour: [Double], wakingHours: Range<Int> = 7..<22) -> Int? {
        wakingHours.first { hour in hour < rainChanceByHour.count && rainChanceByHour[hour] >= 0.4 }
    }

    /// `currentHour` is the hour now when the line is for today, so rain
    /// already falling is not announced as ahead; nil on any other day.
    public static func line(
        feelsLikeHighC high: Double, feelsLikeLowC low: Double, rainChanceByHour rain: [Double],
        windKph wind: Double, uvIndex uv: Int, wakingHours: Range<Int> = 7..<22,
        currentHour: Int? = nil, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        var parts: [String] = []
        switch high {
        case ..<5: parts.append("coat, hat and gloves")
        case ..<12: parts.append("a warm jacket")
        case ..<18: parts.append("a light jacket or a sweater")
        case ..<25: parts.append("a t-shirt")
        default: parts.append("light clothes, and carry water")
        }
        if high >= 12, high - low > 10 { parts.append("layers for the morning") }
        if let wet = firstWetHour(rain, wakingHours: wakingHours) {
            let threshold = currentHour ?? wakingHours.lowerBound
            if wet > threshold {
                parts.append("an umbrella after \(hourText(wet, calendar: calendar, locale: locale))")
            } else {
                parts.append("an umbrella")
            }
        }
        if wind >= 30 { parts.append("a windproof layer") }
        if uv >= 6 { parts.append("sunscreen") }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    /// `15:00` or `3:00 pm`, the way the device shows a time.
    public static func hourText(_ hour: Int, calendar: Calendar, locale: Locale) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let reference = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: .now)) ?? .now
        return reference.formatted(style.hour().minute())
    }
}

/// The one line under the day's masthead: the weather in plain words, what
/// is on, what is due. Nothing is known: no line.
public enum DayLookText {
    public struct Weather: Equatable, Sendable {
        public let conditionSymbol: String
        public let feelsLikeHighC: Double
        public let rainChanceByHour: [Double]
        public init(conditionSymbol: String, feelsLikeHighC: Double, rainChanceByHour: [Double]) {
            self.conditionSymbol = conditionSymbol; self.feelsLikeHighC = feelsLikeHighC; self.rainChanceByHour = rainChanceByHour
        }
    }

    public static func sentence(
        weather: Weather?, agendaCount: Int, firstStart: Date?, dueCount: Int,
        currentHour: Int? = nil, wakingHours: Range<Int> = 7..<22,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        if weather == nil, agendaCount == 0, dueCount == 0 { return nil }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        var sentences: [String] = []
        if let weather {
            var clause = "\(band(weather.feelsLikeHighC)) and \(condition(weather.conditionSymbol))"
            if let wet = WearText.firstWetHour(weather.rainChanceByHour, wakingHours: wakingHours),
               wet > (currentHour ?? wakingHours.lowerBound) {
                clause += ", rain from \(WearText.hourText(wet, calendar: calendar, locale: locale))"
            }
            sentences.append(clause + ".")
        }
        var dayClause: String
        switch agendaCount {
        case 0: dayClause = "Nothing on"
        case 1: dayClause = "One thing on" + (firstStart.map { " at \($0.formatted(style.hour().minute()))" } ?? "")
        default: dayClause = "\(count(agendaCount, capitalised: true)) things on" + (firstStart.map { ", first at \($0.formatted(style.hour().minute()))" } ?? "")
        }
        if dueCount > 0 {
            dayClause += ", \(count(dueCount, capitalised: false)) \(dueCount == 1 ? "task" : "tasks") due"
        }
        sentences.append(dayClause + ".")
        return sentences.joined(separator: " ")
    }

    private static func band(_ high: Double) -> String {
        switch high {
        case ..<5: "Cold"
        case ..<12: "Cool"
        case ..<18: "Mild"
        case ..<25: "Warm"
        default: "Hot"
        }
    }

    /// From the SF Symbol WeatherKit names the condition with.
    private static func condition(_ symbol: String) -> String {
        let s = symbol.lowercased()
        if s.contains("rain") || s.contains("drizzle") { return "wet" }
        if s.contains("snow") || s.contains("sleet") || s.contains("hail") { return "snowy" }
        if s.contains("wind") { return "windy" }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") { return "foggy" }
        if s.contains("cloud") { return "cloudy" }
        if s.contains("sun") { return "sunny" }
        return "clear"
    }

    private static func count(_ n: Int, capitalised: Bool) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let word = n < words.count ? words[n] : "\(n)"
        return capitalised ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter "WearTextTests|DayLookTextTests"`
Expected: `6 tests ... passed`. If `hourText` renders `15:00` with a different separator in `en_GB`, print it once and fix the test's expectation to the locale's real output rather than the rule.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/WearText.swift LifeOSKit/Tests/DesignSystemTests/WearTextTests.swift
git commit -m "feat(design): the Wear line and the day-look sentence as tested rules"
```

---

### Task 3: `DayForecast` and the day link

**Files:**
- Create: `LifeOSKit/Sources/AppSurfaces/DayForecast.swift`
- Modify: `LifeOSKit/Sources/AppSurfaces/SurfaceSnapshot.swift:53-62` (`SurfaceRoute`)
- Modify: `LifeOSKit/Tests/AppSurfacesTests/AppSurfacesTests.swift:51-57` (the `routesAcceptOnlyExactInternalDestinations` test moves)
- Test: `LifeOSKit/Tests/AppSurfacesTests/SurfaceRouteTests.swift` (new)

**Interfaces:**
- Produces: `public struct DayForecast: Codable, Equatable, Sendable` (fields in §2 of the spec, `isFresh(at:within:)`); `SurfaceRoute` becomes `enum SurfaceRoute: Equatable, Sendable { case today, health, activity, notifications, day(Date); static let fixed: [SurfaceRoute]; var url: URL; init?(url:) }`. `RootView.openSurfaceRoute` (Task 8) handles `.day`. The widgets keep using `.today.url`, `.health.url`, `.activity.url`.

- [ ] **Step 1: Write the failing tests**

Create `SurfaceRouteTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSurfaces

@Suite struct SurfaceRouteTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    @Test func fixedRoutesRoundTripAndRejectAnythingLooser() {
        for route in SurfaceRoute.fixed { #expect(SurfaceRoute(url: route.url) == route) }
        for value in ["https://health", "almanac://health?code=token", "almanac://health/path",
                      "almanac://health#fragment", "almanac://someone@health", "almanac://health:443",
                      "almanac://oauth", "almanac://today?date=2026-10-06"] {
            #expect(SurfaceRoute(url: URL(string: value)!) == nil)
        }
    }

    @Test func aDayLinkCarriesItsDate() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let route = SurfaceRoute.day(day)
        #expect(route.url.absoluteString == "almanac://day?date=2026-10-06")
        #expect(SurfaceRoute(url: route.url) == .day(day))
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=2026-10-06T09:00")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=not-a-day")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=2026-10-06&x=1")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day")!) == nil)
    }

    @Test func aForecastRoundTripsAndKnowsWhenItIsStale() throws {
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let forecast = DayForecast(day: now, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                                   highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                                   rainChanceByHour: Array(repeating: 0.1, count: 24), windKph: 12, uvIndex: 3,
                                   sunrise: now, sunset: now.addingTimeInterval(40_000), fetchedAt: now)
        let data = try JSONEncoder().encode(forecast)
        #expect(try JSONDecoder().decode(DayForecast.self, from: data) == forecast)
        #expect(forecast.isFresh(at: now.addingTimeInterval(1_800)))
        #expect(!forecast.isFresh(at: now.addingTimeInterval(3_601)))
    }
}
```

In `AppSurfacesTests.swift`, delete `routesAcceptOnlyExactInternalDestinations` (lines 51 to 57); the new suite covers it.

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "SurfaceRouteTests|AppSurfacesTests"`
Expected: compile errors, `type 'SurfaceRoute' has no member 'fixed'` and `cannot find 'DayForecast'`.

- [ ] **Step 3: Write the value and the route**

`DayForecast.swift`:

```swift
import Foundation

/// One day's weather as the day screen draws it, in Celsius and km/h so the
/// rules in DesignSystem read plain numbers; the screen formats for the
/// device. Shared through AppSurfaces so a widget can read it later.
public struct DayForecast: Codable, Equatable, Sendable {
    public let day: Date
    public let conditionSymbol: String
    public let conditionName: String
    public let highC: Double
    public let lowC: Double
    public let feelsLikeHighC: Double
    public let feelsLikeLowC: Double
    /// 24 values, 0 to 1, from the day's first hour.
    public let rainChanceByHour: [Double]
    public let windKph: Double
    public let uvIndex: Int
    public let sunrise: Date?
    public let sunset: Date?
    public let fetchedAt: Date

    public init(day: Date, conditionSymbol: String, conditionName: String,
                highC: Double, lowC: Double, feelsLikeHighC: Double, feelsLikeLowC: Double,
                rainChanceByHour: [Double], windKph: Double, uvIndex: Int,
                sunrise: Date?, sunset: Date?, fetchedAt: Date) {
        self.day = day; self.conditionSymbol = conditionSymbol; self.conditionName = conditionName
        self.highC = highC; self.lowC = lowC; self.feelsLikeHighC = feelsLikeHighC; self.feelsLikeLowC = feelsLikeLowC
        self.rainChanceByHour = rainChanceByHour; self.windKph = windKph; self.uvIndex = uvIndex
        self.sunrise = sunrise; self.sunset = sunset; self.fetchedAt = fetchedAt
    }

    /// Fresh for an hour: a forecast changes slower than a person reopens a day.
    public func isFresh(at now: Date, within interval: TimeInterval = 3_600) -> Bool {
        now.timeIntervalSince(fetchedAt) < interval
    }
}
```

Replace `SurfaceRoute` in `SurfaceSnapshot.swift` with:

```swift
/// Where a tap outside the app lands inside it. The four fixed routes are
/// hosts alone; `day` carries a calendar date as its only query.
public enum SurfaceRoute: Equatable, Sendable {
    case today, health, activity, notifications
    case day(Date)

    public static let fixed: [SurfaceRoute] = [.today, .health, .activity, .notifications]

    public var url: URL {
        switch self {
        case .today: URL(string: "almanac://today")!
        case .health: URL(string: "almanac://health")!
        case .activity: URL(string: "almanac://activity")!
        case .notifications: URL(string: "almanac://notifications")!
        case .day(let date): URL(string: "almanac://day?date=\(Self.dayFormatter().string(from: date))")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == "almanac", url.user == nil, url.password == nil,
              url.port == nil, url.path.isEmpty, url.fragment == nil, let host = url.host else { return nil }
        if host == "day" {
            guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  items.count == 1, items[0].name == "date", let raw = items[0].value,
                  let date = Self.dayFormatter().date(from: raw) else { return nil }
            self = .day(date)
            return
        }
        guard url.query == nil else { return nil }
        switch host {
        case "today": self = .today
        case "health": self = .health
        case "activity": self = .activity
        case "notifications": self = .notifications
        default: return nil
        }
    }

    /// A calendar date in the device's zone, the same shape the inbox's `day` uses.
    private static func dayFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }
}
```

- [ ] **Step 4: Run them to see them pass, and build the app and the widget**

Run: `cd LifeOSKit && swift test --filter "SurfaceRouteTests|AppSurfacesTests"`
Expected: all pass.

`RootView.openSurfaceRoute` switches over the enum and now lacks `.day`, so the app will not build until Task 8; `MockServices` and `SurfaceCoordinator` only store the value. Check the widget alone now:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme AlmanacWidgets -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-widgets-task3.log 2>&1; echo "widgets build exit $?"; grep "error:" $OUT/build-widgets-task3.log | head -3
```

Expected: `widgets build exit 0`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/AppSurfaces/DayForecast.swift LifeOSKit/Sources/AppSurfaces/SurfaceSnapshot.swift \
  LifeOSKit/Tests/AppSurfacesTests/AppSurfacesTests.swift LifeOSKit/Tests/AppSurfacesTests/SurfaceRouteTests.swift
git commit -m "feat(surfaces): a day link that carries its date, and the shared forecast value

SurfaceRoute drops its raw value so day can carry a calendar date as its
only query; the four fixed routes are unchanged for the widgets."
```

---

### Task 4: The checklist and the journal page in the store

**Files:**
- Create: `LifeOSKit/Sources/Persistence/DayChecklist.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/DayChecklistTests.swift`
- Modify: `LifeOSKit/Sources/Persistence/NotesStore.swift:350-367` (`journalEntry`) and after `indexedTasks`
- Test: `LifeOSKit/Tests/PersistenceTests/NotesStoreJournalTests.swift`

**Interfaces:**
- Produces: `public struct ChecklistRow: Identifiable, Equatable, Sendable { enum Source { journal(blockID:), page(documentID:blockID:), habit(entryID:) }; id: String; source; text; detail: String?; isDone; isEditable }`; `public enum DayChecklist { struct DueTask { documentID, blockID, text, isChecked, pageTitle }; struct Habit { id, title, createdAt, streak }; static func rows(journal: [NoteBlock], journalID: UUID?, due: [DueTask], habits: [Habit], ticked: Set<UUID>, day: Date, editable: Bool, calendar: Calendar) -> [ChecklistRow] }`; `NotesStore.journalEntryIfPresent(on:) -> NoteDocument?`, `NotesStore.tasks(dueOn:) -> [NoteTask]`; `journalEntry(on:in:)` now files into the bucket's `Journal` folder. Task 6 consumes all of them.

- [ ] **Step 1: Write the failing checklist tests**

```swift
import Testing
import Foundation
@testable import Persistence

@Suite struct DayChecklistTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))! }
    private let journalID = UUID()

    @Test func rowsComeInOrderJournalDueThenHabits() {
        let run = UUID(), read = UUID()
        let rows = DayChecklist.rows(
            journal: [NoteBlock(kind: .heading1, text: "Tuesday"),
                      NoteBlock(kind: .todo, text: "Call the dentist", isChecked: true),
                      NoteBlock(kind: .todo, text: "Draft the plan")],
            journalID: journalID,
            due: [DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: "Buy oat milk", isChecked: false, pageTitle: "Groceries")],
            habits: [DayChecklist.Habit(id: run, title: "5km run", createdAt: day.addingTimeInterval(-86_400 * 30), streak: 6),
                     DayChecklist.Habit(id: read, title: "Read 10 pages", createdAt: day.addingTimeInterval(-86_400), streak: 0)],
            ticked: [run], day: day, editable: true, calendar: calendar
        )
        #expect(rows.map(\.text) == ["Call the dentist", "Draft the plan", "Buy oat milk", "5km run", "Read 10 pages"])
        #expect(rows.map(\.isDone) == [true, false, false, true, false])
        #expect(rows[2].detail == "Groceries")
        #expect(rows[3].detail == "6 days")
        #expect(rows[4].detail == nil)
        #expect(rows.allSatisfy(\.isEditable))
        #expect(Set(rows.map(\.id)).count == 5)
    }

    @Test func aJournalToDoIsNotAlsoADueRow() {
        let block = NoteBlock(kind: .todo, text: "Draft the plan", dueDate: day)
        let rows = DayChecklist.rows(
            journal: [block], journalID: journalID,
            due: [DayChecklist.DueTask(documentID: journalID, blockID: block.id, text: block.text, isChecked: false, pageTitle: "Tuesday, October 6")],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar
        )
        #expect(rows.map(\.text) == ["Draft the plan"])
    }

    @Test func habitsCreatedLaterAreNotOnAnOldDay() {
        let rows = DayChecklist.rows(
            journal: [], journalID: nil, due: [],
            habits: [DayChecklist.Habit(id: UUID(), title: "Stretch", createdAt: day.addingTimeInterval(86_400 * 2), streak: 0),
                     DayChecklist.Habit(id: UUID(), title: "Walk", createdAt: day.addingTimeInterval(3_600), streak: 0)],
            ticked: [], day: day, editable: false, calendar: calendar
        )
        #expect(rows.map(\.text) == ["Walk"])
        #expect(rows.allSatisfy { !$0.isEditable })
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter DayChecklistTests`
Expected: compile errors, `cannot find 'DayChecklist' in scope`.

- [ ] **Step 3: Write the checklist**

```swift
import Foundation

/// One line on the day's checklist, from the journal page, another page
/// due that day, or a habit. Plain values: the screen never holds a model.
public struct ChecklistRow: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case journal(blockID: UUID)
        case page(documentID: UUID, blockID: UUID)
        case habit(entryID: UUID)
    }

    public let id: String
    public let source: Source
    public let text: String
    /// The page title for a due row, the streak for a habit, nothing for
    /// the day's own list.
    public let detail: String?
    public let isDone: Bool
    public let isEditable: Bool

    public init(source: Source, text: String, detail: String?, isDone: Bool, isEditable: Bool) {
        self.id = switch source {
        case .journal(let blockID): "journal|\(blockID.uuidString)"
        case .page(let documentID, let blockID): "page|\(documentID.uuidString)|\(blockID.uuidString)"
        case .habit(let entryID): "habit|\(entryID.uuidString)"
        }
        self.source = source; self.text = text; self.detail = detail
        self.isDone = isDone; self.isEditable = isEditable
    }
}

/// Merges the three sources of a day's checklist in a fixed order.
public enum DayChecklist {
    public struct DueTask: Equatable, Sendable {
        public let documentID: UUID
        public let blockID: UUID
        public let text: String
        public let isChecked: Bool
        public let pageTitle: String
        public init(documentID: UUID, blockID: UUID, text: String, isChecked: Bool, pageTitle: String) {
            self.documentID = documentID; self.blockID = blockID; self.text = text
            self.isChecked = isChecked; self.pageTitle = pageTitle
        }
    }

    public struct Habit: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let createdAt: Date
        public let streak: Int
        public init(id: UUID, title: String, createdAt: Date, streak: Int) {
            self.id = id; self.title = title; self.createdAt = createdAt; self.streak = streak
        }
    }

    /// The journal page's to-dos in page order, then what is due from other
    /// pages (a journal to-do that also carries the date is not repeated),
    /// then the habits that existed by the end of the day.
    public static func rows(
        journal: [NoteBlock], journalID: UUID?, due: [DueTask], habits: [Habit],
        ticked: Set<UUID>, day: Date, editable: Bool, calendar: Calendar = .current
    ) -> [ChecklistRow] {
        var rows: [ChecklistRow] = []
        for block in journal where block.kind == .todo {
            rows.append(ChecklistRow(source: .journal(blockID: block.id), text: block.text, detail: nil,
                                     isDone: block.isChecked, isEditable: editable))
        }
        for task in due where task.documentID != journalID {
            rows.append(ChecklistRow(source: .page(documentID: task.documentID, blockID: task.blockID),
                                     text: task.text, detail: task.pageTitle, isDone: task.isChecked, isEditable: editable))
        }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        for habit in habits where habit.createdAt < dayEnd {
            let streak = habit.streak > 0 ? "\(habit.streak) \(habit.streak == 1 ? "day" : "days")" : nil
            rows.append(ChecklistRow(source: .habit(entryID: habit.id), text: habit.title, detail: streak,
                                     isDone: ticked.contains(habit.id), isEditable: editable))
        }
        return rows
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter DayChecklistTests`
Expected: `3 tests ... passed`.

- [ ] **Step 5: Write the failing store tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NotesStoreJournalTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func makeStore() throws -> NotesStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return NotesStore(context: ModelContext(container), calendar: calendar)
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9))! }

    @Test func readingADayCreatesNothing() throws {
        let store = try makeStore()
        #expect(try store.journalEntryIfPresent(on: day) == nil)
        #expect(try store.documents(includeArchived: true).isEmpty)
        let page = try store.journalEntry(on: day)
        #expect(try store.journalEntryIfPresent(on: day)?.id == page.id)
        #expect(try store.journalEntryIfPresent(on: day.addingTimeInterval(86_400)) == nil)
    }

    @Test func aJournalPageLandsInTheJournalFolderAndMakesItWhenMissing() throws {
        let store = try makeStore()
        let page = try store.journalEntry(on: day)
        let folder = try #require(try store.folders().first { $0.name == "Journal" })
        #expect(folder.bucket == .areas)
        #expect(page.folderID == folder.id)
        #expect(page.filedAt != nil)
        let second = try store.journalEntry(on: day.addingTimeInterval(86_400))
        #expect(second.folderID == folder.id)
        #expect(try store.folders().filter { $0.name == "Journal" }.count == 1)
    }

    @Test func tasksDueOnADaySpanTheWholeDay() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Groceries", bucket: .projects)
        try store.update(page, blocks: [
            NoteBlock(kind: .todo, text: "Morning", dueDate: calendar.startOfDay(for: day)),
            NoteBlock(kind: .todo, text: "Evening", dueDate: day.addingTimeInterval(13 * 3_600)),
            NoteBlock(kind: .todo, text: "Tomorrow", dueDate: day.addingTimeInterval(86_400)),
            NoteBlock(kind: .todo, text: "Undated"),
        ])
        #expect(try store.tasks(dueOn: day).map(\.text) == ["Morning", "Evening"])
    }
}
```

- [ ] **Step 6: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter NotesStoreJournalTests`
Expected: compile error, `value of type 'NotesStore' has no member 'journalEntryIfPresent'`.

- [ ] **Step 7: Change the store**

Replace `journalEntry(on:in:)` (lines 350 to 367) with:

```swift
    /// The day's journal page if there is one. Never creates: a past day
    /// read from the day screen must not leave an empty page behind.
    public func journalEntryIfPresent(on date: Date) throws -> NoteDocument? {
        let day = calendar.startOfDay(for: date)
        return try documents(includeArchived: true).first {
            $0.kind == .journal && $0.entryDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
    }

    /// Today's journal entry, created on first write rather than on first
    /// launch: an empty page dated every day is noise, not a journal. It
    /// lives in the bucket's `Journal` folder, made here when missing.
    @discardableResult
    public func journalEntry(on date: Date = .now, in bucket: NoteBucket = .areas) throws -> NoteDocument {
        if let existing = try journalEntryIfPresent(on: date) { return existing }
        let day = calendar.startOfDay(for: date)
        return try createDocument(
            title: day.formatted(.dateTime.weekday(.wide).month(.wide).day()),
            kind: .journal,
            bucket: bucket,
            folderID: try journalFolderID(in: bucket),
            entryDate: day
        )
    }

    private func journalFolderID(in bucket: NoteBucket) throws -> UUID {
        if let folder = try folders().first(where: { $0.bucket == bucket && $0.parentID == nil && $0.name == "Journal" }) {
            return folder.id
        }
        return try createFolder(name: "Journal", bucket: bucket, icon: "\u{1F5D3}").id
    }
```

After `indexedTasks(openOnly:)` add:

```swift
    /// To-dos due on the day, across every page, open and done.
    public func tasks(dueOn date: Date) throws -> [NoteTask] {
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return try indexedTasks().filter { task in
            guard let due = task.dueDate else { return false }
            return due >= day && due < next
        }
    }
```

- [ ] **Step 8: Run the Persistence suites**

Run: `cd LifeOSKit && swift test --filter "NotesStoreJournalTests|NotesStoreTests|PlanNoteMigrationTests|NoteIndexerTests"`
Expected: all pass, including `todaysJournalIsCreatedOnceAndThenReused`. If a migration test counted folders and now sees the Journal folder created twice, the `seedIfEmpty` folder has no `parentID` and the same name, so `journalFolderID` must find it; check the predicate before touching the test.

- [ ] **Step 9: Commit**

```bash
git add LifeOSKit/Sources/Persistence/DayChecklist.swift LifeOSKit/Tests/PersistenceTests/DayChecklistTests.swift \
  LifeOSKit/Sources/Persistence/NotesStore.swift LifeOSKit/Tests/PersistenceTests/NotesStoreJournalTests.swift
git commit -m "feat(persistence): the day's checklist, a read-only journal lookup, and journal pages in their folder

DayChecklist merges the journal page's to-dos, what is due from other
pages and the habits that existed by that day. Reading a day never
creates its page; creating one files it in the Journal folder."
```

---

### Task 5: Weather and location providers in the app

**Files:**
- Create: `LIfeOS/Features/Day/Model/WeatherProviding.swift`, `WeatherKitProvider.swift`, `LocationOnce.swift`, `WeatherCache.swift`, `DayStubs.swift`
- Modify: `Config/App-Info.plist` (location purpose string), `LIfeOS/LIfeOS.entitlements` (WeatherKit)

**Interfaces:**
- Consumes: `DayForecast` (Task 3).
- Produces: `protocol WeatherProviding: Sendable { func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? }`; `enum LocationAccess { notDetermined, denied, granted }`; `@MainActor protocol LocationProviding: AnyObject { var access: LocationAccess { get }; func requestAccess() async -> LocationAccess; func currentLocation() async throws -> CLLocation }`; `struct DayProviders { weather: any WeatherProviding; location: any LocationProviding }` with `EnvironmentValues.dayProviders: DayProviders?`; `WeatherKitProvider`, `LocationOnce`, `WeatherCache(defaults:)` with `forecast(for:)` and `store(_:)`; DEBUG `StubWeatherProvider(forecast:)` and `StubLocation(access:)`. Task 6 reads the providers; Task 8 installs them in `RootView`; Task 7's previews install the stubs.

There is no unit seam for CoreLocation or WeatherKit; the gate is the app build and the stubbed previews.

- [ ] **Step 1: The protocols and the environment key**

`WeatherProviding.swift`:

```swift
import SwiftUI
import CoreLocation
import AppSurfaces

/// Where a day's forecast comes from. WeatherKit in the app, a stub in previews.
protocol WeatherProviding: Sendable {
    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast?
}

enum LocationAccess: Equatable, Sendable {
    case notDetermined, denied, granted
}

/// One fix, with permission asked on first use rather than at launch.
@MainActor
protocol LocationProviding: AnyObject {
    var access: LocationAccess { get }
    func requestAccess() async -> LocationAccess
    func currentLocation() async throws -> CLLocation
}

/// Both providers, handed down the environment so the sheet's calendar and
/// the Today stack push the same day screen with the same sources.
struct DayProviders {
    let weather: any WeatherProviding
    let location: any LocationProviding
}

extension EnvironmentValues {
    @Entry var dayProviders: DayProviders?
}
```

- [ ] **Step 2: WeatherKit**

`WeatherKitProvider.swift`:

```swift
import Foundation
import WeatherKit
import CoreLocation
import AppSurfaces

/// WeatherKit's day and hours, folded into one `DayForecast`. Feels-like
/// high and low come from the hours, which is what a person dressing at
/// seven and walking home at six actually meets.
struct WeatherKitProvider: WeatherProviding {
    private let calendar = Calendar.current

    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let (daily, hourly) = try await WeatherService.shared.weather(
            for: location,
            including: .daily(startDate: start, endDate: end), .hourly(startDate: start, endDate: end)
        )
        guard let dayWeather = daily.forecast.first(where: { calendar.isDate($0.date, inSameDayAs: start) }) else { return nil }
        let hours = hourly.forecast.filter { $0.date >= start && $0.date < end }
        var rain = Array(repeating: 0.0, count: 24)
        for hour in hours {
            rain[calendar.component(.hour, from: hour.date)] = hour.precipitationChance
        }
        let feels = hours.map { $0.apparentTemperature.converted(to: .celsius).value }
        let high = dayWeather.highTemperature.converted(to: .celsius).value
        let low = dayWeather.lowTemperature.converted(to: .celsius).value
        return DayForecast(
            day: start,
            conditionSymbol: dayWeather.symbolName,
            conditionName: dayWeather.condition.description,
            highC: high, lowC: low,
            feelsLikeHighC: feels.max() ?? high, feelsLikeLowC: feels.min() ?? low,
            rainChanceByHour: rain,
            windKph: dayWeather.wind.speed.converted(to: .kilometersPerHour).value,
            uvIndex: dayWeather.uvIndex.value,
            sunrise: dayWeather.sun.sunrise, sunset: dayWeather.sun.sunset,
            fetchedAt: .now
        )
    }
}
```

- [ ] **Step 3: One location fix**

`LocationOnce.swift`:

```swift
import Foundation
import CoreLocation

/// Asks for when-in-use access the first time it is needed and returns one
/// reduced-accuracy fix: a city is enough for weather, and nothing here
/// tracks anyone.
@MainActor
final class LocationOnce: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var accessWaiters: [CheckedContinuation<LocationAccess, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var access: LocationAccess { Self.access(for: manager.authorizationStatus) }

    func requestAccess() async -> LocationAccess {
        if access != .notDetermined { return access }
        return await withCheckedContinuation { continuation in
            accessWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -900 { return last }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .granted
        default: .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let access = Self.access(for: status)
            let waiters = accessWaiters
            accessWaiters = []
            waiters.forEach { $0.resume(returning: access) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(returning: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 4: The cache and the stubs**

`WeatherCache.swift`:

```swift
import Foundation
import AppSurfaces
import Persistence

/// The last forecast per day, in the account's defaults. Fresh for an hour;
/// at most fourteen days kept, so flipping through a fortnight costs one
/// call per day, not one per open.
struct WeatherCache {
    private let defaults: UserDefaults
    private static let key = "day.forecasts"

    init(defaults: UserDefaults = .currentAccount) { self.defaults = defaults }

    func forecast(for day: Date, calendar: Calendar = .current) -> DayForecast? {
        all()[Self.dayKey(day, calendar: calendar)]
    }

    func store(_ forecast: DayForecast, calendar: Calendar = .current) {
        var forecasts = all()
        forecasts[Self.dayKey(forecast.day, calendar: calendar)] = forecast
        let kept = forecasts.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(14)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func all() -> [String: DayForecast] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: DayForecast].self, from: data) else { return [:] }
        return decoded
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }
}
```

`DayStubs.swift`:

```swift
#if DEBUG
import Foundation
import CoreLocation
import AppSurfaces

/// A fixed forecast for previews: mild, cloudy, rain from three.
struct StubWeatherProvider: WeatherProviding {
    var forecast: DayForecast?

    static func sample(for day: Date, calendar: Calendar = .current) -> DayForecast {
        var rain = Array(repeating: 0.1, count: 24)
        for hour in 15...17 { rain[hour] = 0.55 }
        let start = calendar.startOfDay(for: day)
        return DayForecast(day: start, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                           highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                           rainChanceByHour: rain, windKph: 12, uvIndex: 3,
                           sunrise: calendar.date(bySettingHour: 7, minute: 12, second: 0, of: start),
                           sunset: calendar.date(bySettingHour: 18, minute: 31, second: 0, of: start),
                           fetchedAt: .now)
    }

    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? {
        forecast ?? Self.sample(for: day)
    }
}

/// A location that answers at once with whatever access the page wants.
@MainActor
final class StubLocation: LocationProviding {
    private(set) var access: LocationAccess
    init(access: LocationAccess = .granted) { self.access = access }
    func requestAccess() async -> LocationAccess {
        if access == .notDetermined { access = .granted }
        return access
    }
    func currentLocation() async throws -> CLLocation { CLLocation(latitude: 51.5, longitude: -0.12) }
}
#endif
```

- [ ] **Step 5: The purpose string and the entitlement**

In `Config/App-Info.plist`, inside the top-level `<dict>`, after the `NSCalendarsFullAccessUsageDescription` entry, add:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>LifeOS uses your location for the weather on your day screen.</string>
```

In `LIfeOS/LIfeOS.entitlements`, before the closing `</dict>`, add:

```xml
	<!-- Weather on the day screen. WeatherKit wants a dummy entry here and the
	     capability on the App ID; the owner turns that on in the portal. -->
	<key>com.apple.developer.weatherkit</key>
	<array><string>dummy</string></array>
```

- [ ] **Step 6: Build the app**

The app will not link until Task 8 handles `.day` in `openSurfaceRoute`; to check this task alone, add the one missing case now as a placeholder that Task 8 replaces: in `RootView.openSurfaceRoute()` add `case .day: tab = .today` after `.notifications`. Then:

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task5.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task5.log | head -5
```

Expected: `build exit 0`. If signing complains about the WeatherKit entitlement on the simulator build, the automatic provisioning profile lacks the capability; keep the entitlement and note it in the PR body as the owner's step (the simulator run does not need the service).

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/Features/Day/Model/WeatherProviding.swift LIfeOS/Features/Day/Model/WeatherKitProvider.swift \
  LIfeOS/Features/Day/Model/LocationOnce.swift LIfeOS/Features/Day/Model/WeatherCache.swift LIfeOS/Features/Day/Model/DayStubs.swift \
  Config/App-Info.plist LIfeOS/LIfeOS.entitlements LIfeOS/App/RootView.swift
git commit -m "feat(day): weather from WeatherKit behind one location fix, with a cache and preview stubs"
```

---

### Task 6: `DayBriefing` and `DayViewModel`

**Files:**
- Create: `LIfeOS/Features/Day/Model/DayBriefing.swift`, `LIfeOS/Features/Day/ViewModel/DayViewModel.swift`
- Modify: `LIfeOS/App/PushService.swift` (DEBUG seed)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `enum WeatherState`, `struct DayReadings`, `struct DaySpend`, `struct MoneyRow`, `struct DayBriefing`; `@MainActor @Observable final class DayViewModel { init(date:calendar:); private(set) var date; private(set) var briefing: DayBriefing?; func attach(_ context: ModelContext, providers: DayProviders?, sync: NoteSyncing?); func load(); func step(_ days: Int); func goToToday(); func goTo(_ date: Date); func tick(_ row: ChecklistRow); func add(_ text: String); func allowLocation() async; var isOnToday: Bool }`. Task 7 draws from it.

The view model composes tested values; its own code is store plumbing, verified by the build and the previews in Task 7.

- [ ] **Step 1: The briefing values**

`DayBriefing.swift`:

```swift
import Foundation
import AppSurfaces
import DesignSystem
import Persistence

enum WeatherState: Equatable {
    case hidden, needsLocation, denied, loading, unavailable
    case ready(DayForecast)
}

struct DayReadings: Equatable {
    var steps: Int?
    var stepsTarget: Int
    var sleepMinutes: Int?
    var sleepTargetMinutes: Int
    var weightKg: Double?
    var recoveryPct: Double?
}

struct MoneyRow: Identifiable, Equatable {
    let id: UUID
    let merchant: String
    let amount: Double
}

struct DaySpend: Equatable {
    let total: Double
    let rows: [MoneyRow]
}

struct DayWorkout: Identifiable, Equatable {
    let id: String
    let title: String
    let durationMinutes: Int
}

/// Everything the day screen draws, as plain values.
struct DayBriefing: Equatable {
    let date: Date
    let placement: DayPlacement
    let sections: [DaySection]
    var weather: WeatherState
    var agenda: [CalendarEventSnapshot]
    var checklist: [ChecklistRow]
    var readings: DayReadings?
    var workouts: [DayWorkout]
    var spend: DaySpend?
    var nudges: [InboxEntry]
    var dayLook: String?

    var checklistDone: Int { checklist.filter(\.isDone).count }
}
```

- [ ] **Step 2: The DEBUG seed on the inbox**

In `PushService.swift`, inside the class, after `var unreadCount`, add:

```swift
    #if DEBUG
    /// Previews need a day's nudges without a push: seeds the inbox in memory.
    func previewSeed(entries: [InboxEntry]) { self.entries = entries }
    #endif
```

- [ ] **Step 3: The view model**

`DayViewModel.swift`:

```swift
import Foundation
import SwiftData
import AppSurfaces
import DesignSystem
import Persistence

/// Loads one day's briefing from the stores and the weather provider, and
/// writes ticks and new tasks back through the same paths the editor uses.
@MainActor @Observable
final class DayViewModel {
    private(set) var date: Date
    private(set) var briefing: DayBriefing?

    private var context: ModelContext?
    private var providers: DayProviders?
    private var sync: NoteSyncing?
    private let calendar: Calendar
    private var weatherTask: Task<Void, Never>?

    init(date: Date, calendar: Calendar = .current) {
        self.date = calendar.startOfDay(for: date)
        self.calendar = calendar
    }

    func attach(_ context: ModelContext, providers: DayProviders?, sync: NoteSyncing?) {
        self.context = context
        self.providers = providers
        self.sync = sync
    }

    var isOnToday: Bool { calendar.isDateInToday(date) }

    func step(_ days: Int) {
        guard let moved = calendar.date(byAdding: .day, value: days, to: date) else { return }
        goTo(moved)
    }

    func goToToday() { goTo(.now) }

    func goTo(_ newDate: Date) {
        date = calendar.startOfDay(for: newDate)
        load()
    }

    /// Everything but the weather, synchronously; the weather follows.
    func load() {
        guard let context else { return }
        let placement = DayPlacement.of(date, calendar: calendar)
        let sections = DaySections.visible(for: placement)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        var briefing = DayBriefing(
            date: date, placement: placement, sections: sections,
            weather: sections.contains(.weather) ? (self.briefing?.date == date ? self.briefing?.weather ?? .loading : .loading) : .hidden,
            agenda: [], checklist: [], readings: nil, workouts: [], spend: nil, nudges: [], dayLook: nil
        )
        do {
            briefing.agenda = try CalendarStore(context: context, calendar: calendar)
                .events(from: date, to: dayEnd)
                .sorted { lhs, rhs in
                    if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                    return lhs.startDate < rhs.startDate
                }
            briefing.checklist = try loadChecklist(context: context, editable: placement.isEditable)
            if sections.contains(.readings) {
                let metrics = MetricsStore(context: context, calendar: calendar)
                let targets = try metrics.goals().targets
                let row = try metrics.metrics(from: date, to: date).first
                briefing.readings = DayReadings(
                    steps: row?.steps, stepsTarget: targets.steps,
                    sleepMinutes: row?.sleepMinutes, sleepTargetMinutes: targets.sleepMinutes,
                    weightKg: row?.weightKg, recoveryPct: row?.whoopRecoveryPct
                )
                briefing.workouts = try metrics.workouts(on: date).map {
                    DayWorkout(id: $0.externalID, title: $0.activityName, durationMinutes: $0.durationMinutes)
                }
            }
            if sections.contains(.money) {
                let entries = try MoneyStore(context: context, calendar: calendar).entries(from: date, to: date)
                    .filter(\.isSpending)
                let rows = entries.sorted { abs($0.amount) > abs($1.amount) }.prefix(3)
                    .map { MoneyRow(id: $0.id, merchant: $0.merchant, amount: $0.amount) }
                briefing.spend = DaySpend(total: -entries.map(\.amount).reduce(0, +), rows: Array(rows))
            }
            if sections.contains(.nudges) {
                let key = WeatherCache.dayKey(date, calendar: calendar)
                briefing.nudges = PushService.shared.entries.filter { $0.day == key }
                    .sorted { $0.receivedAt < $1.receivedAt }
            }
        } catch {
            assertionFailure("Day load failed: \(error)")
        }
        briefing.dayLook = dayLook(for: briefing)
        self.briefing = briefing
        if sections.contains(.weather) { loadWeather() }
    }

    private func loadChecklist(context: ModelContext, editable: Bool) throws -> [ChecklistRow] {
        let notes = NotesStore(context: context, calendar: calendar)
        let plan = PlanStore(context: context, calendar: calendar)
        let journal = try notes.journalEntryIfPresent(on: date)
        let due = try notes.tasks(dueOn: date).compactMap { task -> DayChecklist.DueTask? in
            guard let page = try? notes.document(id: task.documentID), !page.isArchived else { return nil }
            return DayChecklist.DueTask(documentID: task.documentID, blockID: task.id, text: task.text,
                                        isChecked: task.isChecked, pageTitle: page.displayTitle)
        }
        let habits = try plan.entries(kind: .habit).map { entry in
            DayChecklist.Habit(id: entry.id, title: entry.title, createdAt: entry.createdAt,
                               streak: (try? plan.streak(for: entry, endingOn: date)) ?? 0)
        }
        return DayChecklist.rows(
            journal: journal?.blocks ?? [], journalID: journal?.id, due: due, habits: habits,
            ticked: try plan.tickedHabitIDs(on: date), day: date, editable: editable, calendar: calendar
        )
    }

    private func dayLook(for briefing: DayBriefing) -> String? {
        let weather: DayLookText.Weather? = if case .ready(let forecast) = briefing.weather {
            DayLookText.Weather(conditionSymbol: forecast.conditionSymbol, feelsLikeHighC: forecast.feelsLikeHighC,
                                rainChanceByHour: forecast.rainChanceByHour)
        } else { nil }
        let due = briefing.checklist.filter { if case .page = $0.source { return !$0.isDone } else { return false } }.count
        return DayLookText.sentence(
            weather: weather, agendaCount: briefing.agenda.count,
            firstStart: briefing.agenda.first { !$0.isAllDay }?.startDate, dueCount: due,
            currentHour: isOnToday ? calendar.component(.hour, from: .now) : nil, calendar: calendar
        )
    }

    // MARK: Weather

    private func loadWeather() {
        guard let providers else { briefing?.weather = .unavailable; return }
        let cache = WeatherCache()
        if let cached = cache.forecast(for: date, calendar: calendar), cached.isFresh(at: .now) {
            setWeather(.ready(cached))
            return
        }
        switch providers.location.access {
        case .notDetermined: setWeather(.needsLocation); return
        case .denied: setWeather(.denied); return
        case .granted: break
        }
        if case .ready = briefing?.weather {} else { setWeather(.loading) }
        let day = date
        weatherTask?.cancel()
        weatherTask = Task {
            do {
                let location = try await providers.location.currentLocation()
                guard let forecast = try await providers.weather.forecast(for: day, at: location) else {
                    if self.date == day { setWeather(.unavailable) }
                    return
                }
                cache.store(forecast, calendar: calendar)
                if self.date == day { setWeather(.ready(forecast)) }
            } catch {
                if self.date == day { setWeather(.unavailable) }
            }
        }
    }

    private func setWeather(_ state: WeatherState) {
        guard var briefing else { return }
        briefing.weather = state
        briefing.dayLook = dayLook(for: briefing)
        self.briefing = briefing
    }

    func allowLocation() async {
        guard let providers else { return }
        _ = await providers.location.requestAccess()
        loadWeather()
    }

    // MARK: Writes

    func tick(_ row: ChecklistRow) {
        guard let context, row.isEditable else { return }
        let notes = NotesStore(context: context, calendar: calendar)
        do {
            switch row.source {
            case .journal(let blockID):
                guard let page = try notes.journalEntryIfPresent(on: date) else { return }
                try toggle(blockID, on: page, notes: notes)
            case .page(let documentID, let blockID):
                guard let page = try notes.document(id: documentID) else { return }
                try toggle(blockID, on: page, notes: notes)
            case .habit(let entryID):
                // Habits keep today's rule: a tick is a record of the day it is made.
                guard isOnToday else { return }
                let plan = PlanStore(context: context, calendar: calendar)
                guard let entry = try plan.entries(kind: .habit).first(where: { $0.id == entryID }) else { return }
                try plan.toggleTick(for: entry, on: date)
            }
        } catch {
            assertionFailure("Day tick failed: \(error)")
        }
        // `didSave` reloads the screen; nothing else to do here.
    }

    private func toggle(_ blockID: UUID, on page: NoteDocument, notes: NotesStore) throws {
        let result = NoteBlockEditor.toggleCheck(page.blocks, at: blockID)
        guard result.handled else { return }
        try notes.update(page, blocks: result.blocks)
        requestSync()
    }

    /// Appends a to-do to the day's journal page, creating the page on the
    /// first add. A page that is only its blank paragraph gets the to-do in
    /// its place rather than under it.
    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context, !trimmed.isEmpty, briefing?.placement.isEditable == true else { return }
        let notes = NotesStore(context: context, calendar: calendar)
        do {
            let page = try notes.journalEntry(on: date)
            var blocks = page.blocks
            if blocks.count == 1, blocks[0].kind == .paragraph, blocks[0].isEmpty { blocks = [] }
            blocks.append(NoteBlock(kind: .todo, text: trimmed))
            try notes.update(page, blocks: blocks)
            requestSync()
        } catch {
            assertionFailure("Day add failed: \(error)")
        }
    }

    func journalPageID() -> UUID? {
        guard let context else { return nil }
        return try? NotesStore(context: context, calendar: calendar).journalEntryIfPresent(on: date)?.id
    }

    private func requestSync() {
        guard let sync else { return }
        Task { await sync.sync() }
    }
}
```

`NoteSyncing` is declared in `NotesViewModel.swift` in the app target; it is visible here.

- [ ] **Step 4: Build the app**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task6.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task6.log | head -5
```

Expected: `build exit 0`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Day/Model/DayBriefing.swift LIfeOS/Features/Day/ViewModel/DayViewModel.swift LIfeOS/App/PushService.swift
git commit -m "feat(day): the briefing value and the view model that loads it

Agenda, the checklist from the journal page with what is due and the
habits, readings, spend and nudges from the stores; the weather from
the cache or the provider afterwards; ticks and adds written back
through the store the editor uses."
```

---

### Task 7: `DayScreen`, its sections and the preview pages

**Files:**
- Create: `LIfeOS/Features/Today/View/AgendaRow.swift`, `LIfeOS/Features/Day/View/DayScreen.swift`, `LIfeOS/Features/Day/View/DaySections.swift`
- Modify: `LIfeOS/Features/Notes/View/NotesHubScreen.swift:389` (`private struct NoteEditorHost` becomes `struct NoteEditorHost`)
- Modify: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:100`

**Interfaces:**
- Consumes: Task 6's `DayViewModel`, `DayProviders` from the environment, `HairlineField`, `EditorialMasthead`, `EditorialSectionHeader`, `EditorialRow`, `EditorialFigure`, `Hairline`, `editorialCard()`, `NoteEditorHost(documentID:onOpenLinked:)`.
- Produces: `AgendaRow(event:highlighted:lineLimit:action:)` (Task 8 makes `WeekBands` use it); `DayScreen(date:onTapEvent:onAddEvent:)`; preview pages `day`, `day-past`, `day-future`, `day-far`, `day-empty`, `day-no-location`.

- [ ] **Step 1: The shared event row**

`AgendaRow.swift`:

```swift
import SwiftUI
import DesignSystem
import Persistence

/// One event as a row: `time · title · arrow.right`, with a 6pt accent dot
/// before the time when a find has matched it. The bands and the day
/// screen draw this, so an event reads the same in both.
struct AgendaRow: View {
    let event: CalendarEventSnapshot
    var highlighted = false
    var lineLimit = 2
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.half) {
                if highlighted {
                    Circle().fill(LifeOSTokens.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                EditorialRow(event.timeLabel) {
                    HStack(spacing: Space.half) {
                        Text(event.title).lineLimit(lineLimit)
                        Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold))
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.spanLabel)")
        .accessibilityHint("Opens the event")
    }
}
```

- [ ] **Step 2: The sections**

`DaySections.swift`:

```swift
import SwiftUI
import UIKit
import AppSurfaces
import DesignSystem
import Persistence

/// The weather card: the feels-like high as the figure, the condition, three
/// quiet lines, and the Wear line on a row. Or what stands in for it until
/// location is allowed.
struct WeatherCard: View {
    let state: WeatherState
    let isToday: Bool
    var onAllowLocation: () -> Void
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .needsLocation:
                notice("Weather needs your location.", action: "Allow location", onAction: onAllowLocation)
            case .denied:
                notice("Turn location on in Settings for weather.", action: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .loading:
                Text("Reading the sky…").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    .editorialCard()
            case .unavailable:
                Text("No forecast right now.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    .editorialCard()
            case .ready(let forecast):
                card(forecast)
            }
        }
    }

    private func notice(_ sentence: String, action: String, onAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(sentence).font(LifeOSType.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action, action: onAction).buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    private func card(_ forecast: DayForecast) -> some View {
        let quiet = Editorial.quietInk(scheme)
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        let wear = WearText.line(
            feelsLikeHighC: forecast.feelsLikeHighC, feelsLikeLowC: forecast.feelsLikeLowC,
            rainChanceByHour: forecast.rainChanceByHour, windKph: forecast.windKph, uvIndex: forecast.uvIndex,
            currentHour: isToday ? calendar.component(.hour, from: .now) : nil
        )
        return VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .top, spacing: Space.x2) {
                VStack(alignment: .leading, spacing: Space.half) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Self.degrees(forecast.feelsLikeHighC, digits: 0))
                            .font(Editorial.figure(64)).tracking(Editorial.figureTracking(64)).monospacedDigit()
                        Text("°").font(Editorial.figure(28))
                    }
                    .foregroundStyle(ink)
                    HStack(spacing: Space.half) {
                        Image(systemName: forecast.conditionSymbol)
                        Text(forecast.conditionName)
                    }
                    .font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                Spacer(minLength: Space.x1)
                VStack(alignment: .trailing, spacing: Space.half) {
                    Text("High \(Self.degrees(forecast.highC))° · Low \(Self.degrees(forecast.lowC))°")
                    Text(rainLine(forecast))
                    Text("Wind \(Self.speed(forecast.windKph)) · UV \(forecast.uvIndex)")
                }
                .font(LifeOSType.caption).foregroundStyle(quiet).multilineTextAlignment(.trailing)
            }
            EditorialRow("Wear", value: wear)
        }
        .editorialCard()
        .accessibilityElement(children: .combine)
    }

    private func rainLine(_ forecast: DayForecast) -> String {
        guard let wet = WearText.firstWetHour(forecast.rainChanceByHour) else { return "No rain expected" }
        let chance = Int((forecast.rainChanceByHour[wet] * 100).rounded())
        return "Rain \(chance)% from \(WearText.hourText(wet, calendar: calendar, locale: .current))"
    }

    /// Celsius in, the device's unit out, digits only; the sign is drawn beside.
    static func degrees(_ celsius: Double, digits: Int = 0) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let value = measurement.converted(to: UnitTemperature(forLocale: .current)).value
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func speed(_ kph: Double) -> String {
        Measurement(value: kph, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// The checklist: a square, the text, a quiet detail, hairlines between.
/// Ticking is a tap on the square; the text opens the page or the habits.
struct ChecklistRows: View {
    let rows: [ChecklistRow]
    var onTick: (ChecklistRow) -> Void
    var onOpen: (ChecklistRow) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Button { onTick(row) } label: {
                        Image(systemName: row.isDone ? "checkmark.square.fill" : "square")
                            .font(LifeOSType.body)
                            .foregroundStyle(row.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isEditable)
                    .accessibilityLabel(row.isEditable
                        ? "\(row.text), \(row.isDone ? "done" : "not done"), double tap to \(row.isDone ? "untick" : "tick")"
                        : "\(row.text), \(row.isDone ? "done" : "not done")")
                    Button { onOpen(row) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                            Text(row.text)
                                .font(LifeOSType.body)
                                .strikethrough(row.isDone)
                                .foregroundStyle(row.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = row.detail {
                                Text(detail).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(openHint(row))
                }
                .padding(.vertical, 10)
                Hairline()
            }
        }
    }

    private func openHint(_ row: ChecklistRow) -> String {
        switch row.source {
        case .habit: "Opens habits"
        default: "Opens the page"
        }
    }
}

/// Readings against their targets. Whole hours read as `8h`, not `8h 0m`.
struct ReadingsRows: View {
    let readings: DayReadings
    let workouts: [DayWorkout]

    var body: some View {
        EditorialRow("Steps", value: readings.steps.map { "\($0.formatted()) of \(readings.stepsTarget.formatted())" } ?? "No reading")
        EditorialRow("Sleep", value: readings.sleepMinutes.map { "\(Self.duration($0)) of \(Self.duration(readings.sleepTargetMinutes))" } ?? "No reading")
        EditorialRow("Weight", value: readings.weightKg.map { String(format: "%.1f kg", $0) } ?? "No reading")
        EditorialRow("Recovery", value: readings.recoveryPct.map { "\(Int($0.rounded()))%" } ?? "No reading")
        ForEach(workouts) { workout in
            EditorialRow(workout.title, value: Self.duration(workout.durationMinutes))
        }
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}

/// The day's spend as a figure, then up to three rows, cents exact.
struct SpendRows: View {
    let spend: DaySpend
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if spend.rows.isEmpty {
            Text("Nothing spent").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
        } else {
            EditorialFigure(label: "Spent", value: spend.total.formatted(.currency(code: "USD").precision(.fractionLength(2))), size: 44)
            ForEach(spend.rows) { row in
                EditorialRow(row.merchant, value: abs(row.amount).formatted(.currency(code: "USD").precision(.fractionLength(2))))
            }
        }
    }
}

/// That day's nudges from LIFO, text and time.
struct NudgeRows: View {
    let nudges: [InboxEntry]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if nudges.isEmpty {
            Text("Nothing from LIFO").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
        } else {
            ForEach(nudges) { nudge in
                EditorialRow(nudge.receivedAt.formatted(.dateTime.hour().minute())) {
                    Text(nudge.text).lineLimit(3)
                }
            }
        }
    }
}
```

- [ ] **Step 3: The screen**

`DayScreen.swift`:

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// One day in full, pushed: where it sits, the weather and what to wear,
/// what is on, the checklist, the readings, the spend, what LIFO said.
/// Today is the centre; a past day is a record, a day ahead a plan.
struct DayScreen: View {
    @State private var model: DayViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dayProviders) private var providers
    @Environment(\.noteSync) private var sync
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.dismiss) private var dismiss
    @State private var showDatePicker = false
    @State private var newTask = ""
    @State private var openPage: UUID?
    @State private var openHabits = false
    var onTapEvent: (CalendarEventSnapshot) -> Void
    var onAddEvent: (Date) -> Void

    init(date: Date,
         onTapEvent: @escaping (CalendarEventSnapshot) -> Void = { _ in },
         onAddEvent: @escaping (Date) -> Void = { _ in }) {
        _model = State(initialValue: DayViewModel(date: date))
        self.onTapEvent = onTapEvent
        self.onAddEvent = onAddEvent
    }

    private let calendar = Calendar.current
    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var headline: DayHeadline { DayHeadline.make(date: model.date, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                header
                if let briefing = model.briefing {
                    ForEach(briefing.sections, id: \.self) { section in
                        sectionView(section, briefing: briefing)
                    }
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
        .scrollDismissesKeyboard(.interactively)
        .background(paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openPage) { id in
            NoteEditorHost(documentID: id, onOpenLinked: { openPage = $0 })
        }
        .navigationDestination(isPresented: $openHabits) {
            PlanScreen(section: .habits, showsSections: false)
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Go to date", selection: Binding(get: { model.date }, set: {
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
            model.attach(context, providers: providers, sync: sync)
            model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.load()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Button { showDatePicker = true } label: {
                EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: model.briefing?.dayLook)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any date")
            Spacer(minLength: Space.x1)
            Button("Today") {
                withAnimation(.easeOut(duration: 0.18)) { model.goToToday() }
            }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .disabled(model.isOnToday)
            .accessibilityHint("Shows today")
            stepButton("chevron.left", direction: -1, label: "Previous day")
            stepButton("chevron.right", direction: 1, label: "Next day")
        }
    }

    private func stepButton(_ icon: String, direction: Int, label: String) -> some View {
        Button { step(direction) } label: { Image(systemName: icon) }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .accessibilityLabel(label)
    }

    private func step(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.18)) { model.step(direction) }
    }

    // MARK: Sections

    /// Numbered from the first numbered section: the weather card carries
    /// no index, so `The day` is `01` whether or not a forecast is shown.
    private func number(of section: DaySection, in briefing: DayBriefing) -> Int? {
        briefing.sections.filter { $0 != .weather }.firstIndex(of: section).map { $0 + 1 }
    }

    @ViewBuilder
    private func sectionView(_ section: DaySection, briefing: DayBriefing) -> some View {
        switch section {
        case .weather:
            WeatherCard(state: briefing.weather, isToday: model.isOnToday) {
                Task { await model.allowLocation() }
            }
        case .agenda:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "The day")
                if briefing.agenda.isEmpty {
                    Text("Nothing scheduled").font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                ForEach(briefing.agenda) { event in
                    AgendaRow(event: event) { onTapEvent(event) }
                }
                Button("Add") { onAddEvent(model.date) }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
        case .checklist:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "Checklist") {
                    if !briefing.checklist.isEmpty {
                        Text("\(briefing.checklistDone) of \(briefing.checklist.count)")
                            .font(LifeOSType.label).monospacedDigit().foregroundStyle(quiet)
                    }
                }
                if briefing.checklist.isEmpty {
                    Text(briefing.placement.isEditable ? "Nothing planned. Add a task below." : "Nothing was listed.")
                        .font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                ChecklistRows(rows: briefing.checklist, onTick: { model.tick($0) }, onOpen: open)
                if briefing.placement.isEditable {
                    HairlineField(text: $newTask, placeholder: "Add a task", glyph: "plus", submitLabel: .done,
                                  onSubmit: {
                                      model.add(newTask)
                                      newTask = ""
                                  })
                }
            }
        case .readings:
            if let readings = briefing.readings {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Readings")
                    ReadingsRows(readings: readings, workouts: briefing.workouts)
                }
            }
        case .money:
            if let spend = briefing.spend {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Money")
                    SpendRows(spend: spend)
                }
            }
        case .nudges:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(index: number(of: section, in: briefing), title: "From LIFO")
                NudgeRows(nudges: briefing.nudges)
            }
        }
    }

    private func open(_ row: ChecklistRow) {
        switch row.source {
        case .journal:
            openPage = model.journalPageID()
        case .page(let documentID, _):
            openPage = documentID
        case .habit:
            openHabits = true
        }
    }
}
```

Make `NoteEditorHost` visible: in `NotesHubScreen.swift` change `private struct NoteEditorHost: View {` to `struct NoteEditorHost: View {`.

- [ ] **Step 4: The preview pages and the fixture**

In `TodayDesignPreview.swift`:

(a) The doc comment lists the day pages: replace `day`, `day-past`, in the comment with `day` (today, every section), `day-past` (a record three days ago), `day-future` (three days ahead), `day-far` (twenty days ahead, no forecast), `day-empty` (today with nothing), `day-no-location` (location not yet allowed).

(b) Replace the two `case "day"` / `case "day-past"` lines with:

```swift
            case "day", "day-past", "day-future", "day-far", "day-empty", "day-no-location":
                NavigationStack { DayScreen(date: fixture.dayDate(for: page)) }
                    .modelContainer(page == "day-empty" ? fixture.emptyContainer : fixture.container)
                    .environment(\.dayProviders, DayProviders(
                        weather: StubWeatherProvider(),
                        location: StubLocation(access: page == "day-no-location" ? .notDetermined : .granted)))
```

(c) In `TodayFixture`, delete `pastDay` and `day` (the two `DayDetailSnapshot` properties) and add, after `init()`:

```swift
    func dayDate(for page: String) -> Date {
        let offset: Int = switch page {
        case "day-past": -3
        case "day-future": 3
        case "day-far": 20
        default: 0
        }
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// Readings, spend, habits, due tasks, the journal's to-dos and a nudge,
    /// for today and three days ago, so every day section has rows.
    private func seedDay() {
        let context = container.mainContext
        let metrics = MetricsStore(context: context, calendar: calendar)
        for (offset, steps, sleep, weight, recovery) in [(0, 8_432, 432, 77.4, 82.0), (-3, 6_120, 401, 77.6, 64.0)] {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let row = DailyMetrics(date: day)
            row.steps = steps; row.sleepMinutes = sleep; row.weightKg = weight; row.whoopRecoveryPct = recovery
            context.insert(row)
        }
        context.insert(WorkoutRecord(externalID: "run-1", start: today.addingTimeInterval(7 * 3_600), durationMinutes: 35, activityName: "Running"))
        for (offset, amount, merchant) in [(0, -4.60, "Monmouth Coffee"), (0, -48.10, "Waitrose"), (0, -9.99, "Spotify"), (-3, -23.50, "Dishoom")] {
            context.insert(MoneyEntry(date: calendar.date(byAdding: .day, value: offset, to: today)!, amount: amount, merchant: merchant))
        }
        let plan = PlanStore(context: context, calendar: calendar)
        let run = try! plan.add(kind: .habit, title: "5km run")
        _ = try! plan.add(kind: .habit, title: "Read 10 pages")
        _ = try! plan.add(kind: .habit, title: "Walk the dog")
        for offset in [0, -1, -2, -3, -4, -5] {
            try! plan.toggleTick(for: run, on: calendar.date(byAdding: .day, value: offset, to: today)!)
        }
        let notes = NotesStore(context: context, calendar: calendar)
        let groceries = try! notes.document(titled: "Groceries")!
        try! notes.update(groceries, blocks: [
            NoteBlock(kind: .todo, text: "Buy oat milk", dueDate: today),
            NoteBlock(kind: .todo, text: "Order the filter", dueDate: calendar.date(byAdding: .day, value: 3, to: today)),
        ])
        let journal = try! notes.journalEntry(on: today)
        try! notes.update(journal, blocks: [
            NoteBlock(kind: .todo, text: "Call the dentist", isChecked: true),
            NoteBlock(kind: .todo, text: "Draft the plan"),
        ])
        try! context.save()
        // The empty page shows an empty inbox too; the seed is global.
        guard !ProcessInfo.processInfo.arguments.contains("--page=day-empty") else { return }
        PushService.shared.previewSeed(entries: [
            InboxEntry(ownerID: "preview", text: "Three short nights in a row. An early one tonight would do more than any workout.",
                       trigger: "short_sleep", day: WeatherCache.dayKey(today, calendar: calendar),
                       receivedAt: today.addingTimeInterval(8 * 3_600)),
        ])
    }
```

and call `seedDay()` as the last line of `init()`. The `Groceries` task page is already created there by `notes.createNote(kind: .task, title: "Groceries")`; `NotesStore.document(titled:)` finds it. If `PlanStore.add` is not `@discardableResult` for the `_ =` lines, keep them as written.

In `HealthActivityDesignPreview.swift` line 100, add `"day-future", "day-far", "day-empty", "day-no-location"` to the array after `"day-past"`.

- [ ] **Step 5: Build the app**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task7.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task7.log | head -8
```

Expected: `build exit 0`. `DayDetailSheet` still compiles at this point; it goes in Task 8.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Today/View/AgendaRow.swift LIfeOS/Features/Day/View/DayScreen.swift LIfeOS/Features/Day/View/DaySections.swift \
  LIfeOS/Features/Notes/View/NotesHubScreen.swift LIfeOS/Features/Today/View/TodayDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(day): the day screen, its sections and six preview pages

Masthead with the day-look line, the weather card with the Wear row,
the day, the checklist with Add a task, readings, money and LIFO, each
shown by the day's placement; the editor host opens pages from here."
```

---

### Task 8: The ways in, and the sheet goes

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/DotGrid.swift:54-56`
- Test: `LifeOSKit/Tests/DesignSystemTests/DotGridTests.swift` (new)
- Modify: `LIfeOS/Features/Today/View/WeekBands.swift`, `LIfeOS/Features/Today/View/CalendarScreen.swift`, `LIfeOS/Features/Assistant/View/AssistantSheet.swift`, `LIfeOS/App/RootView.swift`, `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift`
- Delete: `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`, `LIfeOS/Features/Today/View/DayDetailSheet.swift`

**Interfaces:**
- Consumes: `DayScreen`, `AgendaRow`, `DayProviders`, `WeatherKitProvider`, `LocationOnce`, `SurfaceRoute.day`.
- Produces: `DotGrid.isOpenable(_ cell: DotCell) -> Bool` (public static); `WeekBands(model:highlighted:onTapEvent:onAddEvent:onOpenDay:)`; `CalendarScreen(... onOpenDay:)`; `RootView.openDay`.

- [ ] **Step 1: The tap rule, tested**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct DotGridTests {
    @Test func anyRealDayOpensIncludingOnesAhead() {
        let day = Date()
        #expect(DotGrid.isOpenable(DotCell(id: 1, date: day, state: .future)))
        #expect(DotGrid.isOpenable(DotCell(id: 2, date: day, state: .onTarget)))
        #expect(DotGrid.isOpenable(DotCell(id: 3, date: day, state: .today)))
        #expect(!DotGrid.isOpenable(DotCell(id: 4, date: nil, state: .blank)))
        #expect(!DotGrid.isOpenable(DotCell(id: 5, date: day, state: .blank)))
    }
}
```

Run: `cd LifeOSKit && swift test --filter DotGridTests`
Expected: compile error, `type 'DotGrid' has no member 'isOpenable'`.

In `DotGrid.swift`, replace `isTappable` with:

```swift
    /// Padding cells are layout, not days. A day ahead opens like any other:
    /// the day screen shows it as a plan.
    public static func isOpenable(_ cell: DotCell) -> Bool {
        cell.date != nil && cell.state != .blank
    }
```

change the body's `if let onTap, isTappable(cell)` to `if let onTap, Self.isOpenable(cell)`, and add `.accessibilityHint("Shows the day")` after `.accessibilityLabel(label(for: cell))` on the button.

Run: `cd LifeOSKit && swift test --filter DotGridTests`
Expected: `1 test ... passed`.

- [ ] **Step 2: The bands open the day**

In `WeekBands.swift`, add after `var onAddEvent`:

```swift
    /// Raised when the number of the band that is already open is tapped:
    /// the first tap shows the day's events, the second opens the day.
    var onOpenDay: (Date) -> Void = { _ in }
```

Change the number button's action from

```swift
            Button {
                withAnimation(.snappy(duration: 0.22)) { model.select(date) }
            } label: {
```

to

```swift
            Button {
                if isOpen {
                    onOpenDay(date)
                } else {
                    withAnimation(.snappy(duration: 0.22)) { model.select(date) }
                }
            } label: {
```

change its hint to `.accessibilityHint(isOpen ? "Opens the day" : "Shows its events")`, and replace the event row (the `ForEach(rows) { event in Button { onTapEvent(event) } label: { HStack(alignment: .center, ...) ... } .buttonStyle(.plain) .accessibilityLabel(...) }` block) with:

```swift
                    ForEach(rows) { event in
                        AgendaRow(event: event, highlighted: highlighted.contains(event.id)) { onTapEvent(event) }
                    }
```

In `CalendarScreen.swift`, add the parameter and the stored property:

```swift
    var onOpenDay: (Date) -> Void
```

in the init after `onAddEvent`: `onOpenDay: @escaping (Date) -> Void = { _ in },` and `self.onOpenDay = onOpenDay`; and the `WeekBands(...)` call becomes:

```swift
                        WeekBands(model: model, highlighted: Set(found.map(\.id)),
                                  onTapEvent: onTapEvent, onAddEvent: onAddEvent, onOpenDay: onOpenDay)
```

- [ ] **Step 3: RootView**

(a) State, beside `showMonth`:

```swift
    @State private var openDay: Date?
    @State private var locationOnce: LocationOnce?
```

(b) Delete the day-sheet block (lines 140 to 147, `.sheet(item: Binding(get: { today.detail } ...`) and its two comment lines.

(c) In the Today stack, change `onSelectDay: { today.select($0) }` to `onSelectDay: { openDay = Calendar.current.startOfDay(for: $0) }` and `onOpenToday: { today.select(.now) }` to `onOpenToday: { openDay = Calendar.current.startOfDay(for: .now) }`; add `onOpenDay: { openDay = $0 },` to the `CalendarScreen(...)` call after `onAddEvent`; and after the `$openMetric` destination add:

```swift
                    .navigationDestination(item: $openDay) { date in
                        DayScreen(date: date,
                                  onTapEvent: { eventSheet = .edit($0) },
                                  onAddEvent: { eventSheet = .create(on: $0) })
                    }
```

(d) Where `.environment(\.noteSync, noteSync)` is applied (line 233), add beside it:

```swift
        .environment(\.dayProviders, locationOnce.map { DayProviders(weather: WeatherKitProvider(), location: $0) })
```

(e) In `attachAll()`, after the `calendarSync` block, add:

```swift
        if locationOnce == nil { locationOnce = LocationOnce() }
```

(f) In `openSurfaceRoute()`, replace the Task 5 placeholder `case .day: tab = .today` with:

```swift
        case .day(let date): tab = .today; openDay = Calendar.current.startOfDay(for: date)
```

(g) Update the comment at lines 83 to 84 ("Today's agenda, the day sheet") to say "Today's agenda, the day screen".

- [ ] **Step 4: The assistant's calendar pushes the day too**

In `AssistantSheet.swift`, add `@State private var openDay: Date?` beside `eventSheet`; add `onOpenDay: { openDay = $0 },` to its `CalendarScreen(...)` after `onAddEvent`; and after the `.toolbar { ... }` block on the stack's root view add:

```swift
            .navigationDestination(item: $openDay) { date in
                DayScreen(date: date,
                          onTapEvent: { eventSheet = .edit($0) },
                          onAddEvent: { eventSheet = .create(on: $0) })
            }
```

- [ ] **Step 5: The sheet goes**

```bash
git rm LIfeOS/Features/Today/Model/DayDetailSnapshot.swift LIfeOS/Features/Today/View/DayDetailSheet.swift
```

In `TodayViewModel.swift`: delete the `detail` property and its comment; delete the `if let detail { select(detail.date) }` block in `load()` with its five comment lines; delete `select(_:)`, `clearSelection()` and `toggleHabit(id:)` with their comments (everything from the `/// Builds the day sheet's contents` comment to the end of the class). Fix the comments that name the old sheet: `AgendaCard.swift:6` ("Shared by `AgendaCard` and `DayDetailSheet`'s schedule section" becomes "Shared by `AgendaCard`, the bands and the day screen"), `EventSheet.swift:6-7` ("the same idiom `DayDetailSheet` uses for `today.detail`" becomes "the same `.sheet(item:)` idiom the shell uses elsewhere"), `TodayScreen.swift:7-8` and `15-16` ("non-future day" becomes "real day"; "only the day sheet lists everything" becomes "only the day screen lists everything"), and `TodayViewModel.swift` wherever "sheet" remains.

- [ ] **Step 6: Build, and run the whole package**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task8.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task8.log | head -8
grep -rn "DayDetailSheet\|DayDetailSnapshot\|HabitRow\|today.select\|clearSelection" LIfeOS/ LifeOSKit/ | grep -v "docs/" | head
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*(Test run with|recorded an issue)" | tail -2)
```

Expected: `build exit 0`, no grep hits, and the suite passing with the new suites counted (`DayHeadlineTests` 4, `WearTextTests` 3, `DayLookTextTests` 3, `SurfaceRouteTests` 3, `DayChecklistTests` 3, `NotesStoreJournalTests` 3, `DotGridTests` 1: 20 new, one old test removed).

- [ ] **Step 7: Commit**

```bash
git add -A LIfeOS/ LifeOSKit/Sources/DesignSystem/DotGrid.swift LifeOSKit/Tests/DesignSystemTests/DotGridTests.swift
git commit -m "feat(day): three ways into the day, and the day sheet goes

The Today grid opens any real day, days ahead included; the open band's
number on the calendar opens the day; a day link lands on it. The
providers ride the environment so the assistant's calendar pushes the
same screen. DayDetailSheet and its snapshot are deleted."
```

---

### Task 9: Gates and captures

- [ ] **Step 1: Typography and the widget build**

```bash
scripts/check-typography.sh > $OUT/typo-day.txt 2>&1
diff <(sed 's/^[^:]*://' $OUT/typo-day-base.txt | sort) <(sed 's/^[^:]*://' $OUT/typo-day.txt | sort) | grep '^>' || echo "typography: no new violations"
xcodebuild build -project LIfeOS.xcodeproj -scheme AlmanacWidgets -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-widgets-day.log 2>&1; echo "widgets build exit $?"
```

Expected: `typography: no new violations` and `widgets build exit 0`. The `String(format: "%.1f kg", ...)` line in `ReadingsRows` is a number format, not a font, and the check does not flag it.

- [ ] **Step 2: Install and capture**

```bash
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/day-briefing/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B192EA65-BAA2-4814-A298-94A2F0C8FC87
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-day-$name.png" >/dev/null; }
capture today --page=day
capture today-dark --page=day --dark
capture past --page=day-past
capture future --page=day-future
capture far --page=day-far
capture empty --page=day-empty
capture no-location --page=day-no-location
capture today-large --page=day --large
capture month --page=month
capture schedule --page=schedule
ls -la $OUT/pr-day-*.png
```

Open each with the Read tool and check against the spec:
- `today`: `TODAY · <day> <MONTH>` eyebrow, the weekday, the day-look line (`Mild and cloudy, rain from 15:00. Three things on, first at 09:00, one task due.` or the day's real agenda), the weather card with `17°`, `Partly cloudy`, `High 18° · Low 9°`, `Rain 55% from 15:00`, `Wind 12 km/h · UV 3` and `Wear  A light jacket or a sweater, an umbrella after 15:00.`; `01 The day` with three rows and `Add`; `02 Checklist` `2 of 6` with `Call the dentist` struck, `Draft the plan`, `Buy oat milk  Groceries`, `5km run  6 days` ticked, two more habits, `Add a task`; `03 Readings` four rows and `Running  35m`; `04 Money` `$62.69` and three rows; `05 From LIFO` one nudge.
- `past`: `3 DAYS AGO`, no weather card, `01 The day` `Nothing scheduled`, checklist with the habits as a record (no `Add a task`), readings `6,120 of 8,000`, money `$23.50` `Dishoom`, `Nothing from LIFO`.
- `future`: `IN 3 DAYS`, the weather card, `Programming class`, checklist with `Order the filter  Groceries`, `Add a task`, no readings, money or LIFO.
- `far`: no weather card, the agenda and the checklist only.
- `empty`: the needs-nothing state: `Nothing scheduled`, `Nothing planned. Add a task below.`, every reading `No reading`, `Nothing spent`, `Nothing from LIFO`.
- `no-location`: the `Weather needs your location.` card with `Allow location`.
- `today-large`: nothing clipped at the accessibility size.
- `month`, `schedule`: unchanged.

- [ ] **Step 3: Simulator checks**

From `--page=day`: tap the right chevron and screenshot (`TOMORROW`), tap `Today` and screenshot; tap the `Draft the plan` square and screenshot (`3 of 6`, struck); type `Water the plants` into `Add a task`, press Return, screenshot (a new row). From `--page=schedule`: tap the open band's number and screenshot (the day screen). Use the recipe in the simulator memory; if two taps in a row leave the screen unchanged, stop and say so in the PR.

---

### Task 10: Open the pull request

- [ ] **Step 1: Rebase, re-run, push**

```bash
git fetch origin && git rebase origin/main && (cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
git push -u origin feat/day-briefing
```

- [ ] **Step 2: The PR**

`gh pr create --base main --title "feat(day): one screen for any day, with weather and the day's checklist" --body-file $OUT/pr-day-body.md`, the body in the house style (`## Summary`, `## Verification`, `## Deferred minors`, the spec and plan paths, and an `## Owner's steps` section: turn on WeatherKit for the App ID in the developer portal, accept its terms, add the WeatherKit capability under Signing & Capabilities). No attribution footer.

- [ ] **Step 3: Memory**

Update `day-briefing-and-notes-brainstorm.md`: slice 1 is PR #N on `feat/day-briefing`; next is the GitHub card spec.
