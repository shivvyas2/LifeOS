# Day briefing: one screen for any day

Decided 2026-10-06 with the owner, from two reference screens (a bold-weekday
checklist planner and a soft project dashboard) and the question "what would
Jarvis tell me about this day":

- **The screen is a morning briefing for today.** Other days show the same
  frame with what is known: a record for a past day, a preview for a future
  one.
- **It replaces the day sheet.** One pushed `DayScreen` is the only day view;
  `DayDetailSheet` goes.
- **It stays on the editorial theme.** The owner said "neo-brutalism" and
  then, as on 2026-10-05, chose paper and ink once the references were
  compared. The first reference's bold uppercase weekday and checkbox list
  come in as type and a row style, not as a second visual language.
- **Slice 1 runs on what the phone already knows, plus weather.** Agenda,
  the day's own checklist, tasks due that day, habits, readings, workouts,
  spend and that day's LIFO nudges, with WeatherKit weather and a tested
  Wear line. The GitHub project card and the email feed are later slices
  with their own specs: the app has no Google sign-in at all today (Google
  calendars arrive through iOS Settings and EventKit) and no GitHub, weather
  or location code.
- **The day's goals are the day's journal page**, as a checklist typed right
  on the screen, joined by tasks from other pages due that day and by
  habits.
- **Three ways in**: the Today dot grid (future days become tappable), the
  open band's number on the calendar's Weekly view, and a day link.

Everything follows the rules already set: paper is `LifeOSTokens.canvas`, ink
is `primaryText`, hairlines are `Editorial.rule`, quiet text is
`Editorial.quietInk`, the accent only for today and anything live, every
button an `.editorial(role)` style, fonts only from `LifeOSType` and
`Editorial.figure` / `Editorial.headline`, no per-module palette. Find and
rules never call a model; the cost of this screen is zero beyond WeatherKit's
free tier.

## 1. The screen

`DayScreen(date:)` in `LIfeOS/Features/Day/View/DayScreen.swift`, with
`DayViewModel` in `LIfeOS/Features/Day/ViewModel/` and the loader and
providers in `LIfeOS/Features/Day/Model/`. The screen holds `@State private
var date` seeded from the init so the header can step days without a new
push.

Top to bottom, on paper, inside the Today tab's `NavigationStack` with the
system bar holding only Back:

1. **Header row.** `EditorialMasthead` as a button that opens the Go-to-date
   sheet the calendar already has; trailing, in one row: `Today` as
   `.editorial(.secondary, size: .compact)`, disabled on today, then the two
   chevron buttons. A horizontal swipe steps a day too.
   - `DayHeadline.make(date:now:calendar:locale:)` in `DesignSystem` owns
     the wording, tested. Eyebrow: `TODAY · 6 OCTOBER`, `YESTERDAY · 5
     OCTOBER`, `TOMORROW · 7 OCTOBER`, `IN 3 DAYS · 9 OCTOBER`, `3 DAYS AGO
     · 3 OCTOBER` (two to six days either side), and past that the date
     alone, with the year when it is not this year: `14 JANUARY 2027`.
     Title: the weekday, wide (`Tuesday`), in the masthead's headline face,
     which is the first reference's bold weekday in this theme. Detail: the
     day-look sentence (§2), or nothing when nothing is known.
2. **Weather card** (§2), only on days the forecast reaches.
3. **01 The day.** The agenda for the day as the rows the week bands draw
   (`time · title · arrow.right`, `all day` first), lifted into one
   `AgendaRow` in the app so the bands and this screen cannot drift. A row
   opens the event sheet; `Add` as `.editorial(.secondary, size: .compact)`
   creates one on this day. Empty: `Nothing scheduled` in quiet ink.
4. **02 Checklist** (§3), with the trailing count `3 of 7`.
5. **03 Readings.** Four `EditorialRow`s from that day's `DailyMetrics`
   against `UserGoals.targets`: `Steps` `8,432 of 10,000`, `Sleep` `7h 12m
   of 8h`, `Weight` `77.4 kg`, `Recovery` `82%`; a reading with no value
   reads `No reading`. Then that day's workouts as rows, `activityName ·
   duration`, from `MetricsStore.workouts(on:)`.
6. **04 Money.** The day's spend (the sum of outflows) as an
   `EditorialFigure` with cents exact, then up to three rows `merchant ·
   amount`, from `MoneyStore.entries(from:to:)` for the day. Empty:
   `Nothing spent`.
7. **05 From LIFO.** That day's nudges from the notification inbox
   (`PushService.shared.entries` where `day` is this day), as rows `text ·
   time`. Empty: `Nothing from LIFO`.
8. **`Go back`** as `.editorial(.secondary, fullWidth: true)`.

Which sections a day shows is a tested rule, `DaySections.visible(for:)` in
`DesignSystem`, from a `DayPlacement` (`past`, `today`, `future(days:)`):

| Placement | Weather | The day | Checklist | Readings | Money | From LIFO |
|---|---|---|---|---|---|---|
| Past | no | yes | yes, a record | yes | yes | yes |
| Today | yes | yes | yes, editable | yes | yes | yes |
| Future, within the forecast | yes | yes | yes, editable | no | no | no |
| Future, beyond it | no | yes | yes, editable | no | no | no |

The forecast reaches ten days (`DaySections.forecastDays = 10`). Hidden
sections are absent, not empty.

Accessibility: section headers are headers; rows carry the labels the bands
and the Today tiles already use; the checkbox rows read `Read 10 pages, not
done, double tap to tick` on editable days and `Read 10 pages, done` on a
record.

## 2. Weather and the Wear line

### Fetching

- `WeatherProviding` (app): `func forecast(for day: Date, at: CLLocation)
  async throws -> DayWeather?`. `WeatherKitProvider` asks
  `WeatherService.shared` for `.daily` and `.hourly` and maps the day.
  `StubWeatherProvider` (DEBUG) answers from a fixture.
- `DayWeather` in `AppSurfaces` (Codable, Sendable), so a widget can read it
  later: `day`, `conditionSymbol` (SF Symbol name), `conditionName`,
  `highC`, `lowC`, `feelsLikeHighC`, `feelsLikeLowC`, `rainChanceByHour`
  (24 values, 0 to 1, from the day's start), `windKph`, `uvIndex`,
  `sunrise`, `sunset`, `fetchedAt`.
- `WeatherCache` (app): per-account `UserDefaults` JSON keyed by day,
  fresh for 60 minutes; the loader reads the cache first and refetches in
  the background when stale. One call per day shown per hour at most, far
  inside WeatherKit's free 500,000 calls a month.
- Location: `LocationOnce` (app) wraps `CLLocationManager`, asks for
  when-in-use access the first time the Day screen opens, and returns one
  fix with reduced accuracy (a city is enough for weather). Until access is
  granted the card is a paper card reading `Weather needs your location.`
  with `Allow location` as `.editorial(.primary, size: .compact)`; if access
  is denied it reads `Turn location on in Settings for weather.` with `Open
  Settings`. Everything else on the screen works without it. The
  coordinates go only to Apple's WeatherKit; nothing about location or
  weather reaches LifeOS's servers.
- `Config/App-Info.plist` gains `NSLocationWhenInUseUsageDescription`:
  "LifeOS uses your location for the weather on your day screen."
  `LIfeOS/LIfeOS.entitlements` gains `com.apple.developer.weatherkit`
  (`["dummy"]`, as WeatherKit requires). The App ID needs the WeatherKit
  capability turned on in the developer portal; that is the owner's step
  (§7).

### The card

An `editorialCard()`: left, the feels-like high in `Editorial.figure(64)`
with the degree sign in `Editorial.figure(28)` beside it, under it the
condition symbol and name in `LifeOSType.secondary`; right, three quiet
lines: `High 18° · Low 9°`, `Rain 40% from 15:00` (or `No rain expected`),
`Wind 12 km/h · UV 3`; under both, a hairline and one `EditorialRow("Wear",
value:)` with the Wear line. Temperatures and wind are shown through
`Measurement` formatting for the device's locale; the rules below work in
Celsius and km/h. Dark mode changes nothing but the paper.

### The Wear line

`WearText.line(feelsLikeHighC:feelsLikeLowC:rainChanceByHour:windKph:uvIndex:
wakingHours:locale:)` in `DesignSystem`, tested. `wakingHours` defaults to
`7..<22`. The rule, applied in order, joined with commas, first letter
capitalised, a full stop at the end:

| Feels-like high | Wear |
|---|---|
| below 5 | `coat, hat and gloves` |
| 5 to 11 | `a warm jacket` |
| 12 to 17 | `a light jacket or a sweater` |
| 18 to 24 | `a t-shirt` |
| 25 and up | `light clothes, and carry water` |

- If the feels-like low is more than 10 degrees under the high and the
  high is 12 or more: add `layers for the morning`.
- If any waking hour has a rain chance of 0.4 or more: add `an umbrella`,
  with `after three` style wording when the first such hour is after the
  current hour on today (`an umbrella after 15:00` on other days, the hour
  formatted for the locale).
- If `windKph` is 30 or more: add `a windproof layer`.
- If `uvIndex` is 6 or more: add `sunscreen`.

Examples the tests pin: `A light jacket or a sweater, an umbrella after
15:00.`; `Coat, hat and gloves, a windproof layer.`; `A t-shirt, sunscreen.`;
`Light clothes, and carry water, sunscreen.`

### The day-look sentence

`DayLookText.sentence(weather:agendaCount:firstStart:dueCount:now:calendar:
locale:)` in `DesignSystem`, tested, up to three clauses joined into two
sentences:

1. Weather: the condition in plain words with the temperature band:
   `Cool and clear`, `Mild and cloudy`, `Warm and sunny`, `Cold and wet`
   (bands: cold below 5, cool 5 to 11, mild 12 to 17, warm 18 to 24, hot 25
   and up; the word after `and` from the condition symbol: `clear`,
   `cloudy`, `wet`, `snowy`, `windy`, `foggy`), then `, rain from 15:00`
   when the first wet waking hour is ahead. Omitted with no weather.
2. Agenda: `Nothing on`, `One thing on at 09:00`, `Three things on, first at
   09:00`.
3. Tasks: omitted at zero, `one task due`, `two tasks due`.

`Cool and clear, rain from 15:00. Three things on, first at 09:00, two tasks
due.` No model writes this line; LIFO can elaborate when asked.

## 3. The checklist

### Where the rows come from

`DayChecklist.rows(journal:due:habits:ticked:placement:)` in `Persistence`,
tested, merges three sources into `[ChecklistRow]` in this order:

1. **The day's own list**: the `todo` blocks of that day's journal page
   (`NoteDocument` with `kind == .journal` and `entryDate` on the day), in
   page order. Other block kinds on the page are not shown; the page is one
   tap away.
2. **Due that day**: `NoteTask` rows whose `dueDate` falls on the day and
   whose `documentID` is not the journal page, in `documentUpdatedAt` then
   `sortOrder` order, each with its page title in quiet ink after the text.
3. **Habits**: `PlanEntry(kind: .habit)` created on or before the day, with
   `isDone` from `PlanStore.tickedHabitIDs(on:)`.

```swift
public struct ChecklistRow: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case journal(blockID: UUID)
        case page(documentID: UUID, blockID: UUID, title: String)
        case habit(entryID: UUID)
    }
    public let id: String       // "journal|<block>", "page|<doc>|<block>", "habit|<entry>"
    public let source: Source
    public let text: String
    public let isDone: Bool
    public let isEditable: Bool // false on a past day
}
```

### The rows

The first reference's list: a 20pt square (`square` / `checkmark.square.fill`
in ink), the text in `LifeOSType.body`, done rows in quiet ink with a
strikethrough, hairlines between rows. A page row shows its page title after
the text in `LifeOSType.caption` quiet ink. A habit row shows its streak,
`6 days`, the same way. Tapping the square ticks; tapping the text opens the
page (journal or other) in the editor, pushed in the same stack through
`NoteEditorHost`, which stops being private to `NotesHubScreen`. Habit text
opens the Habits screen.

Under the list, on editable days, `HairlineField(placeholder: "Add a task")`
with `glyph: "plus"` and submit label `.done`: Return appends a `todo` block
to the journal page, creating the page on that first add, and clears the
field. On a past day the field is absent and the rows are a record.

Empty states: `Nothing planned. Add a task below.` on editable days;
`Nothing was listed.` on a past day, both in quiet ink.

### Writing through the store

- Ticking a journal or page row: `NoteBlockEditor.toggleCheck(blocks, at:)`
  on the page's blocks, then `NotesStore.update(_:blocks:)` and a sync
  request through the `noteSync` environment, the path the editor takes.
  The index rebuilds on save, so a page row's `NoteTask` follows.
- Ticking a habit: `PlanStore.toggleTick(for:on:)`, on today only (the rule
  `TodayViewModel.toggleHabit` enforces today moves here).
- Adding: `NotesStore.journalEntry(on:in:)` then `update` with the block
  appended.
- Two `NotesStore` changes, both tested: `journalEntryIfPresent(on:) ->
  NoteDocument?` reads without creating, so opening a past day never leaves
  an empty page behind; and `journalEntry(on:in:)` files the page in the
  `Journal` folder of Areas that `PlanNoteMigration` seeds (creating that
  folder if it is missing), which fixes journal pages landing beside the
  folder rather than in it. `NotesStore.tasks(dueOn:) -> [NoteTask]` is the
  due query.

## 4. Data

`DayBriefing` (app, `Equatable`) is everything the screen draws:

```swift
struct DayBriefing: Equatable {
    let date: Date                      // start of day
    let placement: DayPlacement
    var weather: WeatherState           // .hidden, .needsLocation, .denied, .loading, .ready(DayWeather), .unavailable
    var agenda: [CalendarEventSnapshot]
    var checklist: [ChecklistRow]
    var readings: DayReadings?          // steps, sleep, weight, recovery, each with its target
    var workouts: [WorkoutRecord]
    var spend: DaySpend?                // total and up to three rows
    var nudges: [InboxEntry]
    var dayLook: String?
}
```

`DayViewModel` (`@Observable @MainActor`) takes the `ModelContext`, a
`WeatherProviding` and a `LocationProviding` in `attach`, loads the briefing
for its `date` on appear and again on `ModelContext.didSave` (the way the
Today tab's day select reloads), and exposes `tick(_ row:)`, `add(_ text:)`,
`step(_ days: Int)`, `goToToday()`, `goTo(_:)`. Loading the stores is
synchronous on the main actor as elsewhere; the weather arrives afterwards
and only that part of the briefing changes. `DayDetailSnapshot`,
`DayDetailSheet` and `TodayViewModel.select`, `detail`, `clearSelection`
and `toggleHabit` are deleted; the Today preview's `day` and `day-past`
pages move to the new screen.

## 5. Ways in

- **Today tab.** `RootView` gains `@State private var openDay: Date?` and
  `.navigationDestination(item: $openDay) { DayScreen(date: $0, ...) }` in
  the Today stack, beside the calendar destination. `TodayScreen.onSelectDay`
  and `onOpenToday` set `openDay`; the root-level day sheet goes.
  `DotGrid.isTappable` stops excluding `.future`, so a day ahead opens as a
  preview; its accessibility hint reads `Shows the day`.
- **Calendar.** `WeekBands` gains `onOpenDay: (Date) -> Void`: tapping the
  number of the band that is already open calls it (the first tap on a
  closed band still opens the band). `CalendarScreen` takes `onOpenDay` and
  forwards it. `RootView` passes `{ openDay = $0 }`; `AssistantSheet` pushes
  `DayScreen` in its own stack the same way.
- **Day link.** `SurfaceRoute` gains `case day(Date)`, whose URL is
  `almanac://day?date=2026-10-06`; `init?(url:)` accepts a `date` query on
  the `day` host and nothing else, and the other routes keep rejecting any
  query. `RootView.openSurfaceRoute()` handles it with `tab = .today;
  openDay = date`. Nothing emits the link yet; the widget PR will.
- The event sheet and the editor push are the ones `RootView` already owns:
  `DayScreen` takes `onTapEvent`, `onAddEvent` and uses `NoteEditorHost` for
  pages.

## 6. Verification

- Tests: `DayHeadlineTests` (every placement, the year boundary, the
  `IN 3 DAYS` and `3 DAYS AGO` edges at two and six days),
  `DaySectionsTests` (the table in §1), `WearTextTests` (each band, the
  layers rule, the umbrella hour on today and on another day, wind, UV, and
  the four pinned examples), `DayLookTextTests` (each clause present and
  absent, the two-sentence join), `DayChecklistTests` (the merge order, a
  journal to-do not duplicated as a due row, habits created after the day
  excluded, nothing editable on a past day), `SurfaceRouteTests` (the day
  link parses, a day link with a bad date fails, `today` with a query still
  fails), `NotesStoreJournalTests` (`journalEntryIfPresent` creates nothing,
  `journalEntry` lands in the Journal folder and creates it when missing,
  `tasks(dueOn:)` spans the day).
- `scripts/check-typography.sh` reports nothing new versus the base.
- Builds: the app and `AlmanacWidgets` (it links `AppSurfaces`, which
  changes).
- Preview pages in `TodayDesignPreview`, each with `--dark`: `day` (today,
  every section, the stub forecast), `day-past` (`--select=` three days ago,
  a record, no weather), `day-future` (three days ahead: weather, the day,
  the checklist), `day-far` (twenty days ahead: no weather card),
  `day-empty` (today with nothing anywhere), `day-no-location` (the
  needs-location card). The stub provider and a stub location mean no
  entitlement is needed to capture.
- Simulator: open a day from the Today grid, step with the chevrons, tick
  a task, add a task and see it in Notes, open the day from the calendar's
  open band.

## 7. Delivery

One PR, `feat/day-briefing`, planned from this spec and cut from `main`
after PR #25 (the calendar find-and-ask) merges, because the calendar entry
builds on that PR's `WeekBands` and `CalendarScreen`. The owner's steps
before it can run on a device: turn on WeatherKit for the App ID in the
developer portal and accept its terms, and add the WeatherKit capability in
the target's Signing & Capabilities. The build and the captures do not need
them.

Then, as separate specs in this order: the GitHub project card (commits
that day, the repo with the latest commits, its open issues or milestone,
a token or sign-in in Settings), and the email feed (a Google sign-in with
Gmail read access, on-device picking by the device model, nothing leaving
the phone).

## Out of scope

- GitHub, email, and any new server work.
- Historical weather for past days.
- A day widget or Lock Screen surface; the link in §5 is for them.
- The Today tab's own layout, the calendar's Monthly and Weekly bodies, and
  the Notes redesign and tutorial, which get their own spec.
- Notifications settings; the server nudge job that never fires for real
  users (it reads tables the app does not write) is a separate fix.
