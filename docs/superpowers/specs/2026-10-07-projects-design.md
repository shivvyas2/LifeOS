# Projects: plan the work, share it, see it on Today

Decided 2026-10-07 with the owner, who asked for "somewhat brutalist with
some colors" project screens (reference: a soft dashboard with a
contribution grid, project cards with charts, and tasks with owners'
avatars and times) "so I can see contributions, project scopes, add a
planner on project and plan the tasks and manage the whole project, assign
the project to someone".

Decisions, in the order they were made:

- **A project is the app's own**, optionally linked to one GitHub repo.
- **Projects are shared with friends in the app**: members see and edit the
  project's tasks through the server, and tasks assigned to them reach their
  Today.
- **Four planner views**: Board, Schedule, Milestones, List.
- **Projects is a sixth tab.**
- **The tab's look is hard-edged blocks**: square corners, 2pt ink borders,
  offset ink shadows, heavy uppercase labels, and colour only where it means
  a project. The rest of the app stays editorial.

Cost stays well under the ~$2 per person per month ceiling: four small
tables and the notes sync pattern; no model calls.

## 1. The model

| Thing | Fields |
|---|---|
| Project | id, name (1–60), scope (≤ 240), starts_on, ends_on (both optional), colour (one of six), owner, repo (`owner/name`, optional), archived_at, updated_at, deleted_at |
| Member | project, user, role (`owner` or `member`), added_at |
| Milestone | id, project, title (1–80), due_on (optional), position, updated_at, deleted_at |
| Task | id, project, milestone (optional), title (1–120), notes (≤ 2000), status (`todo`, `doing`, `done`), owner (a member, optional), due_on (optional), starts_at and ends_at (optional time block), position (order in its board column), done_at, updated_at, deleted_at |

The six colours, each with a light and dark value, live in `DesignSystem`
as `ProjectColour`: `tomato`, `marigold`, `moss`, `lagoon`, `iris`,
`rose`.

### The server

One migration: `projects`, `project_members`, `project_milestones`,
`project_tasks`, each with `updated_at` maintained by a trigger and the
three content tables carrying `deleted_at` tombstones.

Row-level security, through a `security definer` function
`is_project_member(project uuid)`:

- A member reads the project, its members, milestones and tasks.
- Any member inserts, updates and tombstones milestones and tasks.
- Only the owner updates or tombstones the project and adds or removes
  members; a member may remove themselves.
- Creating a project inserts the owner's membership in the same
  transaction (an `after insert` trigger), so the creator can read it back.
- A member can only be added if they are an accepted friend of the owner
  (checked in the insert policy against `friendships`).

### On the phone

SwiftData models `ProjectRecord`, `ProjectMemberRecord`,
`MilestoneRecord`, `ProjectTaskRecord` (each with `syncedAt` and
`updatedAt`), and `ProjectsStore` with the reads and writes the screens
need. `ProjectSync`, built like `NoteSync`: push pending rows (projects,
then members, milestones, tasks), then pull everything changed since the
cursor (`projects.sync.cursor`, rewound a second), newest `updated_at`
wins, a tombstone deletes locally. It runs on launch, on returning to the
app, after each local change (debounced), and on pull to refresh.

### Tested rules (in `Persistence`)

- `ProjectProgress`: done over total for a project and for each
  milestone; a project with no tasks reads 0 of 0, not a division by zero.
- `BoardMove`: moving a task to a column and position renumbers that
  column; moving to `done` stamps `done_at`, moving out clears it.
- `ScheduleLayout`: a day's time-blocked tasks placed in lanes so
  overlapping blocks sit side by side.
- `ContributionScale`: a year of daily counts mapped to five levels by
  quartiles of the non-zero days.
- `ProjectMerge`: the newer `updated_at` wins on pull; a tombstone deletes;
  a local unsynced edit newer than the incoming row survives.

## 2. The Projects tab

`AppTab.projects`, after Notes, with the `square.stack.3d.up.fill` symbol
and the label `Projects`.

### Home

- **Contributions**: a year grid (53 weeks × 7) in the chosen project
  colour's ramp, with `<n> THIS YEAR` in the header. From GitHub's GraphQL
  `contributionsCollection` when connected, cached for a day; otherwise
  from tasks completed per day.
- **Your projects**: a card each with the colour header band, name, scope,
  the progress bar with `64%`, members' avatars, and the next milestone.
  Archived projects behind `ARCHIVED (n)`.
- **Today's tasks**: your tasks across projects due or scheduled today,
  each with a status chip (`TO DO`, `DOING`, `DONE`), the time block and the
  project's colour tick.
- `+ NEW` opens a sheet: name, scope, dates, colour, and `Link a repo` (your
  repos, from the GitHub connection, when connected).

### A project

- Header: colour band, name, scope, dates, member avatars, `+ TASK`.
- A tab strip: `BOARD · SCHEDULE · MILESTONES · LIST`.
  - **Board**: three columns with counts; cards show title, owner avatar,
    due or time, milestone. Drag a card within or across columns
    (`BoardMove`); on a phone the columns scroll sideways, one and a half
    on screen.
  - **Schedule**: a week strip (today marked), then an hourly timeline of the
    selected day's time-blocked tasks (`ScheduleLayout`), each block with
    title, status, owner avatars and the notes' first line; `+` at an empty
    hour creates a task in that slot.
  - **Milestones**: each phase with its due date, progress bar and its tasks;
    `+ MILESTONE`; long-press to reorder.
  - **List**: every task, filter chips for status, owner and milestone,
    sorted by due date then position.
- **Task sheet**: title, notes, status, owner (a member), milestone, due
  date, an optional time block (start and end), and `Delete task`.
- **The owner's menu**: `Members` (your friends, added and removed),
  `Link repo` or `Unlink repo`, `Edit project`, `Archive`. A member sees
  `Leave project` instead.
- **A linked repo** adds a strip under the header: commits this week, open
  issues, the latest commit, through the existing GitHub day loader's calls.

### The look (this tab only)

`BrutalCard`: square corners, a 2pt ink border, and an ink shadow offset
4pt down and right, all in `DesignSystem`. Uppercase labels in
`LifeOSType.label` with tracking; titles in `LifeOSType.sectionTitle`
heavy. Colour fills only the card header band, contribution squares,
progress bars, column count badges and the task's colour tick. Ink and
paper come from the existing tokens, so dark mode is ink-on-dark with the
same shapes.

## 3. Elsewhere

- **Today's tasks** (Today and the day screen) gain a fourth source: tasks
  assigned to you, due today or with a time block today, open, detail
  `<project name>`, tickable (a tick sets `done`).
- **The Today layout** gains a `projects` module (hidden by default, in the
  tray): the last 12 weeks of contributions and up to three active projects'
  progress bars, opening the tab.

## 4. Verification

- Package tests for the five rules above, the store's reads (my tasks
  today, a project's tasks by column), and the sync's merge against a stub
  REST.
- SQL policy checks run against the local Supabase (`supabase test db`
  with pgTAP): a non-member reads nothing; a member edits a task but not the
  project or members; a non-friend cannot be added; the owner's membership
  appears on create.
- UI tests on preview pages: create a project, add a task, drag it to
  Doing, schedule it, and see it under Today's tasks on the home.
- Preview pages, light and dark: `projects`, `project-board`,
  `project-schedule`, `project-milestones`, `project-list`, `project-task`.
- The app and the package for macOS build; typography reports nothing new.

## 5. Owner's steps

`supabase db push` for the migration. No new secrets or functions.

## Out of scope

- Turning tasks into GitHub issues, and GitHub Projects boards.
- Push notifications for assignments; comments; attachments; recurring
  tasks.
- Projects on the Watch or in widgets.
