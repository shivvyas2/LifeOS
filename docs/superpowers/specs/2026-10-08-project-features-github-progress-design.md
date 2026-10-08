# Project features: scope it, plan it, watch it move on GitHub

Decided 2026-10-08 with the owner, who asked "so that I can scope the
projects, create a plan and list of features, and then I can see at what
stage the project is on GitHub: the commits, commit history, branches,
progress".

Builds on the Projects tab (`2026-10-07-projects-design.md`, merged as PR
#41) and the GitHub connection (`2026-10-07-github-project-card-design.md`,
PR #35). Today a project's `repo` is display only; nothing reads it.

Decisions, in the order they were made:

- **A feature's progress comes from its branch and PR**, read from GitHub;
  the app never writes to the repo.
- **The plan is drafted by LIFO and edited by the owner**: one model call
  per draft, nothing kept until the owner says so.
- **GitHub is read on the phone with the token already in its Keychain**,
  and only the resulting stage is synced to the project's members. Chosen
  over a server poller (it would have to store the token, reversing the
  "store nothing" decision of PR #35) and over a GitHub App with webhooks
  (new registration and per-repo install, too heavy for a personal tool).
  The cost: a stage refreshes only when a member with repo access opens the
  project.
- **Features are a new level; tasks and the four views stay.** A task may
  point at a feature.
- **Three slices, one PR each**: features and Plan; GitHub; Draft with LIFO.

Cost: one small table, the existing sync pattern, GitHub's API (free), and
about one plan draft per person per day through `lifo-agent` (owner accepted
up to ~$1.44 per user per month on top of chat). Well under
the ~$2 per person per month ceiling.

## 1. The feature

| Field | Notes |
|---|---|
| id, project | as for milestones |
| title | 1–80 characters |
| note | ≤ 280 characters, optional |
| position | order in the plan |
| milestone | optional |
| branch | optional branch name, ≤ 255 |
| stage | `planned`, `building`, `review`, `done`; default `planned` |
| stage_detail | ≤ 80, the line under the title ("12 commits · 2h ago", "PR #42 open") |
| pr_number | optional; the PR the stage came from, for the link |
| stage_checked_at | when a phone last worked the stage out from GitHub |
| updated_at, deleted_at | trigger-maintained, tombstoned, as for tasks |

Tasks gain an optional `feature` column. On the phone this is an
**optional** property on `ProjectTaskRecord` (a non-optional field added to
an existing `@Model` stops installed stores opening).

### The server

One migration, `project_features`, with the same row-level security as
`project_milestones`: any member reads, inserts, updates and tombstones;
membership through `is_project_member`. Plus the nullable `feature uuid`
column on `project_tasks`, referencing `project_features` with `on delete
set null`. `account-purge` needs no change: features go with their project.

### On the phone

`FeatureRecord` (SwiftData, with `syncedAt` and `updatedAt`), reads and
writes in `ProjectsStore`, and a fifth table in `ProjectSync` following the
milestone path exactly: snapshot marking, per-row refusal, its own server
cursor, included in the whole-project fetch for a new member.

## 2. Stages

A pure function in the package, `FeatureStage.resolve(branch:prs:)`, with no
network:

| What GitHub says | Stage | Detail |
|---|---|---|
| No branch linked, or the branch does not exist and no PR from it was merged | Planned | "Not started" |
| Branch exists, any commits ahead of the default branch | Building | "N commits · <relative time of last>" |
| Branch exists, zero commits ahead | Planned | "Branch made, no commits yet" |
| An open PR whose head is the branch | In review | "PR #N open" |
| A merged PR whose head is the branch | Done | "Merged <relative date> · PR #N" |
| Only closed, unmerged PRs | as if there were no PR | |

Precedence: a PR beats the branch, and of a branch's open and merged PRs
the newest (highest number) decides, so a merged PR followed by a new open
PR from the same branch shows In review. A branch deleted after its PR
merged stays Done, so tidying branches never undoes progress. Only PRs whose
head repo is this repo count: a fork's PR from a branch of the same name is
someone else's work.

**Branch suggestion**: a new feature proposes `feat/<slug>`, the title
lower-cased, ASCII-folded, non-alphanumerics collapsed to `-`, trimmed to 40
characters. Copy button on the feature page.

**Automatic linking**: a feature with no branch links itself to a branch
whose name equals its suggestion, or ends with `/<slug>`. Exactly one match
links; several matches link none and the feature page lists them to pick
from. The owner can always pick any branch, or unlink.

**Progress**: done features over all features, plus a count per stage.
A project with no features shows no bar.

## 3. Reading GitHub

`GitHubProjectSource` in `Integrations`, given the token and `owner/name`:

- **Status, two GraphQL queries.** The first reads the default branch's
  name (kept for the session). The second reads, in one call, the 100 most
  recently committed branches, each with its last commit time and its
  ahead/behind count against the default branch, and the 50 most recently
  updated PRs (number, title, state, merged time, head branch and head repo).
  This replaces a REST call per branch. A linked branch outside those 100 is
  treated as not existing, which only matters for a branch with no commit in
  a long while and no PR.
- **A feature's commits**: `GET /repos/{repo}/compare/{default}...{branch}`,
  on the feature page only.
- **History**: `GET /repos/{repo}/commits?sha={default}&per_page=30&page=N`,
  on demand. An empty repository answers 409, which reads as no commits.
- **Repo picker**: `GET /user/repos?per_page=100&page=N`, next page while a
  page comes back full, up to 10 pages.

`GitHubTransport` gains a `post` for GraphQL beside its `get`.

When: when a project opens, every 5 minutes while one of its views is on
screen, and on pull to refresh. Results are cached per repo in memory for 5
minutes so switching views does not refetch.

After a fetch, for each feature whose resolved stage, detail or PR differs
from what it holds, the phone writes the new values and `stage_checked_at`,
and `ProjectSync` pushes them. A member who cannot read the repo sees the
synced stage.

Failures:

- **No GitHub connection, or 404 on the repo** (no access): stages stay as
  last synced, the Plan header reads "As of <relative time>" with a
  "Connect GitHub to update" link when not connected. Nothing is reset.
- **401**: the existing `needsReconnect` path; the Plan header offers
  Reconnect.
- **403 or 429** (rate limit; the transport carries no headers to tell a
  reset time): keep the cache and the last state, try again on the next
  5-minute tick.
- **Anything else**: logged through `githubLog`, last state kept.

The repo picker in the new-project sheet moves to the same source: search
field, all pages of `/user/repos` (today it stops at 50).

## 4. Screens

All in the tab's existing hard-edged look.

**Plan** (new; the first view of a project with a repo, the fifth tab of
the view switcher otherwise):

- Header: scope sentence, progress bar ("4 OF 9 FEATURES DONE"), stage
  counts, and "As of …" when the stages are not fresh.
- Feature rows in plan order: title, stage chip, detail line. Long-press to
  drag, swipe to delete.
- Empty: **Draft with LIFO** (primary) and **Add feature**. Otherwise **Add
  feature** at the foot.
- Feature page: title and note (editable), milestone, branch (suggested
  name with Copy, Pick branch, Unlink), its commits ahead of the default
  branch, the PR as a link, and its tasks with Add task.
- iPad: list and feature page side by side.

**GitHub** (new, only with a repo):

- **Commits**: the default branch's history, newest first: message's first
  line, author, relative time, short SHA; tap opens it on GitHub. 30 at a
  time, more on scroll.
- **Branches**: the 100 most recently committed, newest first, each with
  ahead/behind against the default branch, last commit time, and its
  feature if any. No commit in 30 days dims it.
- **Pull requests**: open, then the last five merged.

**Projects home**: a card whose project has features gets a thin progress
bar; one with a repo gets "Last commit <relative time>".

## 5. Draft with LIFO

A new request kind, `plan`, in `lifo-agent`:

- Input: project name, scope, dates, milestone titles, and, when a repo is
  linked and readable, the README (first 6,000 characters) and the 20 most
  recent commit subjects. The phone gathers these and sends them; the
  function never calls GitHub.
- An optional nudge from the owner, ≤ 200 characters ("smaller", "start
  with auth").
- Output, by schema: 3 to 12 features, each `title`, `note`, `branch`
  (suggested), `milestone` (one of the given titles or null), in order.
- Bounds: input sizes above enforced server side; about one draft per
  person per day, enforced as a daily allowance of 12,000 billed tokens in
  `lifo_usage` under kind `plan`, separate from chat's. Chosen by the owner
  knowing it can add ~$1.44 per user per month at the worst.
- The phone shows the draft as an editable preview. **Keep** saves the
  features; **Redraft** asks again with the nudge; leaving discards it.
- A refusal, a failure, or the daily limit shows one plain sentence and
  leaves **Add feature** available.

## 6. Testing

- **Package**: `FeatureStage.resolve` for every row of the table above,
  including merged-then-deleted and merged-then-reopened; slug and
  auto-link rules (one match, several, none); progress; decoding branches,
  compare, pulls and commits from recorded fixtures; paging stops on a short
  page.
- **Deno**: `plan` input bounds, output schema validation, daily limit.
- **Sync**: features round-trip like milestones, including a new member's
  whole-project fetch and a stage written by one member arriving at another.
- **UI** (design-preview pages over fixtures): Plan with a feature in each
  stage; draft, edit, keep; GitHub view's three sections; add a feature and
  link a branch by hand.

## 7. Slices

1. **Features and Plan**: migration, `FeatureRecord`, store and sync, Plan
   view and feature page with hand-made features, progress, task to feature.
   Owner step: push the migration.
2. **GitHub**: `GitHubProjectSource`, stages and linking, the GitHub view,
   home card progress and last commit, repo picker with search and paging.
   No owner step: the `repo` scope already covers every call.
3. **Draft with LIFO**: the `plan` kind, preview, keep and redraft.
   Owner step: redeploy `lifo-agent`.

## Out of scope

Writing to GitHub (issues, branches, PRs), CI status, webhooks, other
forges, and features that span several repos.
