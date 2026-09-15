# Agenda widget: calendar on the Lock Screen and Home Screen

Date: 2026-09-15. Status: approved design, ready for planning.

## Goal

Show the user's calendar on the two surfaces iOS offers outside the app:

- A Lock Screen rectangular widget listing the next events, rolling forward
  as each one ends, with an inline variant for the single next event.
- A Home Screen medium and large widget showing the seven-day week strip
  with colored event chips per day. Large adds today's list under the strip.

The reference photo shows a full-width week strip on the Lock Screen. That
size is not a Lock Screen widget family; apps that show it bake the strip
into a wallpaper image. Lock Screen slots remain inline, circular and
rectangular in iOS 27. This design ships what a widget can honestly do and
leaves a generated wallpaper as separate, unscheduled work.

## Non-goals

- Generated calendar wallpaper.
- Real source calendar colors. `CalendarEvent` does not store a color and
  adding a field is a SwiftData migration. Chips use a stable pastel per
  calendar name.
- Watch complications for events. The Watch payload is untouched.
- Editing or creating events from the widget.

## Data flow

### Envelope

New value type `AgendaSnapshot` in the `AppSurfaces` package, beside
`SurfaceSnapshot`. AppSurfaces has no dependencies, so the events inside are
plain Codable values, not `CalendarEventSnapshot`.

```swift
public struct AgendaSnapshot: Codable, Equatable, Sendable {
    public static let storageKey = "surface.agenda.v1"
    public struct Event: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let calendarTitle: String
        public let startDate: Date
        public let endDate: Date
        public let isAllDay: Bool
    }
    public var ownerID: String?
    public var generatedAt: Date
    public var expiresAt: Date          // min(generatedAt + 6h, next midnight)
    public var weekStart: Date          // start of the calendar week containing generatedAt
    public var events: [Event]          // sorted by start, capped at 80
}
```

Window: from `weekStart` to `weekStart + 14 days`. This covers the week
strip and gives the rolling next-events list at least seven days of
headroom, so it never runs dry between refreshes even on Sunday night.

Helpers, all pure and unit tested:

- `isAvailable(at:)`: same rule as `SurfaceSnapshot` (owner present, not
  before `generatedAt - 60s`, before `expiresAt`).
- `weekDays(calendar:)`: the seven days starting at `weekStart`.
- `events(on day:)`: events overlapping that day, all-day first, then by
  start time.
- `upcoming(from:limit:)`: events whose `endDate > from`, all-day events
  for the current day included at the top, capped at `limit`.
- `read(from:)` and `write(to:)` mirror `SurfaceSnapshot` on the same App
  Group suite under `storageKey`.
- `init` caps `events` at 80 after sorting by start so the file stays small.

An empty `AgendaSnapshot()` with no owner is the tombstone, exactly like
the health envelope.

### Publisher

`SurfaceCoordinator` gains `publishAgenda()`:

1. Guard `ownerID`, `context`, `sharingEnabled`, same as `publish()`.
2. Query `CalendarStore(context:).events(from:to:)` for the window above.
3. Map to `AgendaSnapshot.Event` and build the envelope.
4. Coalesce: if the previous agenda has the same owner, the same events
   (compared by id, title, dates, all-day flag) and is under an hour old,
   return without writing.
5. Write, then `WidgetCenter.shared.reloadTimelines(ofKind: "AlmanacAgenda")`.

`publish()` calls `publishAgenda()` at its end, so the existing
`reloadAll()` hook in `RootView` fires it after every save, including the
save that `CalendarSync.sync()` makes. `adopt`, `clear` and the
`sharingEnabled` setter write the agenda tombstone wherever they write the
health tombstone today. The Watch send path is not changed.

Calendar access not granted is not an error: the store simply holds no rows
in the window, and the envelope is written with an empty `events` list. The
widget distinguishes "no envelope" from "empty week".

## Widget

New file `AlmanacWidgets/AgendaWidget.swift`, added to the iOS widget
extension target in the Xcode project (the project file is hand maintained,
so this is two `PBXBuildFile` and `PBXFileReference` entries and one Sources
phase line). Registered in `AlmanacWidgets.swift` after `HealthWidget()`.

Kind: `"AlmanacAgenda"`. Display name "Your week". Description "Your next
events and a week at a glance." Families: `.accessoryInline`,
`.accessoryRectangular`, `.systemMedium`, `.systemLarge`.
Tap opens `SurfaceRoute.today.url`. Background is the shared `WidgetCanvas`.

### Timeline

`AgendaTimeline` reads the envelope. Entries:

- One at now.
- One at each event `endDate` within the next 24 hours, so the next-events
  list rolls forward without a refresh.
- One at `expiresAt` with a nil snapshot, hiding stale data.

Policy `.after(now + 30 min)`, matching Health. Entries are capped at 24.

### Views

`AgendaEntry` carries `date` and `snapshot`. `AgendaWidgetView` switches on
family:

- **Inline:** `Label("HH:mm Title", systemImage: "calendar")` for the first
  upcoming event; "No more events today" when empty.
- **Rectangular:** up to three rows of `upcoming(from: entry.date)`. Each
  row is a 3 point rounded bar in the chip color, the title in
  `.headline` at one line, and the start time (or "All day") in `.caption2`
  secondary. Titles are `.privacySensitive()`.
- **Medium:** `WeekStripGrid`: seven equal columns. Header per column is the
  abbreviated weekday over the day number; today's column has a soft tint
  behind it. Under the header, up to three chips: a rounded rectangle in
  the chip color with the time range on line one and the title on line two,
  both in a 9 point rounded font, clipped to one line each. A fourth or
  later event shows as "+N" in `.caption2`.
- **Large:** the same grid on top, then a divider, then today's list in the
  rectangular row style, up to six rows.

`ChipPalette.color(for calendarTitle:)` hashes the name with a stable
FNV-1a over UTF-8 (not `hashValue`, which is randomized per process) into
six pastels drawn from the existing widget metric colors plus two more.

### Empty and error states

- No envelope, foreign owner, or expired: the Health widget's prompt,
  "Open Almanac to sync", in each family's layout.
- Envelope present with no events in the window: the strip renders with
  empty columns; rectangular shows "Nothing scheduled" with the calendar
  icon; inline shows "No events this week".

## Testing

Package tests in `AppSurfacesTests` (Swift Testing, fixed UTC calendar):

1. Window and `weekDays` start on the calendar week and cover seven days.
2. `events(on:)` puts all-day first and includes multi-day overlaps.
3. `upcoming(from:limit:)` skips ended events, keeps in-progress ones,
   respects the limit.
4. Event cap holds at 80 after sorting, keeping the earliest.
5. Expiry follows the six-hour or midnight rule and the tombstone clears
   the owner and events.
6. `ChipPalette` returns the same color for the same name across calls and
   never falls outside the palette.

Native checks: build the app and both widget extensions; render the widget
in the simulator with synthetic events and save screenshots next to the
existing ones in `docs/design/widgets-watch/`. Verify the sharing toggle
clears the widget and that sign-out shows the sync prompt.

## Files

- New: `LifeOSKit/Sources/AppSurfaces/AgendaSnapshot.swift`
- New: `LifeOSKit/Tests/AppSurfacesTests/AgendaSnapshotTests.swift`
- New: `AlmanacWidgets/AgendaWidget.swift`
- Edit: `LIfeOS/App/Surfaces/SurfaceCoordinator.swift`
- Edit: `AlmanacWidgets/AlmanacWidgets.swift`
- Edit: `LIfeOS.xcodeproj/project.pbxproj`
- Edit: `docs/design/widgets-watch/implementation.md` (one paragraph)
