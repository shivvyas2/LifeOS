# Notes: the Inbox, the editor, and a walkthrough

Decided 2026-10-06 with the owner, who said note-taking "feels a bit
confusing" and asked for a demo tutorial on first sign-in that can be
replayed from Settings. Reading the code found four places a new person gets
lost, and the owner confirmed all four:

- **Where a note goes.** A page made from the Recent view lands loose on
  Projects; the editor has no way to file it; moving it needs a long-press;
  today's journal lands beside the Journal folder, not in it.
- **Too many ways in.** `New page` opens a four-item menu; the library drawer
  repeats the search field; note, journal and task pages look identical.
- **Writing itself.** The editor opens with nothing focused; block types hide
  behind `/` and markdown prefixes; the accessory bar is twelve unlabelled
  icons; checked items go grey with no strike.
- **Tasks have no home.** The Inbox stream built in August was never routed,
  so there is no single list of open to-dos.

Decisions, in the order they were made:

- **The tutorial is a step-by-step walkthrough over the real screens**,
  not sample pages and not only the guide. Spotlight steps the app drives,
  replayable from Settings. The cost accepted: it needs upkeep when a layout
  moves, so every step is anchored to a view that reports its own frame.
- **A new page lands in an Inbox, and the editor gets a File chip.** The
  August Inbox stream comes back on the editorial theme, with the single
  to-do list as its third chip.
- **New is one tap.** It makes a blank page and opens it with the title
  focused. Today's journal lives on the Day screen and in the Journal
  folder; a task list is a page you add to-dos to; `New folder` lives in
  the library.
- **Three PRs, in order:** the Inbox and filing, then the editor, then the
  walkthrough, so the walkthrough shows the finished flows.

Everything follows the rules already set: paper, ink, hairlines, quiet ink,
the accent only for today and anything live, every button `.editorial(role)`,
fonts only from `LifeOSType` and `Editorial`, no per-module palette, no
model calls. Nothing here changes what Notes syncs.

## 1. The Inbox and filing (`feat/notes-inbox`)

### The shelf opens on the Inbox

`NoteSelection` becomes `inbox`, `all`, `todos`, `favorites`, `bucket(_:)`,
`folder(_:)`; `recent` goes. `NotesViewModel.selection` starts at `.inbox`.

The shelf, top to bottom:

1. The masthead row as now (the iPad library toggle, `EditorialMasthead`,
   the action). The eyebrow is `NotesHeadline.eyebrow(for:count:)`, a tested
   value: `Notes · 3 in Inbox`, `Notes · Nothing in Inbox`, `Notes · 24
   pages`, `Notes · 5 to-dos`, `Notes · 2 favourites`, and for a shelf or
   folder the page count as today. The title is `Inbox`, `All pages`,
   `To-dos`, `Favourites`, or the shelf or folder name; `Search` while
   searching.
2. The action is **`New`**, `.editorial(.primary, size: .compact)`,
   accessibility label `New page`. One tap calls
   `model.createNote(kind: .note)` and opens the page with the title
   focused (§2). From `inbox`, `all`, `todos` and `favorites` the page is
   unfiled, so it is in the Inbox; from a shelf or folder it lands there,
   filed, as now. The four-item menu is deleted. `New folder` is reachable
   only from the drawer and the rail.
3. **The chips**, an `UnderlinePicker` over `(.inbox, "Inbox")`, `(.all,
   "All")`, `(.todos, "To-dos")`, shown when the selection is one of those
   three; choosing a chip sets the selection. On a shelf, folder or
   favourites the chips are absent and the `Pages` header with its filter
   and sort stands as now.
4. The hairline search field as now.
5. **The rows.**
   - `inbox`: every unfiled, unarchived page, newest edit first
     (`NotesStore.inbox()`, which exists). Empty: an `EditorialEmptyState`
     with sentence `Nothing waiting. New starts a page here.` and action
     `New page`.
   - `all`: every page, by `NotesViewModel.sort` as now (`NotesStore`
     gains `cardsNewestFirst` as a public read, replacing the capped
     `recent(limit:)`), and the sort is honoured rather than overwritten:
     `load()` sorts once, by `sort`, for every selection; the `recentlyOpened`
     sort uses `openedAt`.
   - `todos`: the open to-dos of every live page, grouped by page: a quiet
     caption with the page title, then its to-dos as the rows the day screen
     draws (`ChecklistRows` from the day-briefing PR, each with
     `source: .page`), tick in place, text opens the page. Empty: `No open
     to-dos.` in quiet ink. `NotesViewModel` gains `private(set) var tasks:
     [NoteTaskGroup]` (`page: NoteCardSnapshot, rows: [ChecklistRow]`) built
     from `NotesStore.stream(for: .todos)`, and `toggleTask(documentID:
     blockID:)`, which runs `NoteBlockEditor.toggleCheck` and
     `NotesStore.update(_:blocks:)` then `requestSync()`.

The list is one `List` on paper (`.listStyle(.plain)`, hidden separators and
background, zero row insets), the masthead, the field and the chips as its
first rows, so cards can carry swipe actions: leading `File` (opens the
picker below) and trailing `Archive` (`Restore` on the Archive shelf). The
hairline between cards is drawn by the row, as now. Drag and drop on iPad is
unchanged.

### Cards say what they are

`NoteCardSnapshot` gains `isInInbox` (from `NoteDocument.isInInbox`). The
card's caption line reads the folder name, or `Inbox` when the page is
unfiled, or the shelf; a `JOURNAL` or `TASKS` eyebrow (`editorialEyebrow()`)
sits before it on those kinds, nothing on a plain note.

### The File chip

`NoteEditorViewModel` learns where its page lives: `private(set) var
folderID: UUID?`, `folderName: String?`, `isInInbox: Bool`, loaded with the
rest, and `func file(to bucket: NoteBucket, folderID: UUID?)`, which calls
`NotesStore.move(_:to:folderID:)`, reloads those fields and requests sync.

The meta row's first item becomes the chip: `Label("Inbox", systemImage:
"tray")` or `Label("Projects · Training", systemImage: "folder")` as
`.editorial(.secondary, size: .compact)`, accessibility hint `Choose where
this page lives`. Tapping presents **`NoteFilingSheet`**, the picker the
old Inbox screen had, lifted into its own file and finished: a `List` with
one section per shelf in `NoteBucket.filing`, `On Projects` first, then
every folder with nested ones indented by depth (the walk `NoteShelfScreen.
moveTargets` does today moves to `NotesSnapshot.moveTargets()` so the chip,
the swipe and the long-press share one list), and at the bottom `New
folder`, which dismisses, shows `NoteFolderSheet`, and files the page into
the folder it makes. The long-press `Move to` on cards stays.

### The drawer and the rail

`NotesLibraryList` and `NotesSidebar` lose their search field and the
`query` and `isSearchFocused` inputs. The tiles are `Inbox` (with its
count), `All`, `Favourites`, `Habits`; the shelves and folders as now;
`New folder` stays here and nowhere else.

### What goes

`NoteInboxScreen.swift` and `NoteInboxViewModel.swift` (their picker and
their empty-state sentence live on above; the composer and the sketch
button do not return).

## 2. The editor (`feat/notes-editor`)

- **A new page opens ready to write.** The focus itself ships with §1,
  because `New` promises it: `NoteEditorHost` takes `focus: NoteEditorFocus`
  (`none`, `title`, `firstBlock`); `NoteRoute.page(UUID)` becomes
  `page(UUID, focus: NoteEditorFocus)`, and `NotesHubScreen.open(_:focus:)`
  passes `.title` for a page `New` just made and `.none` otherwise;
  `NoteEditorScreen` gains `@FocusState private var titleFocused: Bool`.
  This PR adds the way into the body: the title field gets
  `.submitLabel(.next)` and `.onSubmit` moves focus to the first block
  (`model.focusedBlockID = model.blocks.first?.id`).
- **The block picker.** The formatting state of `NoteAccessoryBar` becomes
  `NoteBlockPicker`: a horizontal row of labelled chips, `Label(title,
  systemImage:)` in `LifeOSType.label`, `.editorial(.secondary, size:
  .compact)` with the current kind as `.primary`: `Text`, `To-do`,
  `Heading`, `Bullet`, `Numbered`, `Quote`, then a `More` menu holding
  `Heading 2`, `Heading 3`, `Callout`, `Code`, `Sketch`, `Divider`, then
  `Indent` and `Outdent` as chips, the `Draw` toggle, and `Hide keyboard`
  pinned outside the scroll as now. Picking a kind calls `model.transform(
  id, to: kind, text: block.text)`, keeping the block's words; today the
  bar routes through `applySlashCommand`, which passes an empty string and
  wipes them. The `/` menu and the markdown prefixes are unchanged.
- **Checked to-dos strike through.** In `NoteBlockRow` a checked to-do's
  text is quiet ink with `.strikethrough(true)`; its gutter mark is ink, not
  the accent. A swipe right of 48pt on a to-do row (horizontal beats
  vertical, as the calendar's swipe decides) ticks it with a light haptic;
  the gutter box stays.
- **The meta row** reads: the File chip, then the entry date or the status
  menu where they apply, then the save state.

## 3. The walkthrough (`feat/notes-walkthrough`)

### The pieces, in `DesignSystem`

- `WalkthroughAnchor`: `notesNew`, `notesFileChip`, `notesBlockPicker`,
  `notesTodos`, `notesLibrary`.
- `WalkthroughFrames`, an `@Observable` class in the environment
  (`\.walkthroughFrames`), holding `[WalkthroughAnchor: CGRect]` in the
  global coordinate space. The modifier `.walkthroughAnchor(_:)` reports a
  view's frame into it with `onGeometryChange(for: CGRect.self) { $0.frame(
  in: .global) }`, the pattern the workout video screen uses, and removes it
  on disappear. A view that is not on screen has no frame.
- `WalkthroughStep { anchor: WalkthroughAnchor; sentence: String }` and
  `WalkthroughScript`, a tested value: `static let notes: [WalkthroughStep]`
  in the order below, `next(after index: Int?, available: Set<
  WalkthroughAnchor>) -> Int?` returning the next step whose anchor is
  available and nil when none remain, and `isLast(_:available:)`.
- `WalkthroughOverlay(step:frame:isLast:onNext:onSkip:)`: paper ink at 55%
  over the whole screen with the anchor's frame cut out (a rounded
  rectangle, 8pt outset, `blendMode(.destinationOut)` inside a compositing
  group), and a card placed under the cut-out, or above it when the cut-out
  is in the lower half: the sentence in `LifeOSType.body`, then `Next` (or
  `Done` on the last step) as `.editorial(.primary, size: .compact)` and
  `Skip` as `.editorial(.quiet, size: .compact)`. The overlay is modal:
  taps outside the card do nothing. VoiceOver focus lands on the sentence;
  the card respects Dynamic Type.

### The steps

| # | Anchor | Where | Sentence |
|---|---|---|---|
| 1 | `notesNew` | the shelf | One tap starts a page. It lands in your Inbox until you file it. |
| 2 | `notesFileChip` | the editor | This says where the page lives. Tap it to move it anywhere. |
| 3 | `notesBlockPicker` | the editor | To-dos, headings and lists from here, or type / in the text. |
| 4 | `notesTodos` | the shelf | Every open to-do from every page, in one list. |
| 5 | `notesLibrary` | the shelf | Folders, favourites and habits live here. |

### The driver, in the app

`NotesWalkthrough`, an `@Observable` class owned by `RootView` and handed to
`NotesHubScreen` through the environment: `private(set) var stepIndex:
Int?`, `samplePageID: UUID?`, `func start()`, `next()`, `skip()`. The app
drives it; the person taps `Next`:

- `start()` sets step 1.
- `next()` from step 1 makes the sample page (`NotesStore.createDocument(
  title: "Your first page", bucket: .areas)`, unfiled) and asks the hub to
  open it with `focus: .firstBlock`, so the block picker is up; the overlay
  waits for the editor's anchors and shows step 2.
- `next()` from step 3 pops the hub's path and shows step 4; from step 4,
  step 5; from step 5 it finishes.
- Finishing or skipping: the sample page is deleted if its title is still
  `Your first page` and its blocks are blank, otherwise kept; the per-account
  flag `hasSeenNotesWalkthrough` in `UserDefaults.currentAccount` is set;
  `stepIndex` goes nil.
- A step whose anchor never appears within two seconds is skipped by the
  script's `next(after:available:)`; the walkthrough never draws a cut-out
  where nothing is.

`RootView` draws `WalkthroughOverlay` at the top of its shell `ZStack`
(above the tab content, below the full-screen covers), with the frame from
`WalkthroughFrames`.

### When it runs, and the Settings rows

- `NotesHubScreen` starts it on appear when `hasSeenNotesWalkthrough` is
  false and `hasSeenFirstRunTour` is true (both `@AppStorage` on
  `.currentAccount`), once per account. It never runs over the tour.
- `SettingsScreen` gains two rows under `At a glance`, in its
  `AccountPanel`, after `Widgets & Watch`: `Walk me through Notes again`
  and `Show the tour again`, as `NavigationLink`-styled rows that call two
  new `SettingsScreen` callbacks, `onReplayNotesWalkthrough` and
  `onReplayTour`. `RootView` wires them: the first closes the Settings cover
  and, in its `onDismiss`, sets `tab = .notes` and calls `start()`; the
  second closes the cover and sets `hasSeenFirstRunTour` to false, and
  `AppShell` gains `.onChange(of: hasSeenFirstRunTour) { _, seen in if !seen
  { showTour = true } }` so the welcome screen returns. The guide's row
  joins them when `feat/editorial-guide` lands; that spec's Notes line
  becomes "New starts a page in your Inbox; File puts it away."

## 4. Verification

- Tests: `NotesHeadlineTests` (every selection's eyebrow, zero and one),
  `NotesStoreTests` additions (`cardsNewestFirst` order; `moveTargets()`
  walks nested folders with `Parent / Child` titles); `WalkthroughScriptTests`
  (five steps in order, a missing anchor is skipped, the last available step
  is last, nothing after it). The view models live in the app target, which
  has no test target; their behaviour is checked through the preview pages.
- `scripts/check-typography.sh` reports nothing new versus the base of each
  PR.
- Builds: the app; `AlmanacWidgets` where `DesignSystem` changes.
- Preview pages, each with `--dark`: `notes` (the Inbox with three unfiled
  pages and the chips), `notes-all`, `notes-todos` (two pages' open to-dos),
  `notes-empty` (the Inbox empty state), `notes-filing` (the editor with the
  File sheet up), `notes-editor-new` (a new page, title focused, keyboard
  up), `notes-editor-picker` (first block focused, the labelled picker),
  `notes-walkthrough --step=N` for N 1 to 5 (the overlay over the fixture's
  shelf or editor). `NotesDesignPreview` is routed through `--page=` for the
  editor pages; its fixture gains three unfiled pages.
- Simulator: tap `New`, type a title, Return into the body, pick `To-do`
  from the bar, tap the File chip and file the page, go back and see it
  under its folder and gone from the Inbox; open `To-dos` and tick one;
  run the walkthrough from Settings end to end.

## 5. Delivery

Three PRs, each planned from this spec:

1. `feat/notes-inbox` (§1), cut from `main` after `feat/day-briefing`
   merges: it reuses that PR's `ChecklistRows` and `ChecklistRow` for the
   To-dos chip and relies on its journal-folder fix.
2. `feat/notes-editor` (§2), on `main` after 1.
3. `feat/notes-walkthrough` (§3), on `main` after 2.

Each PR's own gates are in §4. The planned `feat/editorial-guide` is
independent and can land before or after; its Notes row text is the one
line that changes.

## Out of scope

- Collections, goals as their own model, the mindmap, voice or share-sheet
  capture (the August spec's phases 3 to 6).
- The guide screen and the rebuilt tour (`feat/editorial-guide`).
- The Day screen's checklist, which already shows the journal page.
- Any change to sync, the block model, `NoteIndexer` or the migrations.
- iPad three-column behaviour beyond keeping it working with the new
  selection cases.
