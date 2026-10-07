# A Today you arrange

Decided 2026-10-07 with the owner, who asked that "the user can select what
component they want here and how to arrange", for example "the dot calendar
as first thing", with the GitHub card and the tasks for today on Today too.
The important-mail inbox (the Gmail slice) and music for focus and workouts
come after this, each with its own spec.

Decisions, in the order they were made:

- **Arranging happens in place**, by long-press, the way the Home Screen
  does: modules wobble, a minus hides one, a drag moves one, a tray adds one
  back. Chosen over an Edit sheet and over a Settings page.
- **iPad arranges two lists**, the left and right columns, and a module can
  be dragged across. The phone shows the left column then the right as one
  list.
- **The catalog:** Next up, Month (the dot calendar), Today's tasks, GitHub,
  Scheduled workout, Steps, Sleep, Weight, Recovery, Weather, Spent today,
  From LIFO. Inbox joins with the Gmail slice.
- **Each stat tile is its own module.** Tiles that sit next to each other
  share a two-up row on a phone, so the grid still reads as a grid.
- **Today's tasks is the day screen's checklist:** today's journal to-dos,
  tasks due today (and, new, overdue ones, marked), and habits, ticked in
  place, with `Add a task`, under a `3 of 7` count.
- **The layout is kept per device, per account**, in
  `UserDefaults.currentAccount`. iPhone and iPad keep their own.

The masthead (greeting, date, streak) stays fixed at the top and is not a
module. Everything follows the rules already set: paper, ink, hairlines,
quiet ink, the accent only for today and anything live, every button
`.editorial(role)`, fonts only from `LifeOSType` and `Editorial`, no
per-module palette, no model calls, no new server work.

## 1. The layout

### The value, in `DesignSystem`

- `TodayModule: String, Codable, CaseIterable`: `nextUp`, `month`, `tasks`,
  `github`, `scheduledWorkout`, `steps`, `sleep`, `weight`, `recovery`,
  `weather`, `spentToday`, `fromLifo`. Each has a `title` for the tray and
  VoiceOver (`Next up`, `Month`, `Today's tasks`, `GitHub`, `Scheduled
  workout`, `Steps`, `Sleep`, `Weight`, `Recovery`, `Weather`, `Spent today`,
  `From LIFO`) and `isTile` (true for the four stats).
- `TodayLayout: Codable, Equatable` holds `left: [TodayModule]`,
  `right: [TodayModule]`, and derives `hidden` as every module in neither.
  Tested operations:
  - `move(_:toColumn:at:)`, within a column or across;
  - `hide(_:)`, which removes it from its column;
  - `add(_:to:)`, to the end of a column; `add(_:)` without a column picks
    the shorter one (counting a tile as half);
  - `moveUp(_:)` and `moveDown(_:)`, which cross from the end of the left
    column to the start of the right and back (for VoiceOver);
  - `phoneOrder`: `left + right`;
  - `rows(for: [TodayModule])`: groups consecutive tiles into pairs, so
    `[month, steps, sleep, weight, nextUp]` draws as `month`,
    `[steps, sleep]`, `[weight]`, `nextUp`.
- **The default** is the approved iPad estate arrangement: left `nextUp,
  month, tasks, scheduledWorkout`; right `steps, sleep, weight, recovery`.
  `github`, `weather`, `spentToday`, `fromLifo` start hidden. `github` is
  added to the end of the left column the first time GitHub connects, once
  (a `today.layout.githubOffered` flag), so connecting it shows it.

### Saving

JSON under `today.layout` in `UserDefaults.currentAccount`, written on every
change. Decoding drops names it does not know (a newer build's module read
by an older one) and keeps hidden any module the saved layout never had (a
module a newer build adds, like Inbox, arrives in the tray, never pushed
into someone's arrangement). No saved layout means the default.

## 2. Drawing Today

`TodayScreen` stops hard-coding its body. Under the masthead it draws the
layout: on a phone `rows(for: phoneOrder)` in one column; on iPad the two
columns side by side as now (left capped at 520), each `rows(for:)` its own
list. Each module draws with the view it already has or the day screen's:

| Module | View | When there is nothing |
|---|---|---|
| Next up | `AgendaCard` | its existing connect and empty states |
| Month | `MonthCalendarView` | always draws |
| Today's tasks | `ChecklistRows` with `Add a task`, under `EditorialSectionHeader(title: "Today's tasks")` with `3 of 7` | `Nothing planned. Add a task below.` |
| GitHub | `ProjectRows`, header `Project` with the repo | not connected: hidden outside arranging; while arranging a ghost row with `Connect` that opens Settings |
| Scheduled workout | the existing card | not drawn when nothing is scheduled (as now) |
| Steps, Sleep, Weight, Recovery | the existing tile | the existing ghosted sample figures |
| Weather | `WeatherCard` | its location prompt |
| Spent today | `SpendRows` | `Nothing spent` |
| From LIFO | `NudgeRows` | `Nothing from LIFO` |

The `No health data yet` prompt stays where it is drawn now, above the first
tile, whenever any tile is shown and nothing is connected.

### Data

Today hosts a `DayViewModel` for today, the one behind the day screen. It
already loads the checklist, weather, spend, nudges and the GitHub card, so
Today and the day screen always agree, and ticks and `Add a task` go through
the same writes. It loads only the parts whose modules are showing: with
Weather hidden there is no location request and no forecast call; with
GitHub hidden, no GitHub call. (`DayViewModel.load` gains a
`sections: Set<DaySection>` override for this; the day screen passes
nothing and keeps its own.)

### Overdue tasks

`DayChecklist.rows` gains overdue tasks for today only: open to-dos with a
due date before today on live pages, after today's due tasks and before
habits, oldest first, each with detail `overdue · <page title>`. A tested
rule; it shows on Today and on the day screen for today alike.

## 3. Arranging

- **Entering:** a long-press of 0.5 s on any module, with a light haptic.
  The masthead's eyebrow reads `Arranging Today`; `Done`
  (`.editorial(.primary, size: .compact)`) appears top right.
- **While arranging,** each module:
  - wobbles (±1.2°, alternating phase), or with Reduce Motion shows a dashed
    hairline outline instead;
  - has a minus button at its top-left corner (`Hide <title>`);
  - drags: `TodayModule` is `Transferable`; each column is a
    `dropDestination` that inserts at the drop point; the others make room.
    On iPad a module drops into either column.
  - does not respond to taps meant for its content (no ticks, no day opens);
    scrolling still works.
- **The tray:** under the last module, `Add to Today` and a wrap of chips,
  one per hidden module (`.editorial(.secondary, size: .compact)`, `+
  Weather`). A tap adds it (`add(_:)`); a chip can also be dragged into
  place. Under the chips, `Reset to default` (`.editorial(.quiet)`) with a
  confirmation.
- **Leaving:** `Done`, a tap on empty canvas, or switching tabs. Each change
  is already saved.
- **Accessibility:** every module carries VoiceOver actions `Move up`, `Move
  down`, `Move to other column` (iPad) and `Hide`, available whether or not
  arranging; tray chips read `Add Weather`. The wobble is decoration and is
  hidden from VoiceOver.
- **A first-time hint:** a card under the masthead, `Long-press anything to
  rearrange Today.`, with a close button, shown until the first arrange or
  its close (`today.layout.hintSeen`).

## 4. Verification

- Package tests:
  - `TodayLayoutTests`: the default; move within and across; hide and add;
    `add` to the shorter column; `moveUp`/`moveDown` crossing columns;
    `phoneOrder`; `rows(for:)` pairing tiles; decoding drops unknown names
    and keeps new modules hidden; reset; GitHub offered once.
  - `DayChecklistTests`: overdue tasks appear for today only, after today's
    due tasks, oldest first, with their detail; a ticked one drops out;
    archived pages excluded.
- `scripts/check-typography.sh` reports nothing new; the app and the
  package for macOS build.
- Preview pages, light and dark: `today-custom` (Month first, Today's tasks,
  GitHub, two tiles), `today-arranging` (jiggle mode with the tray),
  `today-ipad-custom` (both columns), on the phone and on the private iPad
  simulator.
- UI tests in `LIfeOSUITests` on the preview: long-press, hide Weather, add
  it back from the tray, drag Month above Next up; and the VoiceOver
  `Move up` action.

## Out of scope

- Syncing the layout between devices.
- The Inbox module (the Gmail slice adds it to the catalog, hidden).
- Music for focus and workouts.
- Widgets or the Watch following the layout.
- More than two columns, or resizing a module.
