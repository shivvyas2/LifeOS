# Notes redesign — 2026-09-13

## Changes

- iPhone opens a searchable page library with compact document rows, a creation menu, and native navigation. Folders and shortcuts live in a dismissible library sheet.
- iPad retains an adaptive library, page list and editor workspace, with a collapsible sidebar and keyboard commands.
- Warm neutral surfaces, charcoal typography and orange accents replace mixed pastel cards and glass pills.
- The editor emphasizes the page title and blocks. Metadata and save status are quiet; icon and color controls live in the page menu. Empty blocks explain typing and slash commands.
- Text supports Dynamic Type and Scribble. Sketch blocks support PencilKit; phone drawing accepts fingers. iPad page annotation offers an explicit finger-drawing toggle. Clearing drawings requires confirmation, and removed canvases release tool-picker observers.
- Edits flush when leaving the page or backgrounding. Failed saves expose a retry action. Recently opened, edited and created sorting now use their respective timestamps.
- Folder rename starts with the current name, and folder forms are presented after the library sheet dismisses.

## Validation

- Final native iOS simulator build: **BUILD SUCCEEDED**.
- Full Swift package suite: **1,168 tests passed in 151 suites**, including a new regression test for distinct creation, edit and open dates.
- Targeted Notes tests: **128 passed in 8 suites**.
- `git diff --check`: passed.
- In-memory library and editor fixtures are available through `NotesDesignPreview` in Xcode. They do not sync sample pages or change account data. The temporary launch routing used for visual QA was removed from the app entry point.
- Runtime visual verification is incomplete: the temporary iPhone and iPad simulators failed to finish usable startup, and SpringBoard crashed when launching the preview. Invalid boot-screen captures were discarded.
- Physical Apple Pencil drawing, Scribble, squeeze/double-tap and final iPad layout need device verification. No claim of hardware verification is made.
