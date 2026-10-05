# Editorial theme, navigation, Money, and badminton tracking

Decided 2026-10-05. Three choices made up front:

- **Visual direction: editorial mono.** Black and white base, large light
  figures, thin rules, numbered sections, a pill tab bar, one accent. Drawn
  from the two reference screens (a monochrome day planner and the ConnectX
  set). Not neo-brutalism: no thick outlines, offset shadows or loud colour
  blocks.
- **Court tracking: phone video plus watch.** GPS cannot place a player on
  a 13.4 x 6.1 m court (consumer GPS error is 5 to 10 m outdoors, worse
  indoors), so position comes from the phone camera, calibrated by a photo
  of the empty court, and the watch adds wrist data.
- **Order: theme, navigation and Money first,** then badminton, then the
  remaining stability work.

## Phase 1: theme, navigation, Money

### Design system (`LifeOSKit/Sources/DesignSystem/Editorial.swift`)

No new colours. Paper is `LifeOSTokens.canvas`, ink is `primaryText`, the
accent stays `LifeOSTokens.accent`. The layer adds structure:

| Piece | Use |
|---|---|
| `Hairline` | Rules between rows and under headings, ink at 14 to 18% |
| `editorialEyebrow()` | Tracked uppercase line above a heading or figure |
| `EditorialMasthead` | Screen heading: eyebrow, 34pt headline, support line |
| `EditorialSectionHeader` | "01" + title + rule, one trailing action |
| `EditorialFigure` | Large light figure, unit beside, label above |
| `EditorialRow` | Two-column fact row with a rule |
| `IndexPill` | The "03." anchor pill |
| `EditorialTag` | Outlined capsule; filled with accent only for the live or urgent item |
| `IndexedTabStrip` | Numbered, scrolling underline tabs for more than four sections |

### Root

- `AccentColor` asset set to the accent. It was empty, so every system
  control in the app was tinted system blue.

### Navigation

- `PillNavBar`: ink capsule, every tab shows its icon and its name, the
  selected tab on a paper pill. It was unlabelled icon circles, two of them
  near-identical grids.
- Still to do in this phase: label the floating quick actions (assistant,
  coach, start activity), make Social and Settings reachable without the
  avatar, replace stale copy ("Plan tab").

### Money

- Masthead: "Money · October", the month's net as a 64pt figure with the
  cents ghosted, a verdict tag, last sync time, and a labelled Add button.
- The vertical icon rail is gone. The six questions are an `IndexedTabStrip`
  under the masthead, with their full titles.
- Bands lose their six pastel fills. On a phone they are ruled blocks on the
  paper; on a regular width, outlined cards in the grid.
- `MoneyPalette` now points at the app's canvas and ink.

### Then, in the same style

Health, Fitness and Activity screens (sports and fitness first, as asked),
then Today, Notes, Life, Social and Settings, so no tab keeps its own palette.

## Phase 2: badminton

### Matches and practice

- A session is a match or a practice. A match has a format (singles or
  doubles), a teammate (picked from Social friends or typed), opponents, and
  a score per game, logged rally by rally on the watch or the phone.
- Practice has drills; each drill is a target zone sequence on the court
  (the reference drill screen: numbered steps over a court grid).

### 3D court

- Replace the illustrative SceneKit court with a proper badminton court:
  correct proportions and lines (singles and doubles sidelines, short and
  long service lines), a zone grid both halves, and the player's heatmap and
  shot origins drawn on it.
- Shot list per rally with side (forehand or backhand) and, where tagged,
  type.

### Tracking

- Before play: a photo of the empty court from the phone's stand position.
  The four court corners are found (or placed by the user), giving a
  homography from image to court coordinates.
- During play: the phone records; Vision body pose gives the player's feet
  each frame; the homography maps them onto the court. That yields position,
  distance, speed (walking or running), and where each shot was played from.
- Watch: wrist rotation sign and handedness give forehand or backhand; peak
  rotation and acceleration give swing power; lunges from acceleration.
- Shot type (clear, drop, smash, drive, net) is not detectable from the
  wrist without labelled data. Practice mode lets the player tag shots, and
  those tags become the training set; until then the app does not claim a
  shot type it did not observe.
- Strengths and weaknesses: per side and per court zone, rally outcome
  (won or lost) against where the shot was played from.

## Phase 3: stability

- Phone and watch must never disagree about a workout: force-end on the
  phone when the watch is gone, implement `didDisconnectFromRemoteDevice`,
  close the phone timer on an offline watch finish.
- The two watchdog kills seen in build 47 logs.
