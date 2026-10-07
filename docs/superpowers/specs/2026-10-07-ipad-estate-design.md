# iPad: the pane, not a widened phone

A design for the five hub screens on a regular-width pane, and for the dot
calendar's place on Today everywhere. Decided with Shiv on 2026-10-07 from
captures of the current build on a 13-inch iPad in portrait.

## 0. What the captures showed

The app already lays out in regular width: a 32pt gutter, a 124pt rail
inset, a 1060pt cap for single columns, four stat columns, a two-column
Today, a three-column Notes. Five screens still stop short of the pane:

- **Today.** The left column is capped at 520pt and holds the greeting, the
  agenda and then the dot month, so the month lands under the fold. The
  right column is four tall stat tiles with one figure each and nothing
  beneath them; the lower half of the pane is empty.
- **Day.** One column stretched across the 1060pt cap: the weather card,
  the agenda rows and every checklist row span the pane with the text at
  the far left and the value at the far right.
- **Weekly calendar.** The bands span the width, but a closed day still
  shows a `1 event` tag where the events themselves would fit.
- **Money.** The section's cards fall into two adaptive columns that do not
  line up (a tall gap under `Spent`), and one section fills a third of the
  pane.
- **Health.** One capped column: two small tiles on the left of a four-wide
  row, the big cards full width.

Notes and the editor are already a library, a shelf and a page side by
side; Activity already uses two columns. Neither changes here.

## 1. Rules for every regular-width screen

- **Grids fill the pane; reading columns take the measure.** A grid of
  tiles, cards or dots fills whatever width it is given. A column of rows
  that read label-left, value-right caps at the reading measure, and sits
  leading, after the rail inset, like every other hub. `LayoutMetrics`
  gains `readingWidth`: 760 in regular width, `.infinity` in compact.
  `maxContentWidth` (1060) stays for everything that is neither.
- **The phone layout does not change.** Every rule below is behind
  `layout.isRegular`; the compact arrangement is what ships today, except
  where section 2 says otherwise (the month's place, which is a decision for
  both widths).
- **Nothing new in colour or type.** Paper, ink, hairlines, quiet ink, the
  accent only for today and anything live; fonts from `LifeOSType` and
  `Editorial`; `scripts/check-typography.sh` reports nothing new.
- **Numbers live in `LayoutMetrics`**, not in views: any new width, column
  count or spacing a screen needs in regular width is a field there.

## 2. Today

**The dot month is the first thing on the screen, on every width.**

Compact (phone), top to bottom: the month (its own header: the day figure,
`OCTOBER 2026`, the weekday, then the dot grid); the greeting masthead as it
is today (`TODAY · WEDNESDAY, OCT 7`, `Good morning`, the streak); `Next
up`, the day's agenda field; the scheduled workout; the health prompt when
nothing is connected; the stat tiles in two columns; `Upcoming`.

Regular (iPad), two columns:

- **Left column**, capped at 520pt as now: the month, then `Next up`, then
  the scheduled workout.
- **Right column**, the rest of the pane: the greeting masthead; the health
  prompt when nothing is connected; the four stat tiles in one row of four
  **short tiles** (eyebrow, figure and unit, the trend arrow; no chart
  area, so a tile is as tall as its figure needs, not a card with an empty
  body); then `Upcoming`, the next days' events as today.

`AgendaCard` splits into the two views it already draws internally, `Next
up` (the field with the day's events, `Add`, and the connect and denied
states) and `Upcoming` (the card of the next days' events), so Today can
place them in different columns. On the phone they stack exactly as the one
card did. `TrendStatTile` gains a `compact` form for the row of four.

The health prompt keeps its place above the tiles: it says why they are
ghosted, so it stays beside them.

## 3. Day

In regular width the day keeps its one column (the sections are a
sequence, and two columns would break the numbering) but takes the reading
measure: the masthead, the weather card and every section cap at
`readingWidth` and sit leading after the rail inset. Rows stop spanning the
pane. Nothing else changes; the phone is untouched.

## 4. Weekly calendar

In regular width every band shows its events as rows (`AgendaRow`, the same
rows the open band draws), and the `N events` tag goes. The selected day
is still the one with `Add` under its rows, the day number still opens the
day screen, and a tap on another day's number still selects it. A day with
nothing scheduled shows nothing under its number unless it is the selected
one, which reads `Nothing scheduled` as today. The month view is unchanged.
The phone keeps the tags.

## 5. Money

In regular width the screen shows **two sections side by side**: the one
chosen in the `01` to `06` switch on the left, and the next one in order on
the right (`06 Recent` is followed by `01 In and out`). Choosing a section
puts it on the left; the right follows. Each half is one column of that
section's cards, stacked with equal spacing, so the cards line up and the
staggered gap goes. Section headers inside each half are unchanged. The
`Add` action, the masthead figure and the switch stay where they are.

On the phone nothing changes: one section at a time, the switch above it.

`MoneySection` moves into `DesignSystem` (as `NotesScope` did; it is six
cases and their titles) and gains a tested `next` (the companion in order,
wrapping), so the pairing is one rule, not a view's arithmetic.

## 6. Health

In regular width: the small tiles (`Recovery`, `Calories`, `HRV`, `Resting
HR` and their like) sit four across, using `layout.statColumns`; the large
cards (`Sleep` and any other full-width card in the segment) sit two-up in a
two-column grid when the segment has two or more of them, and alone at full
width when it has one. The readings field, the week strip and the
`Health | Fitness` switch are unchanged. The phone is untouched.

## 7. Verification

- Tests: `LayoutMetricsTests` (the regular and compact values, including
  `readingWidth`); `MoneySectionTests.nextWrapsFromRecentToInAndOut`; the
  existing `TodayHeadline`, `DayHeadline`, `WeekBands` and `DotGrid` tests
  stay green.
- `scripts/check-typography.sh` reports nothing new versus the baseline.
- Builds: the app for iPhone and iPad simulators, and `AlmanacWidgets`
  where `DesignSystem` changes.
- Captures on the private iPad simulator `CalendarAsk iPad 13`
  (`90F31CB7-2D45-488A-A9E0-8F8CC597B3B9`, iOS 26.2, 13-inch, portrait and
  landscape): `today`, `today-empty`, `day`, `day-past`, `schedule`,
  `money`, `health`, each with `--dark` where the page supports it. The
  same pages on `CalendarAsk iPhone 17` to show the phone unchanged except
  for the month's new place on Today.
- Simulator: on the iPad, tap a dot and see the day open; choose `02 Where
  it went` on Money and see it move left with `03` beside it; tap a day
  number on Weekly and see the day open. If two taps in a row leave the
  screen unchanged, stop and say so in the PR.

## 8. Delivery

One PR, `feat/ipad-estate`, cut from `main` at 41da473 and independent of
the Notes PRs (#27 and the editor branch touch no file here except
`TodayDesignPreview`, where a rebase resolves the fixture seeds).

## Out of scope

- Landscape-specific arrangements beyond what the two-column rules give;
  Stage Manager panes narrower than regular width (the compact metrics
  already apply there).
- Notes, the editor, Activity, Life and Plan screens.
- The rail itself and the navigation bar.
- A third column on the widest panes.
