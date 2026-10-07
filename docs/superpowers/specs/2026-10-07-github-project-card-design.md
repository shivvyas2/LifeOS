# The day's project card, from GitHub

Decided 2026-10-07 with the owner. Slice 2 of the day briefing
(`2026-10-06-day-briefing-design.md` named it: "commits that day, the repo
with the latest commits, its open issues or milestone, a token or sign-in in
Settings"). Email is slice 3 and has its own spec.

Decisions, in the order they were made:

- **Sign-in is a GitHub OAuth App asking for `repo read:user`.** The owner
  chose it over a read-only GitHub App knowing that `repo` is full read and
  write on every private repo: one web step instead of two. The app itself
  only ever reads.
- **The redirect flow, with a small Edge Function for the secret.** Tap
  Connect, sign in on GitHub in the in-app web sheet, land back in the app.
  Chosen over the device-code flow, which needs no server but makes the
  person type a code.
- **The card's repo is automatic, with an optional pin.** By default, the
  repo with the most of your commits that day; Settings can pin one repo.
- **The card shows commits, then the milestone or issues:**

  ```
  PROJECT · LifeOS
  6 commits
    fix(notes): close the gaps the review found
    test(notes): UI tests tap through the walk…
    feat(design): a walkthrough script, ancho…
    4 more
  Milestone 1.1 · 4 of 9 left · due Oct 20
  ```

Everything follows the rules already set: paper, ink, hairlines, quiet ink,
the accent only for today and anything live, every button
`.editorial(role)`, fonts only from `LifeOSType` and `Editorial`, no
per-module palette, no model calls, and the running cost under about $2 per
person per month. The app ships free, so anyone can connect their own
GitHub, not only the owner.

## 1. Connecting

### Settings

`ConnectionsSettingsScreen` gains a GitHub row drawn like Whoop and Fitbit:
`Connect` when there is no token; `Connected as @login` with `Disconnect`
once there is, and under it `Pin a repo`, a picker of `Automatic` then the
person's repos sorted by most recent push (`GET /user/repos?sort=pushed&
per_page=50&affiliation=owner,collaborator,organization_member`). The
choice is stored per account in `UserDefaults.currentAccount` under
`github.pinnedRepo` as `owner/name`; nil is Automatic.

### Sign-in

- `GitHubOAuth` in `Integrations` builds the authorize URL:
  `https://github.com/login/oauth/authorize` with `client_id`,
  `redirect_uri=almanac://github-callback`, `scope=repo read:user`, a random
  `state`, and a PKCE `code_challenge` (S256) with its verifier. It parses
  the callback, rejecting a missing code or a `state` that does not match,
  and surfaces GitHub's `error=access_denied` as a cancel, not a failure.
  The client id ships in `Config/App-Info.plist` as `GitHubClientID` (it is
  public); the secret never ships.
- `GitHubConnectionViewModel` in the app runs `ASWebAuthenticationSession`
  with `callbackURLScheme: "almanac"`, as `FitbitConnectionViewModel` does,
  then posts the code and verifier to the Edge Function.

### The `github-token` Edge Function

`supabase/functions/github-token/index.ts`, on the `_shared/supabase.ts`
helpers the other functions use:

- Every call needs a Supabase session (`resolveUser`); without one, 401.
- `POST { code, verifier, redirect_uri }`: exchanges at
  `https://github.com/login/oauth/access_token` with `GITHUB_CLIENT_ID` and
  `GITHUB_CLIENT_SECRET` from the function's environment, `Accept:
  application/json`, and returns `{ access_token, scope }`. A GitHub error
  (`bad_verification_code`, `redirect_uri_mismatch`) comes back as 400 with
  that code. Missing environment: 500 `server_not_configured`.
- `DELETE { access_token }`: revokes the grant with `DELETE
  https://api.github.com/applications/{client_id}/grant` (basic auth with the
  id and secret), so Disconnect really disconnects. 204 on success; a token
  GitHub no longer knows counts as success.
- It stores nothing: no table, no log of the token. GitHub OAuth App tokens
  do not expire, so there is no refresh. The operator never holds anyone's
  GitHub token.

### On the phone

`KeychainGitHubTokenStore` in `Integrations`, per account like
`KeychainFitbitAuthStore`, holds `{ token, login }`. `login` comes from
`GET /user` straight after the exchange. Disconnect calls the function's
`DELETE`, then clears the Keychain item and the pin whether or not the
revoke succeeded (offline Disconnect still forgets the token here).

## 2. What is fetched, and when

All calls go from the phone straight to `https://api.github.com` with
`Authorization: Bearer <token>`, `Accept: application/vnd.github+json`,
`X-GitHub-Api-Version: 2022-11-28`.

### A day's commits

- **The day** is the person's local calendar day, `[start, start + 1 day)`
  in `Calendar.current`, so a daylight-saving day is 23 or 25 hours.
- **One search:** `GET /search/commits?q=author:<login>+author-date:<from>..<to>&
  sort=author-date&order=desc&per_page=100`, the bounds as ISO 8601 with the
  local offset. Author date, so a commit written yesterday and rebased today
  stays on yesterday. The search covers private repos the token can read.
- **The repo:**
  - Pinned: the commits from that search whose repository is the pin; the
    card is about the pin even on a day with none of them.
  - Automatic: the repository with the most of that day's commits; a tie
    goes to the one with the latest commit.
  - Automatic, today, no commits yet: the repo pushed to last
    (`GET /user/repos?sort=pushed&per_page=1`), shown as `No commits yet
    today`.
  - Automatic, a past day with no commits: no card.
- **Then, for that repo:** the nearest open milestone
  (`GET /repos/{o}/{r}/milestones?state=open&per_page=10`; `ProjectCard`
  picks the soonest due, undated ones after dated ones, rather than trusting
  GitHub's ordering of nulls); with
  none, the open issues (`GET /search/issues?q=repo:{o}/{r}+is:issue+
  is:open&sort=created&order=desc&per_page=2`, whose `total_count` is the
  count and whose items are the two newest; pull requests are excluded by
  `is:issue`).

Two or three requests per day viewed. Search allows 30 requests a minute
per person, far above what a person paging through days does.

### Caching

`GitHubDayCache` keeps one result per day per account, encoded to a file in
the account's caches directory, in the manner of the forecast cache:

- A past day's result never changes once the day has ended, so it is kept
  for good (until Disconnect, which clears the cache).
- Today's result is refreshed when the day screen opens if it is more than
  five minutes old, and always on pull to refresh.
- Changing the pin clears the cache.

### Where it plugs in

`DayProviders` gains `github: (any GitHubDayProviding)?`, nil when not
connected. `DayViewModel` asks it for the day alongside the weather;
`DayBriefing` gains `project: ProjectCardState?`.

### Failures

| What happens | The card |
|---|---|
| Not connected | No card, and no prompt on the day screen; connecting lives in Settings |
| Offline, rate limited, or 5xx | The cached result with `As of 9:40` in quiet ink under it; no card if nothing is cached |
| 401 (token revoked on github.com) | `GitHub needs reconnecting` as one row that opens Settings, and the token is kept until the person reconnects or disconnects |
| The pinned repo is gone or no longer readable (404) | Falls back to Automatic for that day, and the Settings row says `Pinned repo not found` |

## 3. The card

### The tested value, in `LifeOSKit`

`ProjectCard` in `Integrations` (the GitHub wire types live beside it in
`GitHubWireFormat.swift`) is built by a pure function from the decoded
search results, the pin, the day's placement and the milestone or issues,
with no network code in it:

- `repo: String` (`name`, not `owner/name`), `repoURL: URL`
- `commitCount: Int`, `commits: [ProjectCommit]` (subject line only, the
  first line of the message, newest first, with its `html_url`)
- `isTodayWithoutCommits: Bool`
- `followUp: ProjectFollowUp?`: `.milestone(title, open, total, due: Date?,
  url)` or `.issues(count, newest: [ProjectIssue])`, nil when the repo has
  neither an open milestone nor an open issue
- `ProjectCardState`: `.card(ProjectCard, asOf: Date?)` or `.reconnect`

Wording, in `DesignSystem` as `ProjectHeadline` beside `DayHeadline`, tested:
`1 commit` / `6 commits` / `No commits yet today` / `No commits` (a
pinned repo on a past day with none); `Milestone 1.1 · 4 of 9
left · due Oct 20` or, undated, `Milestone 1.1 · 4 of 9 left`, or when all
are closed `Milestone 1.1 · all 9 done`; `1 open issue` / `3 open issues`;
`4 more`; `As of 9:40`.

### On the day screen

- `DaySection` gains `.project`, after `.checklist` and before `.readings`,
  on today and past days, not on days ahead. `DaySections.visible(for:)`
  lists it; the section is skipped when `briefing.project` is nil, and the
  sections after it renumber (the existing `number(of:in:)` already counts
  only what is shown).
- Header: `EditorialSectionHeader(index:title: "Project")` with the repo
  name in its trailing slot as a `.plain` link to the repo.
- Body, all `.plain` rows that open GitHub in Safari through
  `openURL`:
  - the count line in `LifeOSType.body`;
  - the first three commit subjects in `LifeOSType.secondary`, quiet ink,
    one line each, truncated at the tail; `4 more` (an
    `.editorial(.quiet, size: .compact)` button) expands the rest in place;
  - a hairline, then the milestone line, or the issue count line and the
    two newest issue titles in quiet ink.
- No accent. `As of 9:40` in `LifeOSType.caption`, quiet ink, when the card
  is from the cache after a failed refresh.
- `.reconnect`: one row, `GitHub needs reconnecting`, opening Settings
  through the shell profile's `open` (the same path the avatar uses).

## 4. Verification

- **Package tests:**
  - `ProjectCardTests`: the busiest repo wins, a tie goes to the latest
    commit, the pin wins and shows even with no commits, today with none
    takes the last-pushed repo, a past day with none has no card, the
    milestone comes before issues, a milestone without a due date, a repo
    with neither, subjects are first lines only.
  - `GitHubDayTests`: the day's bounds in New York and in Kolkata, the 23
    and 25 hour daylight-saving days, the search query string.
  - `ProjectHeadlineTests`: every line above, zero and one.
  - `GitHubOAuthTests`: the authorize URL, `state` mismatch rejected,
    `access_denied` read as cancel, the S256 challenge for a known verifier.
  - `GitHubWireFormatTests`: decoding recorded search, milestone and issue
    responses.
  - `GitHubDayCacheTests`: a past day is kept, today expires after five
    minutes, a pin change and Disconnect clear it.
- **Edge Function:** Deno tests for `github-token`: 401 without a session,
  400 passing GitHub's error through, 500 without configuration, `DELETE`
  revokes and treats an unknown token as success. GitHub's endpoints are
  stubbed; nothing reaches github.com in tests.
- `scripts/check-typography.sh` reports nothing new; the app, `AlmanacWidgets`
  (if `DesignSystem` changes reach it) and the package for macOS build.
- **Preview pages**, each with `--dark`: `day-github` (six commits, a
  milestone), `day-github-issues` (no milestone, three issues),
  `day-github-today-none` (`No commits yet today`), `day-github-reconnect`,
  `day-github-stale` (`As of 9:40`).
- **UI test** in `LIfeOSUITests`, on `day-github`: `4 more` expands to all
  six subjects.
- The owner connects a real account once and reads a day with commits.

## 5. Owner's steps

1. Register an OAuth App at github.com/settings/developers: name `Almanac`,
   homepage the app's site, callback `almanac://github-callback`.
2. `supabase secrets set GITHUB_CLIENT_ID=… GITHUB_CLIENT_SECRET=…` and
   deploy `github-token`.
3. Put the client id in `Config/App-Info.plist` as `GitHubClientID`.

## Out of scope

- Writing anything to GitHub.
- Pull-request review queues, notifications, CI status, contribution graphs.
- GitHub Enterprise hosts.
- The iPad estate's two-column Day (the card follows `readingWidth` like
  every other section).
- LIFO reading GitHub; widgets or the Watch showing the card.
- A GitHub App with per-repo read-only access (declined above; revisit if
  people object to the `repo` scope).
