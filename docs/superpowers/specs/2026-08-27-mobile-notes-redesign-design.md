# Mobile notes: capture, collections, goals, mindmap

Date: 2026-08-27
Status: approved design, not yet planned

## Why

The notes tab is a good filing cabinet and a poor notebook.

On a phone, `NotesHubScreen.compactShell` opens on the Library sidebar. Writing
one line costs four taps: the tab, a shelf, the New menu, a page kind. Nothing
in the app captures a thought quickly. `QuickLogSheet` captures water and
weight; there is no equivalent for a sentence.

What is already good, and stays: the block editor (`NoteBlock`,
`NoteBlockEditor`) with its slash menu, markdown shortcuts, inline sketches and
ink layer; PARA filing (`NoteBucket`, `NoteFolder`) with drag to file; wiki
links and backlinks (`NoteLinkScanner`); Supabase sync for documents and
folders; and the measured three column iPad layout, which is untouched by this
work.

What is missing, in the order a person hits it:

1. No fast way in. The first screen is a cabinet, not a page.
2. No cross note questions. Blocks live as JSON inside `NoteDocument.blocksData`,
   so nothing can ask for every open to-do.
3. No categories that cut across PARA. A note has exactly one home.
4. Goals are half migrated. `PlanNoteMigration` moved them into Notes as `.task`
   pages in a Goals folder and dropped their targets on the way.
5. No way to see the shape of a library. The link graph exists as data and is
   never drawn.

## Decisions

Taken during brainstorming, recorded because each one closed off alternatives:

| Question | Decision |
| --- | --- |
| To-dos across notes | First class and indexed, mirrored from blocks |
| Phone root | Inbox stream with a pinned composer |
| Collections | Manual and smart, both |
| Mindmap | Graph over existing notes, lightly editable |
| Goals | Their own model |
| iPad | Three column shell kept as is, phone gets the new shell |
| Capture reach | Voice, share extension, Lock Screen and Control Centre |
| Data approach | Derived index written on save |

The rejected data approaches, so they are not relitigated: filtering documents
in memory on every read (fine at a few hundred notes, breaks on the mindmap and
on smart collections); and promoting blocks to SwiftData rows (cleanest queries,
but it rewrites the editor, the wire format and the server schema at once, and
reverses a documented decision in `NoteBlock.swift` for more blast radius than
the win justifies).

## Architecture

### The index layer

`NoteDocument` remains the single source of truth. Blocks stay JSON. On every
document save, `NoteIndexer` writes derived rows in the same transaction.

Derived models, local only, never pushed:

- `NoteTask`: one row per `.todo` block. `id` is the block's own UUID so the row
  is stable across reindexes. Carries `documentID`, text, `isChecked`, `indent`,
  `dueDate`, `goalID`, `sortOrder`. The indexer keys on (`documentID`, block id)
  rather than block id alone, so a block duplicated by copy and paste across two
  pages cannot collide.
- `NoteLink`: one row per `[[link]]` edge. `sourceID`, `targetTitleFolded`,
  resolved `targetID`. This is the mindmap's edge set.
- `NoteTagging`: one row per (document, collection), with a `source` of
  `explicit` or `inline` depending on whether membership came from a chip on the
  page or a `#tag` in the text. Rows exist for manual collections only. Smart
  collection membership is evaluated from its `NoteQuery` at read time and never
  stored, so a smart collection cannot drift from its own rule.

Inline tags are found by `NoteTagScanner`, a sibling of `NoteLinkScanner` in
`NoteBlock.swift` with the same shape: scan block text, fold case at lookup,
preserve what was typed. A `#tag` naming a collection that does not exist yet
produces no row until the collection is created, at which point the next
reindex picks it up.

Authored models, synced:

- `NoteCollection`: `id`, `name`, `icon`, `accent`, `kind` (`manual` or
  `smart`), `rule: NoteQuery?`, `sortOrder`, `createdAt`, `updatedAt`,
  `syncedAt`, `deletedAt`. The `syncedAt`/`deletedAt` pair follows `NoteFolder`
  exactly: `updatedAt > syncedAt` is the dirty test, deletes are tombstones.
- `Goal`: `id`, `title`, `detail`, `targetValue`, `unit`, `dueDate`, `status`
  (reusing `PlanStatus`), `pageID`, `collectionID`, plus the same timestamp
  quartet. Progress is computed, never stored.

Changes to existing models:

- `NoteDocument` gains `collectionIDsData: Data` (explicit membership, encoded
  `[UUID]`) and `filedAt: Date?`. A nil `filedAt` means the note is in the
  Inbox. That single nullable field is the whole Inbox concept: no new bucket,
  no new list, and it defaults cleanly for SwiftData's no-migration rule.
  `filedAt` is stamped the first time someone chooses where a note belongs:
  moving it to a bucket or folder, or joining it to a collection. It is never
  stamped by editing, so a note you keep writing in stays in the Inbox until you
  decide it has a home. Existing notes are stamped once by the phase 1
  migration, since they were all filed under the old model and should not
  reappear as unfiled.
- `NoteBlock` gains `goalID: UUID?` and `dueDate: Date?`. Both optional, so
  existing blocks decode unchanged (synthesized `Decodable` uses
  `decodeIfPresent` for optional properties), and both ride inside `blocksData`
  with no wire format change.

Goal attachment and to-do due dates live on the block, not on `NoteTask`,
because `NoteTask` is derived and rebuilt. Anything authored that lived only on
a derived row would be erased by the next reindex.

`NoteIndexer` is the only writer of derived rows:

```
reindex(document:in:)   // one document, inside the caller's transaction
rebuildAll(context:)    // migration, and a repair path
```

`NotesStore` and `NoteEditorViewModel.flush()` call `reindex`. `NoteSync` calls
it after each pull. Because every derived row is reconstructible from
`blocksData`, an indexer bug is a stale view rather than data loss, and the
repair is `rebuildAll`.

### NoteQuery

A small Codable predicate, and deliberately not a query language:

- `buckets: [NoteBucket]`
- `collectionIDs: [UUID]`
- `kinds: [NoteKind]`
- `statuses: [PlanStatus]`
- `hasOpenTasks: Bool?`
- `dueWithin: DateInterval?`
- `textContains: String?`

Evaluated against a `FetchDescriptor` where SwiftData can express the predicate
and in memory where it cannot. Powers smart collections and nothing else. If a
future need does not fit, it gets its own type rather than growing this one.

### Sync

Two server migrations:

- `note_collections` and `goals`, RLS scoped to `auth.uid()` like every existing
  table.
- `collection_ids uuid[]` and `filed_at timestamptz` columns on
  `note_documents`.

`NoteTask`, `NoteLink` and `NoteTagging` are never pushed. They rebuild locally
from the documents after each pull, which keeps the wire format unchanged for
the parts of the model that are derived and removes any possibility of two
devices disagreeing about them.

## Screens

### Phone shell

`NotesHubScreen.compactShell` is replaced by `NoteInboxScreen`. `wideShell` is
untouched: the iPad keeps its three column arrangement and gains the new
features inside it.

- **Composer, pinned above the nav rail.** Tap and the caret is there. Return
  saves and keeps you in the stream, so capturing five thoughts is five
  sentences rather than five navigations. It carries a to-do toggle, a mic and a
  sketch button. Typing `#` autocompletes collections inline.
- **Stream, above the composer.** Reverse chronological by `updatedAt`. Each
  row: icon, title, one line of excerpt, collection chips, to-do progress. Swipe
  right files (a sheet of recent collections and shelves), swipe left archives.
- **Chip row at the top.** Inbox, All, To-dos, Goals, then the person's own
  collections. Inbox is selected on launch, so the first thing anyone sees is
  what they have captured and not yet filed. To-dos and Goals are the cross note
  views the index unlocks.
- **Library and Map buttons in the header.** Library pushes the existing
  `NotesSidebar` as its own screen, so nothing that works today is lost. It
  simply stops being the first thing anyone sees.

### Editor ergonomics

Same pass, phone only:

- Swipe to check on to-do rows.
- Long press and drag to reorder blocks.
- The accessory bar's block picker shows six kinds inline (to-do, bulleted,
  heading 2, paragraph, sketch, divider) with the remaining six behind a "more"
  tap. Today all twelve sit in a horizontal scroller, which means the common
  ones are a scroll away.

### Collections

A collection is a chip: name, emoji, accent. Manual ones are joined from the
composer's `#` autocomplete or a chip row under the page title. Smart ones carry
a `NoteQuery` and fill themselves. Both render identically in the stream's chip
row: no one should have to remember which kind a collection is in order to use
it. A note keeps its one PARA home; collections cut across.

### Goals

`GoalsScreen`, reached from the chip row. A goal card shows title, progress (a
ring against `targetValue`, or done over total when it counts to-dos), due date,
the to-dos feeding it and its page. Creating a goal offers to create its page,
so a goal is never a lonely row.

Progress is computed from `NoteTask` rows whose `goalID` matches, so ticking a
to-do anywhere in the library moves the goal it belongs to.

This restores the targets `PlanNoteMigration` dropped. That migration is left
alone: the pages it created stay where they are, and adopting one into a goal is
a user action, not a second automatic pass over their library.

### Mindmap

`NoteMapScreen`, over the `NoteLink` edges the indexer produces. Nodes are notes
plus collections as hubs; edges are wiki links plus membership.

Not a force directed graph. A global simulation on a 390pt screen is unreadable,
and its positions move every time it re-runs, so nothing is ever where you left
it. Instead, a focused ego graph:

- One centre note. Neighbours on ring one, theirs on ring two.
- Radial layout by a deterministic sort, capped near 60 nodes with a "+N more"
  spur.
- Tap a node to re-centre with animation. Long press to open the page.
- Edges drawn in a `Canvas`; nodes are real views above it, for hit testing and
  accessibility. Pan and pinch on the container.

No physics engine, so no frame budget problem, and node positions are a pure
function of the focused note.

Editing without a second model: dragging one node onto another appends a
`[[target]]` to the source's text; long pressing empty space creates a page and
writes the link into the centre note. Every map edit is a text edit that flows
back through `NoteIndexer`. The map owns no state, syncs nothing, and cannot
conflict with the document it draws.

### Capture reach

- **Voice.** In app, on device `SFSpeechRecognizer`. `SpeechListener` already
  exists for the coach, so this is wiring. Nothing per user to pay for.
- **Share extension.** The extension does not touch the SwiftData store. The
  store is per account under Application Support (`UserScope.storeURL`) and was
  only just moved there; putting it in an app group would be a second store
  relocation whose failure mode is someone's notes. Instead the extension writes
  a small JSON payload into an app group drop folder, and the app drains that
  queue into the Inbox on next foreground.
- **Lock Screen and Control Centre.** A widget plus an App Intent that deep
  links `lifeos://capture` into the composer. No data path, no shared store,
  nothing to reconcile.

Global compose from any tab was considered and left out. It is close to free if
it is wanted later: long press the Notes pill in `PillNavBar` and present the
same composer.

## Testing

Following the existing shape in `LifeOSKit/Tests`:

- `NoteIndexerTests`: blocks in, derived rows out. Pure values, no store.
  Covers reindex stability (same blocks produce the same row ids), removal (a
  deleted to-do block removes its row), and `rebuildAll` idempotence.
- `NoteQueryTests`: predicate evaluation over literal documents.
- `NoteMapLayoutTests`: the radial maths, in the manner of
  `MonthGridLayoutTests`. Deterministic positions, the node cap, the overflow
  spur.
- `SharePayloadTests`: decoding a drop folder payload, including a malformed one.
- `NoteBlockTests`: extended for the two new optional fields decoding from JSON
  that lacks them.

## Phases

Written as one spec, sequenced so each phase ships alone.

1. **Index layer.** `NoteBlock` fields, `NoteTagScanner`, `NoteIndexer`,
   `rebuildAll`, and the one time stamp of `filedAt` on existing notes. No UI
   change. Entirely testable from literals.
2. **Phone shell.** `NoteInboxScreen`, the composer, `filedAt` as Inbox, editor
   ergonomics.
3. **Collections.** `NoteCollection`, `NoteQuery`, the `note_collections` table,
   chip row, smart collection evaluation.
4. **Goals.** `Goal`, `GoalsScreen`, the `goals` table, progress from indexed
   to-dos.
5. **Mindmap.** `NoteMapScreen`.
6. **Capture reach.** Voice, then the widget and App Intent, then the share
   extension last, since it is the only new target that needs an app group.

## Risks

- **Index drift.** Mitigated by construction: derived rows are rebuildable, and
  `rebuildAll` is the repair. Worth a debug menu entry.
- **Two new targets.** The share extension and the widget are the only parts
  that touch the project file and entitlements. They are last for that reason,
  and neither is required for phases 1 to 5 to be useful.
- **Scope.** Six phases is a lot of surface. Phases 1 and 2 are the ones that
  answer the original complaint; 3 to 6 are additive and can stop at any point
  without leaving anything half built.

## Cost

Device local work plus plain Postgres rows. On device speech recognition is
free. Nothing here touches the AI budget.
