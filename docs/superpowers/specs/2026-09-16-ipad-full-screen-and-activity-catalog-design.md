# iPad full screen for live flows, and the full activity catalog

Date: 2026-09-16. Status: approved design, ready for planning.

## Goal

Two things Shiv asked for on 2026-09-15, after trying the app on an iPad:

1. The live session and the workout video should fill an iPad's screen,
   in landscape as well as portrait, the way they do on a phone.
2. Begin Activity should offer every activity the Apple Watch Workout app
   offers, badminton included, on the phone and on the Almanac Watch app.

## Part 1: iPad full screen

### Cause

Begin Activity is presented with `.sheet` from `RootView`. On an iPhone a
sheet covers the screen; on an iPad it is a centered card, and the workout
library and the video player are pushed inside that card's navigation
stack, so nothing in the live flow can ever be larger than the card.

Separately, `VideoWorkoutScreen` decides it is in landscape when the
vertical size class is compact. That is true of a phone turned sideways
and never true of an iPad, so on an iPad rotation never enters the
full-screen player; only the button does.

### Presentation

`RootView` presents `BeginActivityScreen` with `.fullScreenCover` when the
horizontal size class is regular and keeps `.sheet` when compact. That is
the precedent `showSettings` and `showCoach` already follow. The two
presentations share one `isPresented` binding and one `onDismiss` closure,
so the quick-log hand-off after a session behaves the same either way. No
other sheet changes: Quick Log, notifications, day detail, the assistant
and the editors are dialogs, and a card is the right size for a dialog.

### Landscape detection

`VideoWorkoutScreen` reads its size with a `GeometryReader` at the root of
the screen and defines `isLandscape` as width greater than height. On a
phone that is the same answer the size class gave. `OrientationLock` is
unchanged: an iPad already allows every orientation, and the phone still
asks for landscape only while this screen is up.

### Wide layouts

Both live screens gain a wide layout, chosen when the horizontal size
class is regular and the available width is at least 900 points. Below
that, including every iPhone and an iPad in a narrow Stage Manager pane,
the current single column stays.

- `VideoWorkoutScreen`, portrait on a wide screen: the player on the
  leading side at 60 percent of the width, keeping its aspect ratio and
  its draggable HUD, and a trailing column with the open-in-YouTube link,
  the details, the elapsed line, rep controls and `ActivityControls`. The
  620 point cap on the column is dropped on iPad. Full screen and
  landscape are unchanged apart from the detection fix.
- `BeginActivityScreen` on a wide screen: the timer card with its rings and
  the activity picker on the leading side, the connections panel, the
  follow-a-video entry and the quick-log button on the trailing side. The
  live gradient behind a running session spans the full width.

### Not changed

The Watch app, the Live Activity, the design previews, and the other
screens' column caps. A general iPad pass over Today, Money and Notes is
separate work.

## Part 2: the activity catalog

### Data

A new file `LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift`, in
AppSurfaces because the Watch app and the widget extension already import
it and it has no dependencies. It holds:

```swift
public struct ActivityType: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case cardio = "Cardio"
        case strength = "Strength and Conditioning"
        case sports = "Racket and Ball Sports"
        case water = "Water"
        case outdoor = "Snow and Outdoor"
        case mindAndBody = "Mind and Body"
        case danceAndPlay = "Dance and Play"
        case other = "Other"
    }
    public let name: String          // the stored value and the display name
    public let group: Group
    public let symbol: String        // SF Symbol
    public let healthRawValue: UInt  // HKWorkoutActivityType.rawValue
    public let countsReps: Bool
    public let showsZones: Bool
    public let tracksDistance: Bool
    public var id: String { name }
}

public enum ActivityCatalog {
    public static let all: [ActivityType]          // 79 entries
    public static let popular: [ActivityType]      // Walk, Run, Cycle, Strength, Yoga, Other
    public static func type(named: String) -> ActivityType?   // exact, then case-insensitive
    public static func type(healthRawValue: UInt) -> ActivityType?
    public static func search(_ query: String) -> [ActivityType]  // name contains, catalog order
    public static func grouped() -> [(Group, [ActivityType])]     // catalog order within a group
}
```

`all` is every `HKWorkoutActivityType` in the iOS 26 SDK except:

- the three deprecated cases `dance`, `danceInspiredTraining` and
  `mixedMetabolicCardioTraining`, which Health no longer accepts;
- `swimBikeRun` and `transition`, which are multisport containers that
  need sub-activities the recorder does not model.

That leaves 79, and `other` is one of them. Names follow the Apple Watch
Workout app where it has one ("Traditional Strength Training" becomes
"Strength" and "Functional Strength Training" becomes "Functional
Strength", so today's stored names stay valid). The six current names
`Walk`, `Run`, `Cycle`, `Strength`, `Yoga` and `Other` are unchanged, so
every `WorkoutRecord.activityName` and every persisted
`ActivitySessionState.activity` on disk resolves without migration. An
unknown stored name resolves to Other, as it does today.

Flags:

- `countsReps` is true for Strength and Functional Strength only.
- `showsZones` is false for Yoga, Pilates, Tai Chi, Flexibility, Cooldown,
  Preparation and Recovery, and Mind and Body.
- `tracksDistance` is true for Walk, Run, Cycle, Hiking, Wheelchair Walk
  Pace, Wheelchair Run Pace, Hand Cycling, Swimming, Rowing, Paddle Sports,
  Cross Country Skiing, Downhill Skiing, Snowboarding and Skating. It is recorded on the row for the
  future; the recorder does not change how it collects distance in this
  work.

Symbols are the `figure.*` SF Symbols Apple uses for the same types, for
example `figure.badminton`, `figure.pickleball`, `figure.table.tennis`.
A native check confirms each symbol resolves, so a typo shows up in the
check run, not on a Lock Screen.

### Recents

`ActivityRecents` in the app, over `UserDefaults.currentAccount` under the
key `activity.recents`: an ordered list of up to six names, most recent
first. Starting a session moves that name to the front. The list is empty
for a new account, and Begin Activity shows `ActivityCatalog.popular` in
that case. Recents are per account, like the other current-account
preferences, and are not sent to the Watch.

### Replacing `RecordedActivity`

`RecordedActivity` is deleted. `ActivityRecorder.selection` becomes an
`ActivityType`, defaulting to Walk. Every site that switched on the enum
uses a flag instead:

- `selection == .strength` becomes `selection.countsReps`, in the
  recorder, the Watch mirror path, `BeginActivityScreen` and
  `VideoWorkoutScreen`.
- `selection != .yoga` around the zones card becomes `selection.showsZones`.
- `selection.healthType` becomes
  `HKWorkoutActivityType(rawValue: selection.healthRawValue) ?? .other`,
  through one app-side extension `ActivityType.healthType`.
- `RecordedActivity(rawValue:)` on a restored draft becomes
  `ActivityCatalog.type(named:) ?? other`.
- `VideoWorkoutScreen.activity(for:)` returns Strength, Yoga or Other by
  name lookup.
- `WatchSessionBridge.name(for:)` and `icon(for:)` read the catalog by
  health raw value, which removes the hand-copied table there.
- `WatchWorkoutController.startable` is deleted. The Watch start sheet
  lists `ActivityCatalog.popular` first, then every group as a section.
  `activityName` and `isStrength` come from the catalog entry.

The Live Activity, the widget readout and the Watch mirror show the
catalog symbol for the running type, so a badminton session gets a
racket, not a walking figure.

### Picker

`BeginActivityScreen` keeps the "Choose your activity" grid, now fed by the
recents list (or popular) plus a "More" tile at the end. The tile opens
`ActivityPickerSheet`: a searchable `List` with one section per group in
catalog order, the selected type marked, a search field that filters by
name across every group. Choosing a type sets `selection`, records it as
a recent, and dismisses. The sheet is a `.sheet` on every device; it is a
dialog. The grid marks the selected type even when it is not in the
recents, by appending it as a seventh tile.

## Error handling

- A saved name that no catalog entry matches resolves to Other, never
  fails to open a draft or a record.
- `HKWorkoutActivityType(rawValue:)` returning nil for a catalog value is a
  bug the native check catches; at runtime the recorder falls back to
  `.other` rather than refusing to start.
- A symbol that does not resolve falls back to `figure.mixed.cardio` at the
  call sites that draw it, and the native check reports the name.

## Testing

Package tests in `AppSurfacesTests` (Swift Testing):

1. The catalog has 79 entries with unique names and unique health values,
   and none of the excluded raw values (14, 15, 30, 82, 83).
2. Lookup by name is exact first and case-insensitive second; an unknown
   name returns nil.
3. Lookup by health raw value round-trips every entry.
4. `popular` is the six current names in the current order.
5. `search("bad")` finds Badminton; `search("")` returns everything.
6. `grouped()` covers every entry exactly once and keeps catalog order.
7. Reps, zones and distance flags hold for the named entries.

App tests via the existing native check harness
(`ActivityRecorderChecks`):

8. Every catalog entry maps to a non-nil `HKWorkoutActivityType` and a
   resolving SF Symbol.
9. Recents: starting Badminton then Run yields `["Run", "Badminton"]`;
   starting Run again keeps it at the front without a duplicate; the
   seventh distinct start drops the oldest.
10. A restored draft with activity "Pilates" selects Pilates with reps off
    and zones off; a draft with "Nonsense" selects Other.

Native and visual checks on the `LifeOS-iPad13` simulator: Begin Activity
opens full screen; a running session shows the wide layout; a video in
landscape fills the screen with the HUD; the picker sheet lists Racket and
Ball Sports with Badminton. Screenshots go to `docs/design/ipad/`. Phone
build, Watch build and both extension builds pass.

## Files

- New: `LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift`
- New: `LifeOSKit/Tests/AppSurfacesTests/ActivityCatalogTests.swift`
- New: `LIfeOS/Features/Activity/Model/ActivityRecents.swift`
- New: `LIfeOS/Features/Activity/View/ActivityPickerSheet.swift`
- Edit: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`,
  `ActivityRecorder+Watch.swift`, `ActivityRecorderChecks.swift`
- Edit: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`
- Edit: `LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift`
- Edit: `LIfeOS/App/RootView.swift`
- Edit: `LIfeOS/App/Surfaces/WatchSessionBridge.swift`
- Edit: `AlmanacWatch/WatchWorkoutController.swift`,
  `AlmanacWatch/AlmanacWatchApp.swift`
- Edit: `docs/design/widgets-watch/implementation.md` (one paragraph)
