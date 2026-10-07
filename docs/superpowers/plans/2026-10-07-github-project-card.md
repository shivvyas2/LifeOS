# GitHub project card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person connects GitHub in Settings, and each day screen (today and past days) shows a Project section: the repo they worked in, that day's commits, then the repo's nearest milestone or its open issues.

**Architecture:** Everything that decides anything is a tested value in `LifeOSKit`: the wording and the new section in `DesignSystem`; the wire types, the day's bounds and search query, the card builder, the OAuth URL and callback, the token store, the per-day cache and a loader that talks through an injected transport in `Integrations`. A stateless `github-token` Edge Function swaps the sign-in code for a token and revokes it; its logic lives in `_shared/github.ts` with Deno tests. The app adds a `GitHubConnectionViewModel` (owned by `IntegrationContainer`, put in the environment), a GitHub row with a pin picker in Connections, a `github` provider on `DayProviders`, and the section on `DayScreen`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing in `LifeOSKit`, `AuthenticationServices`, `CryptoKit`, Keychain, Deno for the Edge Function, XCUITest in `LIfeOSUITests`.

**Spec:** `docs/superpowers/specs/2026-10-07-github-project-card-design.md`

## Global Constraints

- OAuth App scope exactly `repo read:user`; callback exactly `almanac://github-callback`; PKCE S256 plus a random `state`.
- The Edge Function stores nothing: no table, no logging of a token. GitHub OAuth App tokens do not expire; there is no refresh path.
- The token lives only in the Keychain, per account (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), like `KeychainFitbitAuthStore`.
- API calls go from the phone to `https://api.github.com` with `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`.
- "The day" is `Calendar.current`'s `[startOfDay, startOfDay + 1 day)`; commits are matched by **author date**.
- Copy, verbatim: `1 commit`, `6 commits`, `No commits yet today`, `No commits`, `Milestone 1.1 · 4 of 9 left · due Oct 20`, `Milestone 1.1 · 4 of 9 left`, `Milestone 1.1 · all 9 done`, `1 open issue`, `3 open issues`, `4 more`, `As of 9:40`, `GitHub needs reconnecting`, `Pinned repo not found`, `Connected as @login`, `Pin a repo`, `Automatic`.
- The section is titled `Project`, sits after Checklist and before Readings, on today and past days only.
- Paper, ink, hairlines, quiet ink; no accent on the card; buttons `.editorial(role)` or `.plain`; fonts only from `LifeOSType`/`Editorial`. `scripts/check-typography.sh` reports nothing new (compare with line numbers stripped).
- `LifeOSKit` also builds for macOS 26: no UIKit in `Integrations` or `DesignSystem` files.
- `LIfeOS/` is a synchronized folder: new files need no `project.pbxproj` edit. `LIfeOSUITests/` is not: a new UI test file is added to that target with the `xcodeproj` gem (Task 8).
- Commits: conventional `type(scope): summary`, no em dashes, no Claude attribution in commits or the PR body.
- Worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/github-card` on `feat/github-card`, cut from main 2dab4b0. Simulator `CalendarAsk iPhone 17` `B192EA65-BAA2-4814-A298-94A2F0C8FC87`; DerivedData `~/Library/Developer/Xcode/DerivedData/github-card`. `$W` is the executor's ledger workspace.

## Review Focus

1. A day with commits in several repos must show the busiest, and a tie must go to the repo with the latest commit, not to whichever the API listed first: `ProjectCardTests.aTieGoesToTheLatestCommit` in Task 2.
2. Day bounds around a daylight-saving change must cover the whole local day (23 or 25 hours), or the first or last hour's commits vanish: `GitHubDayTests.springForwardIsTwentyThreeHours` in Task 2.
3. A token revoked on github.com must turn the card into `GitHub needs reconnecting`, never an empty day or a cached card forever: `GitHubDayLoaderTests.aRevokedTokenAsksToReconnect` in Task 4.
4. A pinned repo that was deleted or lost access must fall back to Automatic and say so, not blank the card: `GitHubDayLoaderTests.aMissingPinFallsBackToAutomatic` in Task 4.
5. A past day fetched while it was still today must refresh later; only a result fetched after the day ended is final: `GitHubDayCacheTests.aPastDayFetchedBeforeItEndedIsStale` in Task 4.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/DayHeadline.swift` | `DaySection.project`, `DaySections.visible` |
| `LifeOSKit/Sources/DesignSystem/ProjectHeadline.swift` (new) | The card's wording |
| `LifeOSKit/Sources/Integrations/GitHubWireFormat.swift` (new) | Decodable API types and the shared decoder |
| `LifeOSKit/Sources/Integrations/GitHubDay.swift` (new) | A day's bounds and the commit search query |
| `LifeOSKit/Sources/Integrations/ProjectCard.swift` (new) | `ProjectCard`, `ProjectFollowUp`, `ProjectCardState`, the builder |
| `LifeOSKit/Sources/Integrations/GitHubOAuth.swift` (new) | Authorize URL, callback parsing |
| `LifeOSKit/Sources/Integrations/GitHubTokenStore.swift` (new) | Keychain and in-memory token and pending stores |
| `LifeOSKit/Sources/Integrations/GitHubDayCache.swift` (new) | Per-day results in the account's defaults |
| `LifeOSKit/Sources/Integrations/GitHubDayLoader.swift` (new) | The calls, through `GitHubTransport`, into a `ProjectCardState` |
| `LifeOSKit/Tests/IntegrationsTests/GitHub*Tests.swift`, `ProjectCardTests.swift` (new) | Their tests |
| `supabase/functions/_shared/github.ts`, `github_test.ts`, `supabase/functions/github-token/index.ts` (new) | The exchange and revoke |
| `LIfeOS/Features/Settings/Model/AppConfig.swift`, `Config/App-Info.plist`, `Config/Secrets.example.xcconfig` | `GitHubClientID`, the function URL |
| `LIfeOS/Features/Settings/ViewModel/GitHubConnectionViewModel.swift` (new) | Connect, disconnect, repos, the pin, the day provider |
| `LIfeOS/Components/Model/IntegrationContainer.swift`, `LIfeOS/App/RootView.swift` | Own it, inject it |
| `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift` | The GitHub card and pin picker |
| `LIfeOS/Features/Day/Model/WeatherProviding.swift`, `DayBriefing.swift`, `DayStubs.swift` | `github` provider, `project` field, a stub |
| `LIfeOS/Features/Day/ViewModel/DayViewModel.swift`, `View/DayScreen.swift`, `View/DaySections.swift` | Load and draw the section |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `Health/View/HealthActivityDesignPreview.swift` | Five `day-github*` pages |
| `LIfeOSUITests/DayProjectUITests.swift` (new) | `4 more` expands |

---

### Task 0: Worktree and baselines

- [ ] **Step 1:**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/github-card
git log --oneline -2; ls Config/Secrets.xcconfig && git check-ignore -q Config/Secrets.xcconfig && echo ok
(cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1)
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort > $W/typo-base.txt
(cd supabase/functions/_shared && deno test --allow-env 2>&1 | tail -2)
```

Expected: the spec commit on top of 2dab4b0; 1522 tests in 216 suites pass; Deno's suite passes (note its count; `lifo_live_test.ts` skips itself offline).

- [ ] **Step 2: Commit the plan**: `git add docs/superpowers/plans/2026-10-07-github-project-card.md && git commit -m "docs(plans): the GitHub project card"`

---

### Task 1: The section and its wording

**Files:** Modify `LifeOSKit/Sources/DesignSystem/DayHeadline.swift:61-77`; Create `LifeOSKit/Sources/DesignSystem/ProjectHeadline.swift`; Test `LifeOSKit/Tests/DesignSystemTests/DayHeadlineTests.swift:47-51`, Create `LifeOSKit/Tests/DesignSystemTests/ProjectHeadlineTests.swift`.

**Interfaces — Produces:** `DaySection.project`; `ProjectHeadline.commits(_ count: Int, isTodayWithoutCommits: Bool) -> String`, `.milestone(title: String, open: Int, total: Int, due: Date?, calendar: Calendar) -> String`, `.issues(_ count: Int) -> String`, `.more(_ count: Int) -> String`, `.asOf(_ date: Date, calendar: Calendar) -> String`.

- [ ] **Step 1: Failing tests.** In `DayHeadlineTests`, replace lines 47-48 with:

```swift
        #expect(DaySections.visible(for: .today) == [.weather, .agenda, .checklist, .project, .readings, .money, .nudges])
        #expect(DaySections.visible(for: .past(daysAgo: 3)) == [.agenda, .checklist, .project, .readings, .money, .nudges])
```

`ProjectHeadlineTests.swift`:

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct ProjectHeadlineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func commitCounts() {
        #expect(ProjectHeadline.commits(1, isTodayWithoutCommits: false) == "1 commit")
        #expect(ProjectHeadline.commits(6, isTodayWithoutCommits: false) == "6 commits")
        #expect(ProjectHeadline.commits(0, isTodayWithoutCommits: true) == "No commits yet today")
        #expect(ProjectHeadline.commits(0, isTodayWithoutCommits: false) == "No commits")
    }

    @Test func milestones() {
        let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        #expect(ProjectHeadline.milestone(title: "1.1", open: 4, total: 9, due: due, calendar: calendar)
                == "Milestone 1.1 · 4 of 9 left · due Oct 20")
        #expect(ProjectHeadline.milestone(title: "1.1", open: 4, total: 9, due: nil, calendar: calendar)
                == "Milestone 1.1 · 4 of 9 left")
        #expect(ProjectHeadline.milestone(title: "1.1", open: 0, total: 9, due: due, calendar: calendar)
                == "Milestone 1.1 · all 9 done")
    }

    @Test func issuesMoreAndAsOf() {
        #expect(ProjectHeadline.issues(1) == "1 open issue")
        #expect(ProjectHeadline.issues(3) == "3 open issues")
        #expect(ProjectHeadline.more(4) == "4 more")
        let time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9, minute: 40))!
        #expect(ProjectHeadline.asOf(time, calendar: calendar) == "As of 9:40")
    }
}
```

- [ ] **Step 2:** `cd LifeOSKit && swift test --filter "ProjectHeadline|DayHeadline"` → fails: `ProjectHeadline` not in scope, `.project` not a member.

- [ ] **Step 3: Implement.** `DayHeadline.swift`: `case weather, agenda, checklist, project, readings, money, nudges`, and `.past: [.agenda, .checklist, .project, .readings, .money, .nudges]` (`.today` stays `DaySection.allCases`). `ProjectHeadline.swift`:

```swift
import Foundation

/// The project card's lines, as words. Kept apart from the card so every
/// count and the milestone's three shapes are tested.
public enum ProjectHeadline {
    public static func commits(_ count: Int, isTodayWithoutCommits: Bool) -> String {
        if count == 0 { return isTodayWithoutCommits ? "No commits yet today" : "No commits" }
        return count == 1 ? "1 commit" : "\(count) commits"
    }

    public static func milestone(title: String, open: Int, total: Int, due: Date?, calendar: Calendar) -> String {
        if open == 0 { return "Milestone \(title) · all \(total) done" }
        let head = "Milestone \(title) · \(open) of \(total) left"
        guard let due else { return head }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return "\(head) · due \(due.formatted(style))"
    }

    public static func issues(_ count: Int) -> String {
        count == 1 ? "1 open issue" : "\(count) open issues"
    }

    public static func more(_ count: Int) -> String { "\(count) more" }

    public static func asOf(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        style.timeZone = calendar.timeZone
        return "As of \(date.formatted(style))"
    }
}
```

The formatter follows the user's locale on purpose. If the test machine's locale prints `09:40`, pin the test (not the code) by setting `calendar.locale = Locale(identifier: "en_US")` in the test's calendar and reading `calendar.locale` into `style.locale` in `asOf` and `milestone`; ledger it.

- [ ] **Step 4:** `swift test --filter "ProjectHeadline|DayHeadline"` passes; whole suite passes.
- [ ] **Step 5:** `git commit -m "feat(design): a Project section on the day, and the words its card uses"`

---

### Task 2: Wire types, the day's bounds, and the card builder

**Files:** Create `LifeOSKit/Sources/Integrations/GitHubWireFormat.swift`, `GitHubDay.swift`, `ProjectCard.swift`; Test `LifeOSKit/Tests/IntegrationsTests/GitHubWireFormatTests.swift`, `GitHubDayTests.swift`, `ProjectCardTests.swift`.

**Interfaces — Produces:**
- `GitHubCommitSearch { items: [Item] }`, `Item { sha: String, htmlUrl: URL, commit: { message: String, author: { date: Date } }, repository: GitHubRepoRef }`; `GitHubRepoRef { name: String, fullName: String, htmlUrl: URL }` (also decodes `/user/repos` rows, with optional `pushedAt: Date?`); `GitHubMilestone { title: String, openIssues: Int, closedIssues: Int, dueOn: Date?, htmlUrl: URL }`; `GitHubIssueSearch { totalCount: Int, items: [Issue] }`, `Issue { title: String, htmlUrl: URL }`; `GitHubUser { login: String }`; `GitHubWire.decoder: JSONDecoder` (snake case, ISO 8601).
- `GitHubDay.bounds(for day: Date, calendar: Calendar) -> (start: Date, end: Date)`; `GitHubDay.commitQuery(login: String, day: Date, calendar: Calendar) -> String`.
- `ProjectCommit: Codable, Equatable { subject: String, url: URL }`; `ProjectIssue: Codable, Equatable { title: String, url: URL }`; `ProjectFollowUp: Codable, Equatable { case milestone(title: String, open: Int, total: Int, due: Date?, url: URL); case issues(count: Int, newest: [ProjectIssue]) }`; `ProjectCard: Codable, Equatable { repo: String, repoURL: URL, commitCount: Int, commits: [ProjectCommit], isTodayWithoutCommits: Bool, followUp: ProjectFollowUp? }`; `ProjectCardState: Equatable { case card(ProjectCard, asOf: Date?); case reconnect }`.
- `ProjectCardBuilder.busiestRepo(in items: [GitHubCommitSearch.Item]) -> GitHubRepoRef?`; `.commits(in items:, repo fullName: String) -> [ProjectCommit]`; `.followUp(milestones: [GitHubMilestone], issues: GitHubIssueSearch?) -> ProjectFollowUp?`; `.card(repo: GitHubRepoRef, commits: [ProjectCommit], isToday: Bool, followUp: ProjectFollowUp?) -> ProjectCard`.

- [ ] **Step 1: Failing tests.**

`GitHubWireFormatTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubWireFormatTests {
    @Test func decodesACommitSearch() throws {
        let json = """
        {"total_count":1,"items":[{"sha":"abc","html_url":"https://github.com/o/r/commit/abc",
          "commit":{"message":"fix(notes): close the gaps\\n\\nBody text","author":{"date":"2026-10-07T14:03:00Z"}},
          "repository":{"name":"r","full_name":"o/r","html_url":"https://github.com/o/r"}}]}
        """
        let search = try GitHubWire.decoder.decode(GitHubCommitSearch.self, from: Data(json.utf8))
        #expect(search.items.first?.repository.fullName == "o/r")
        #expect(search.items.first?.commit.author.date == ISO8601DateFormatter().date(from: "2026-10-07T14:03:00Z"))
    }

    @Test func decodesMilestonesWithAndWithoutADueDate() throws {
        let json = """
        [{"title":"1.1","open_issues":4,"closed_issues":5,"due_on":"2026-10-20T07:00:00Z","html_url":"https://github.com/o/r/milestone/1"},
         {"title":"Later","open_issues":2,"closed_issues":0,"due_on":null,"html_url":"https://github.com/o/r/milestone/2"}]
        """
        let milestones = try GitHubWire.decoder.decode([GitHubMilestone].self, from: Data(json.utf8))
        #expect(milestones.map(\.dueOn == nil) == [false, true])
    }

    @Test func decodesAnIssueSearch() throws {
        let json = """
        {"total_count":3,"items":[{"title":"Crash on launch","html_url":"https://github.com/o/r/issues/9"}]}
        """
        let search = try GitHubWire.decoder.decode(GitHubIssueSearch.self, from: Data(json.utf8))
        #expect(search.totalCount == 3)
    }
}
```

`GitHubDayTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubDayTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func theQueryCoversTheLocalDayByAuthorDate() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        #expect(GitHubDay.commitQuery(login: "shivvyas2", day: day, calendar: cal)
                == "author:shivvyas2 author-date:2026-10-07T00:00:00-04:00..2026-10-07T23:59:59-04:00")
    }

    @Test func aHalfHourZoneKeepsItsOffset() {
        let cal = calendar("Asia/Kolkata")
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 1))!
        #expect(GitHubDay.commitQuery(login: "a", day: day, calendar: cal)
                == "author:a author-date:2026-10-07T00:00:00+05:30..2026-10-07T23:59:59+05:30")
    }

    @Test func springForwardIsTwentyThreeHours() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let bounds = GitHubDay.bounds(for: day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 23 * 3600)
        #expect(GitHubDay.commitQuery(login: "a", day: day, calendar: cal)
                == "author:a author-date:2026-03-08T00:00:00-05:00..2026-03-08T23:59:59-04:00")
    }

    @Test func fallBackIsTwentyFiveHours() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let bounds = GitHubDay.bounds(for: day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 25 * 3600)
    }
}
```

`ProjectCardTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct ProjectCardTests {
    private func repo(_ name: String) -> GitHubRepoRef {
        GitHubRepoRef(name: name, fullName: "o/\(name)", htmlUrl: URL(string: "https://github.com/o/\(name)")!, pushedAt: nil)
    }

    private func item(_ repoName: String, at seconds: TimeInterval, message: String = "work") -> GitHubCommitSearch.Item {
        GitHubCommitSearch.Item(
            sha: UUID().uuidString, htmlUrl: URL(string: "https://github.com/o/\(repoName)/commit/x")!,
            commit: .init(message: message, author: .init(date: Date(timeIntervalSince1970: seconds))),
            repository: repo(repoName))
    }

    @Test func theBusiestRepoWins() {
        let items = [item("a", at: 300), item("b", at: 200), item("b", at: 100)]
        #expect(ProjectCardBuilder.busiestRepo(in: items)?.fullName == "o/b")
    }

    @Test func aTieGoesToTheLatestCommit() {
        let items = [item("a", at: 100), item("b", at: 300)]
        #expect(ProjectCardBuilder.busiestRepo(in: items)?.fullName == "o/b")
        #expect(ProjectCardBuilder.busiestRepo(in: items.reversed())?.fullName == "o/b")
    }

    @Test func noCommitsNoRepo() {
        #expect(ProjectCardBuilder.busiestRepo(in: []) == nil)
    }

    @Test func subjectsAreFirstLinesNewestFirstForThatRepoOnly() {
        let items = [item("a", at: 100, message: "older\n\nbody"), item("b", at: 150), item("a", at: 200, message: "newer")]
        #expect(ProjectCardBuilder.commits(in: items, repo: "o/a").map(\.subject) == ["newer", "older"])
    }

    @Test func theSoonestDueMilestoneComesFirstAndUndatedLast() {
        let undated = GitHubMilestone(title: "Later", openIssues: 1, closedIssues: 0, dueOn: nil, htmlUrl: URL(string: "https://x/2")!)
        let soon = GitHubMilestone(title: "1.1", openIssues: 4, closedIssues: 5, dueOn: Date(timeIntervalSince1970: 1000), htmlUrl: URL(string: "https://x/1")!)
        let later = GitHubMilestone(title: "2.0", openIssues: 9, closedIssues: 0, dueOn: Date(timeIntervalSince1970: 9000), htmlUrl: URL(string: "https://x/3")!)
        #expect(ProjectCardBuilder.followUp(milestones: [undated, later, soon], issues: nil)
                == .milestone(title: "1.1", open: 4, total: 9, due: Date(timeIntervalSince1970: 1000), url: URL(string: "https://x/1")!))
        #expect(ProjectCardBuilder.followUp(milestones: [undated], issues: nil)
                == .milestone(title: "Later", open: 1, total: 1, due: nil, url: URL(string: "https://x/2")!))
    }

    @Test func withoutAMilestoneTheIssuesFollow() {
        let issues = GitHubIssueSearch(totalCount: 3, items: [.init(title: "Crash", htmlUrl: URL(string: "https://x/9")!)])
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: issues)
                == .issues(count: 3, newest: [ProjectIssue(title: "Crash", url: URL(string: "https://x/9")!)]))
    }

    @Test func aRepoWithNeitherHasNoFollowUp() {
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: GitHubIssueSearch(totalCount: 0, items: [])) == nil)
        #expect(ProjectCardBuilder.followUp(milestones: [], issues: nil) == nil)
    }

    @Test func todayWithoutCommitsIsMarked() {
        let card = ProjectCardBuilder.card(repo: repo("a"), commits: [], isToday: true, followUp: nil)
        #expect(card.isTodayWithoutCommits)
        #expect(card.repo == "a")
        let past = ProjectCardBuilder.card(repo: repo("a"), commits: [], isToday: false, followUp: nil)
        #expect(!past.isTodayWithoutCommits)
    }
}
```

- [ ] **Step 2:** `swift test --filter "GitHubWireFormat|GitHubDay|ProjectCard"` fails to build (types missing).

- [ ] **Step 3: Implement.**

`GitHubWireFormat.swift`:

```swift
import Foundation

/// The few shapes the project card reads from GitHub's REST API.
public enum GitHubWire {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct GitHubRepoRef: Codable, Equatable, Sendable {
    public let name: String
    public let fullName: String
    public let htmlUrl: URL
    public var pushedAt: Date?

    public init(name: String, fullName: String, htmlUrl: URL, pushedAt: Date?) {
        self.name = name; self.fullName = fullName; self.htmlUrl = htmlUrl; self.pushedAt = pushedAt
    }
}

public struct GitHubCommitSearch: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        public struct Commit: Decodable, Sendable {
            public struct Author: Decodable, Sendable {
                public let date: Date
                public init(date: Date) { self.date = date }
            }
            public let message: String
            public let author: Author
            public init(message: String, author: Author) { self.message = message; self.author = author }
        }
        public let sha: String
        public let htmlUrl: URL
        public let commit: Commit
        public let repository: GitHubRepoRef
        public init(sha: String, htmlUrl: URL, commit: Commit, repository: GitHubRepoRef) {
            self.sha = sha; self.htmlUrl = htmlUrl; self.commit = commit; self.repository = repository
        }
    }
    public let items: [Item]
}

public struct GitHubMilestone: Decodable, Equatable, Sendable {
    public let title: String
    public let openIssues: Int
    public let closedIssues: Int
    public let dueOn: Date?
    public let htmlUrl: URL
    public init(title: String, openIssues: Int, closedIssues: Int, dueOn: Date?, htmlUrl: URL) {
        self.title = title; self.openIssues = openIssues; self.closedIssues = closedIssues
        self.dueOn = dueOn; self.htmlUrl = htmlUrl
    }
}

public struct GitHubIssueSearch: Decodable, Equatable, Sendable {
    public struct Issue: Decodable, Equatable, Sendable {
        public let title: String
        public let htmlUrl: URL
        public init(title: String, htmlUrl: URL) { self.title = title; self.htmlUrl = htmlUrl }
    }
    public let totalCount: Int
    public let items: [Issue]
    public init(totalCount: Int, items: [Issue]) { self.totalCount = totalCount; self.items = items }
}

public struct GitHubUser: Decodable, Sendable {
    public let login: String
}
```

`GitHubDay.swift`:

```swift
import Foundation

/// A local calendar day, as GitHub's search wants it.
public enum GitHubDay {
    public static func bounds(for day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// `author:<login> author-date:<start>..<end>`, inclusive at both ends,
    /// each written with its own offset so a daylight-saving day is right.
    /// Author date, so a commit rebased today stays on the day it was written.
    public static func commitQuery(login: String, day: Date, calendar: Calendar) -> String {
        let (start, end) = bounds(for: day, calendar: calendar)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        let last = end.addingTimeInterval(-1)
        func stamp(_ date: Date) -> String {
            formatter.timeZone = TimeZone(secondsFromGMT: calendar.timeZone.secondsFromGMT(for: date))
            return formatter.string(from: date)
        }
        return "author:\(login) author-date:\(stamp(start))..\(stamp(last))"
    }
}
```

`ISO8601DateFormatter` writes `Z` for a zero offset; that is valid for GitHub. If it writes `-0400` without the colon, add `.withColonSeparatorInTimeZone` to `formatOptions`.

`ProjectCard.swift`:

```swift
import Foundation

public struct ProjectCommit: Codable, Equatable, Sendable {
    public let subject: String
    public let url: URL
    public init(subject: String, url: URL) { self.subject = subject; self.url = url }
}

public struct ProjectIssue: Codable, Equatable, Sendable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

public enum ProjectFollowUp: Codable, Equatable, Sendable {
    case milestone(title: String, open: Int, total: Int, due: Date?, url: URL)
    case issues(count: Int, newest: [ProjectIssue])
}

/// What the day's Project section shows.
public struct ProjectCard: Codable, Equatable, Sendable {
    public let repo: String
    public let repoURL: URL
    public let commitCount: Int
    public let commits: [ProjectCommit]
    public let isTodayWithoutCommits: Bool
    public let followUp: ProjectFollowUp?
}

public enum ProjectCardState: Equatable, Sendable {
    /// `asOf` is set when a refresh failed and this is the cached card.
    case card(ProjectCard, asOf: Date?)
    case reconnect
}

/// Turns what GitHub returned into the card. No network here.
public enum ProjectCardBuilder {
    /// The repo with the most of the day's commits; a tie goes to the one
    /// whose latest commit is latest.
    public static func busiestRepo(in items: [GitHubCommitSearch.Item]) -> GitHubRepoRef? {
        let groups = Dictionary(grouping: items, by: \.repository.fullName)
        let best = groups.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            let left = lhs.value.map(\.commit.author.date).max() ?? .distantPast
            let right = rhs.value.map(\.commit.author.date).max() ?? .distantPast
            return left < right
        }
        return best?.value.first?.repository
    }

    public static func commits(in items: [GitHubCommitSearch.Item], repo fullName: String) -> [ProjectCommit] {
        items.filter { $0.repository.fullName == fullName }
            .sorted { $0.commit.author.date > $1.commit.author.date }
            .map { item in
                let subject = item.commit.message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? ""
                return ProjectCommit(subject: subject, url: item.htmlUrl)
            }
    }

    /// The soonest-due open milestone, undated ones after dated ones; with
    /// none, the open issues; with neither, nothing.
    public static func followUp(milestones: [GitHubMilestone], issues: GitHubIssueSearch?) -> ProjectFollowUp? {
        let ordered = milestones.sorted { lhs, rhs in
            switch (lhs.dueOn, rhs.dueOn) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.title < rhs.title
            }
        }
        if let first = ordered.first {
            return .milestone(title: first.title, open: first.openIssues,
                              total: first.openIssues + first.closedIssues, due: first.dueOn, url: first.htmlUrl)
        }
        guard let issues, issues.totalCount > 0 else { return nil }
        return .issues(count: issues.totalCount, newest: issues.items.prefix(2).map { ProjectIssue(title: $0.title, url: $0.htmlUrl) })
    }

    public static func card(repo: GitHubRepoRef, commits: [ProjectCommit], isToday: Bool, followUp: ProjectFollowUp?) -> ProjectCard {
        ProjectCard(repo: repo.name, repoURL: repo.htmlUrl, commitCount: commits.count, commits: commits,
                    isTodayWithoutCommits: isToday && commits.isEmpty, followUp: followUp)
    }
}
```

`GitHubRepoRef` is `Codable` with a `pushedAt` the search payload lacks; it decodes as nil because the property is optional.

- [ ] **Step 4:** the three filters pass; whole suite passes.
- [ ] **Step 5:** `git commit -m "feat(integrations): GitHub's shapes, a local day as a commit search, and the project card"`

---

### Task 3: Sign-in pieces in the package

**Files:** Create `LifeOSKit/Sources/Integrations/GitHubOAuth.swift`, `GitHubTokenStore.swift`; Test `LifeOSKit/Tests/IntegrationsTests/GitHubOAuthTests.swift`.

**Interfaces — Produces:** `GitHubOAuth.scope = "repo read:user"`, `GitHubOAuth.redirectURI = "almanac://github-callback"`, `GitHubOAuth.session(clientID: String, state: String = random, verifier: String = random) -> (url: URL, state: String, verifier: String)`, `GitHubOAuth.code(from url: URL, expectedState: String) throws -> String`, `GitHubOAuth.state(in url: URL) -> String?`, `GitHubAuthError { case denied, stateMismatch, missingCode }`; `GitHubPendingAuth: Codable { verifier, state, createdAt }`; `GitHubConnection: Codable, Equatable { token: String, login: String }`; `protocol GitHubTokenStoring: Sendable { func load() -> GitHubConnection?; func save(_:) throws; func clear(); func savePending(_:) throws; func pending() -> GitHubPendingAuth?; func clearPending() }`; `KeychainGitHubTokenStore`, `InMemoryGitHubTokenStore`.

- [ ] **Step 1: Failing tests.**

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubOAuthTests {
    @Test func theAuthorizeURLAsksForRepoAndReadUserWithPKCE() throws {
        let session = GitHubOAuth.session(clientID: "abc", state: "s1", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let items = URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(session.url.absoluteString.hasPrefix("https://github.com/login/oauth/authorize?"))
        #expect(value("client_id") == "abc")
        #expect(value("redirect_uri") == "almanac://github-callback")
        #expect(value("scope") == "repo read:user")
        #expect(value("state") == "s1")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func theCodeComesBackWhenTheStateMatches() throws {
        let url = URL(string: "almanac://github-callback?code=xyz&state=s1")!
        #expect(try GitHubOAuth.code(from: url, expectedState: "s1") == "xyz")
        #expect(GitHubOAuth.state(in: url) == "s1")
    }

    @Test func aMismatchedStateIsRejected() {
        let url = URL(string: "almanac://github-callback?code=xyz&state=other")!
        #expect(throws: GitHubAuthError.stateMismatch) { try GitHubOAuth.code(from: url, expectedState: "s1") }
    }

    @Test func accessDeniedIsACancel() {
        let url = URL(string: "almanac://github-callback?error=access_denied&state=s1")!
        #expect(throws: GitHubAuthError.denied) { try GitHubOAuth.code(from: url, expectedState: "s1") }
    }

    @Test func theInMemoryStoreKeepsOneConnection() throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubConnection(token: "t", login: "me"))
        #expect(store.load()?.login == "me")
        store.clear()
        #expect(store.load() == nil)
    }
}
```

(The challenge for that verifier is RFC 7636's own example.)

- [ ] **Step 2:** `swift test --filter GitHubOAuth` fails to build.

- [ ] **Step 3: Implement.** `GitHubOAuth.swift`:

```swift
import Foundation

public enum GitHubAuthError: Error, Equatable {
    case denied, stateMismatch, missingCode
}

/// The authorize URL and the callback for a GitHub OAuth App, with PKCE.
public enum GitHubOAuth {
    public static let scope = "repo read:user"
    public static let redirectURI = "almanac://github-callback"

    public static func session(
        clientID: String,
        state: String = FitbitOAuth.randomURLSafeString(byteCount: 16),
        verifier: String = FitbitOAuth.randomURLSafeString()
    ) -> (url: URL, state: String, verifier: String) {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: FitbitOAuth.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return (components.url!, state, verifier)
    }

    public static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
    }

    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" })?.value == "access_denied" { throw GitHubAuthError.denied }
        guard state(in: url) == expectedState else { throw GitHubAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GitHubAuthError.missingCode
        }
        return code
    }
}
```

`FitbitOAuth.challenge` is `static` without `public`; it is internal to `Integrations`, which this file shares. `GitHubTokenStore.swift`: `GitHubPendingAuth` (`verifier`, `state`, `createdAt = .now`, `isFresh(now:) -> Bool` within 10 minutes), `GitHubConnection`, `GitHubTokenStoring`, `KeychainGitHubTokenStore` written on the pattern of `KeychainFitbitAuthStore` (service `ai.lifeos.github`, account from `KeychainAuthSessionStore.currentAccountKey`, two items: `account` for the connection and `account + ".pending"` for the pending auth, same `read`/`write` helpers and accessibility, a `GitHubTokenStoreError.keychain(OSStatus)`), and `InMemoryGitHubTokenStore` (`final class`, `@unchecked Sendable`, a lock-free pair of optionals, as `InMemoryFitbitAuthStore` does).

- [ ] **Step 4:** `swift test --filter GitHubOAuth` passes; whole suite passes; `swift build` (macOS) completes.
- [ ] **Step 5:** `git commit -m "feat(integrations): GitHub sign-in with PKCE, and a token kept per account in the Keychain"`

---

### Task 4: The cache and the loader

**Files:** Create `LifeOSKit/Sources/Integrations/GitHubDayCache.swift`, `GitHubDayLoader.swift`; Test `LifeOSKit/Tests/IntegrationsTests/GitHubDayCacheTests.swift`, `GitHubDayLoaderTests.swift`.

**Interfaces — Consumes:** Task 2's types and builder, Task 3's `GitHubConnection`. **Produces:**
- `GitHubDayCache(defaults: UserDefaults)`: `entry(for day: Date, calendar:) -> GitHubDayCache.Entry?` where `Entry: Codable { card: ProjectCard?; fetchedAt: Date }`; `store(_ card: ProjectCard?, for day: Date, fetchedAt: Date = .now, calendar:)`; `isFresh(_ entry: Entry, for day: Date, now: Date, calendar:) -> Bool`; `clear()`. Kept: 120 most recently fetched days.
- `protocol GitHubTransport: Sendable { func get(_ url: URL, token: String) async throws -> (Data, Int) }`; `URLSessionGitHubTransport`.
- `GitHubDayLoader(transport:connection:pinnedRepo:calendar:)`: `func load(day: Date, isToday: Bool) async throws -> GitHubDayLoader.Result` where `Result: Equatable { state: ProjectCardState?; pinMissing: Bool }`. Throws `GitHubLoadError.unavailable(Int)` on any non-2xx other than 401 (and other than the pinned repo's 404).
- `GitHubAPI.url(_ path: String, query: [String: String]) -> URL` on `https://api.github.com`.

- [ ] **Step 1: Failing tests.**

`GitHubDayCacheTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubDayCacheTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func defaults() -> UserDefaults {
        let name = "github.cache.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }
    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
    private let card = ProjectCard(repo: "r", repoURL: URL(string: "https://github.com/o/r")!, commitCount: 0,
                                   commits: [], isTodayWithoutCommits: false, followUp: nil)

    @Test func aPastDayFetchedAfterItEndedIsKept() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(6), calendar: calendar)
        let entry = cache.entry(for: day(5), calendar: calendar)!
        #expect(cache.isFresh(entry, for: day(5), now: day(30), calendar: calendar))
    }

    @Test func aPastDayFetchedBeforeItEndedIsStale() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(5), calendar: calendar)
        let entry = cache.entry(for: day(5), calendar: calendar)!
        #expect(!cache.isFresh(entry, for: day(5), now: day(7), calendar: calendar))
    }

    @Test func todayIsFreshForFiveMinutes() {
        let cache = GitHubDayCache(defaults: defaults())
        let now = day(7)
        cache.store(card, for: now, fetchedAt: now, calendar: calendar)
        let entry = cache.entry(for: now, calendar: calendar)!
        #expect(cache.isFresh(entry, for: now, now: now.addingTimeInterval(299), calendar: calendar))
        #expect(!cache.isFresh(entry, for: now, now: now.addingTimeInterval(301), calendar: calendar))
    }

    @Test func aDayWithNoCardIsRememberedAsNone() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(nil, for: day(5), fetchedAt: day(6), calendar: calendar)
        #expect(cache.entry(for: day(5), calendar: calendar) != nil)
        #expect(cache.entry(for: day(5), calendar: calendar)?.card == nil)
    }

    @Test func clearForgetsEverything() {
        let cache = GitHubDayCache(defaults: defaults())
        cache.store(card, for: day(5), fetchedAt: day(6), calendar: calendar)
        cache.clear()
        #expect(cache.entry(for: day(5), calendar: calendar) == nil)
    }
}
```

`GitHubDayLoaderTests.swift` (a stub transport answers by path prefix):

```swift
import Testing
import Foundation
@testable import Integrations

private final class StubTransport: GitHubTransport, @unchecked Sendable {
    var routes: [(String, Int, String)] = []   // path prefix, status, body
    private(set) var requested: [URL] = []
    func get(_ url: URL, token: String) async throws -> (Data, Int) {
        requested.append(url)
        let path = url.path + "?" + (url.query ?? "")
        guard let route = routes.first(where: { path.hasPrefix($0.0) }) else { return (Data("{}".utf8), 404) }
        return (Data(route.2.utf8), route.1)
    }
}

@Suite struct GitHubDayLoaderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))! }
    private let connection = GitHubConnection(token: "t", login: "me")

    private func commit(_ repo: String, _ hour: Int, _ message: String = "work") -> String {
        """
        {"sha":"\(UUID().uuidString)","html_url":"https://github.com/o/\(repo)/commit/x",
         "commit":{"message":"\(message)","author":{"date":"2026-10-07T\(String(format: "%02d", hour)):00:00Z"}},
         "repository":{"name":"\(repo)","full_name":"o/\(repo)","html_url":"https://github.com/o/\(repo)"}}
        """
    }

    private func loader(_ transport: StubTransport, pin: String? = nil) -> GitHubDayLoader {
        GitHubDayLoader(transport: transport, connection: connection, pinnedRepo: pin, calendar: calendar)
    }

    @Test func theBusiestRepoWithItsMilestone() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9)),\#(commit("b", 10)),\#(commit("b", 11))]}"#),
            ("/repos/o/b/milestones", 200, #"[{"title":"1.1","open_issues":4,"closed_issues":5,"due_on":null,"html_url":"https://github.com/o/b/milestone/1"}]"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: false)
        guard case .card(let card, let asOf)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "b")
        #expect(card.commitCount == 2)
        #expect(asOf == nil)
        #expect(card.followUp == .milestone(title: "1.1", open: 4, total: 9, due: nil, url: URL(string: "https://github.com/o/b/milestone/1")!))
        #expect(!transport.requested.contains { $0.path.hasPrefix("/search/issues") })
    }

    @Test func withoutAMilestoneTheIssuesAreAsked() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/a/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":3,"items":[{"title":"Crash","html_url":"https://github.com/o/a/issues/9"}]}"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.followUp == .issues(count: 3, newest: [ProjectIssue(title: "Crash", url: URL(string: "https://github.com/o/a/issues/9")!)]))
        let issueQuery = transport.requested.first { $0.path == "/search/issues" }?.query ?? ""
        #expect(issueQuery.contains("is:issue") || issueQuery.contains("is%3Aissue"))
    }

    @Test func aPastDayWithoutCommitsHasNoCard() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 200, #"{"items":[]}"#)]
        let result = try await loader(transport).load(day: day, isToday: false)
        #expect(result.state == nil)
    }

    @Test func todayWithoutCommitsShowsTheLastPushedRepo() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[]}"#),
            ("/user/repos", 200, #"[{"name":"c","full_name":"o/c","html_url":"https://github.com/o/c","pushed_at":"2026-10-06T20:00:00Z"}]"#),
            ("/repos/o/c/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport).load(day: day, isToday: true)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "c")
        #expect(card.isTodayWithoutCommits)
        #expect(card.followUp == nil)
    }

    @Test func thePinWinsEvenWithoutCommitsInIt() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/p/milestones", 200, "[]"),
            ("/repos/o/p", 200, #"{"name":"p","full_name":"o/p","html_url":"https://github.com/o/p"}"#),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport, pin: "o/p").load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "p")
        #expect(card.commitCount == 0)
        #expect(!result.pinMissing)
    }

    @Test func aMissingPinFallsBackToAutomatic() async throws {
        let transport = StubTransport()
        transport.routes = [
            ("/search/commits", 200, #"{"items":[\#(commit("a", 9))]}"#),
            ("/repos/o/gone", 404, #"{"message":"Not Found"}"#),
            ("/repos/o/a/milestones", 200, "[]"),
            ("/search/issues", 200, #"{"total_count":0,"items":[]}"#),
        ]
        let result = try await loader(transport, pin: "o/gone").load(day: day, isToday: false)
        guard case .card(let card, _)? = result.state else { Issue.record("no card"); return }
        #expect(card.repo == "a")
        #expect(result.pinMissing)
    }

    @Test func aRevokedTokenAsksToReconnect() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 401, #"{"message":"Bad credentials"}"#)]
        let result = try await loader(transport).load(day: day, isToday: true)
        #expect(result.state == .reconnect)
    }

    @Test func anOutageThrows() async {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 503, "")]
        await #expect(throws: GitHubLoadError.unavailable(503)) {
            _ = try await loader(transport).load(day: day, isToday: true)
        }
    }

    @Test func theSearchAsksForTheLocalDay() async throws {
        let transport = StubTransport()
        transport.routes = [("/search/commits", 200, #"{"items":[]}"#)]
        _ = try await loader(transport).load(day: day, isToday: false)
        let query = URLComponents(url: transport.requested[0], resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
        #expect(query == "author:me author-date:2026-10-07T00:00:00Z..2026-10-07T23:59:59Z")
    }
}
```

- [ ] **Step 2:** `swift test --filter "GitHubDayCache|GitHubDayLoader"` fails to build.

- [ ] **Step 3: Implement.** `GitHubDayCache.swift`:

```swift
import Foundation

/// One result per day, in the account's defaults, as the forecast cache does.
/// A day's result is final once it was fetched after that day ended; today's
/// is fresh for five minutes.
public struct GitHubDayCache {
    public struct Entry: Codable, Equatable {
        public let card: ProjectCard?
        public let fetchedAt: Date
    }

    private let defaults: UserDefaults
    private static let key = "github.days"
    private static let kept = 120
    public static let todayFreshness: TimeInterval = 5 * 60

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func entry(for day: Date, calendar: Calendar = .current) -> Entry? {
        all()[WeatherCache.dayKey(day, calendar: calendar)]
    }

    public func store(_ card: ProjectCard?, for day: Date, fetchedAt: Date = .now, calendar: Calendar = .current) {
        var entries = all()
        entries[WeatherCache.dayKey(day, calendar: calendar)] = Entry(card: card, fetchedAt: fetchedAt)
        let kept = entries.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.kept)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func isFresh(_ entry: Entry, for day: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let end = GitHubDay.bounds(for: day, calendar: calendar).end
        if entry.fetchedAt >= end { return true }
        return now.timeIntervalSince(entry.fetchedAt) < Self.todayFreshness && now < end
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }
}
```

(`WeatherCache` lives in `AppSurfaces`, which `Integrations` depends on; add `import AppSurfaces`.)

`GitHubDayLoader.swift`:

```swift
import Foundation

public protocol GitHubTransport: Sendable {
    func get(_ url: URL, token: String) async throws -> (Data, Int)
}

public struct URLSessionGitHubTransport: GitHubTransport {
    public init() {}
    public func get(_ url: URL, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum GitHubLoadError: Error, Equatable {
    case unavailable(Int)
}

enum GitHubAPI {
    static func url(_ path: String, query: [(String, String)] = []) -> URL {
        var components = URLComponents(string: "https://api.github.com")!
        components.path = path
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        return components.url!
    }
}

/// The day's project card: two or three requests, decided by the builder.
public struct GitHubDayLoader: Sendable {
    public struct Result: Equatable, Sendable {
        public let state: ProjectCardState?
        public let pinMissing: Bool
    }

    private struct Unauthorized: Error {}
    private struct NotFound: Error {}

    let transport: any GitHubTransport
    let connection: GitHubConnection
    let pinnedRepo: String?
    let calendar: Calendar

    public init(transport: any GitHubTransport, connection: GitHubConnection, pinnedRepo: String?, calendar: Calendar = .current) {
        self.transport = transport; self.connection = connection; self.pinnedRepo = pinnedRepo; self.calendar = calendar
    }

    public func load(day: Date, isToday: Bool) async throws -> Result {
        do {
            let search: GitHubCommitSearch = try await get(GitHubAPI.url("/search/commits", query: [
                ("q", GitHubDay.commitQuery(login: connection.login, day: day, calendar: calendar)),
                ("sort", "author-date"), ("order", "desc"), ("per_page", "100"),
            ]))
            var pinMissing = false
            var repo: GitHubRepoRef?
            if let pinnedRepo {
                if let match = search.items.first(where: { $0.repository.fullName == pinnedRepo })?.repository {
                    repo = match
                } else {
                    do { repo = try await get(GitHubAPI.url("/repos/\(pinnedRepo)")) as GitHubRepoRef }
                    catch is NotFound { pinMissing = true }
                }
            }
            if repo == nil { repo = ProjectCardBuilder.busiestRepo(in: search.items) }
            if repo == nil, isToday {
                let recent: [GitHubRepoRef] = try await get(GitHubAPI.url("/user/repos", query: [
                    ("sort", "pushed"), ("per_page", "1"),
                ]))
                repo = recent.first
            }
            guard let repo else { return Result(state: nil, pinMissing: pinMissing) }

            let milestones: [GitHubMilestone] = try await get(GitHubAPI.url("/repos/\(repo.fullName)/milestones", query: [
                ("state", "open"), ("per_page", "10"),
            ]))
            var issues: GitHubIssueSearch?
            if milestones.isEmpty {
                issues = try await get(GitHubAPI.url("/search/issues", query: [
                    ("q", "repo:\(repo.fullName) is:issue is:open"), ("sort", "created"), ("order", "desc"), ("per_page", "2"),
                ]))
            }
            let card = ProjectCardBuilder.card(
                repo: repo, commits: ProjectCardBuilder.commits(in: search.items, repo: repo.fullName),
                isToday: isToday, followUp: ProjectCardBuilder.followUp(milestones: milestones, issues: issues))
            return Result(state: .card(card, asOf: nil), pinMissing: pinMissing)
        } catch is Unauthorized {
            return Result(state: .reconnect, pinMissing: false)
        }
    }

    private func get<Value: Decodable>(_ url: URL) async throws -> Value {
        let (data, status) = try await transport.get(url, token: connection.token)
        switch status {
        case 200..<300: return try GitHubWire.decoder.decode(Value.self, from: data)
        case 401: throw Unauthorized()
        case 404: throw NotFound()
        default: throw GitHubLoadError.unavailable(status)
        }
    }
}
```

A 404 anywhere but the pin lookup escapes as `NotFound`; the app treats any thrown error as unavailable. In `theSearchAsksForTheLocalDay`, the stub sees `url.path` decoded, so the route prefix `/search/commits` matches; if the stub's `path + "?" + query` mis-matches the pin repo route `/repos/o/p` against `/repos/o/p/milestones`, order the routes most-specific first, as the test does.

- [ ] **Step 4:** both filters pass; whole suite; `swift build`.
- [ ] **Step 5:** `git commit -m "feat(integrations): the day's GitHub calls, cached per day, with reconnect and a missing pin"`

---

### Task 5: The `github-token` Edge Function

**Files:** Create `supabase/functions/_shared/github.ts`, `supabase/functions/_shared/github_test.ts`, `supabase/functions/github-token/index.ts`.

**Interfaces — Produces:** `handleGitHubToken(req: Request, deps: { resolveUser: (req: Request) => Promise<string | null>; fetch: typeof fetch; env: (name: string) => string | undefined }): Promise<Response>`.

- [ ] **Step 1: Failing tests** (`github_test.ts`):

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { handleGitHubToken } from "./github.ts";

const env = (values: Record<string, string>) => (name: string) => values[name];
const configured = env({ GITHUB_CLIENT_ID: "id", GITHUB_CLIENT_SECRET: "secret" });
const signedIn = () => Promise.resolve("user-1");

function post(body: unknown, auth = true): Request {
  return new Request("http://x/github-token", {
    method: "POST",
    headers: auth ? { Authorization: "Bearer jwt", "Content-Type": "application/json" } : {},
    body: JSON.stringify(body),
  });
}

Deno.test("no session, no exchange", async () => {
  const res = await handleGitHubToken(post({ code: "c" }, false), {
    resolveUser: () => Promise.resolve(null), fetch: () => { throw new Error("must not call"); }, env: configured,
  });
  assertEquals(res.status, 401);
});

Deno.test("without configuration it says so", async () => {
  const res = await handleGitHubToken(post({ code: "c", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn, fetch: () => { throw new Error("must not call"); }, env: env({}),
  });
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "server_not_configured");
});

Deno.test("a good code becomes a token, and nothing else is returned", async () => {
  let sent = "";
  const res = await handleGitHubToken(post({ code: "c", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn,
    fetch: async (_url, init) => {
      sent = String(init?.body);
      return new Response(JSON.stringify({ access_token: "gho_x", scope: "read:user,repo", token_type: "bearer" }));
    },
    env: configured,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { access_token: "gho_x", scope: "read:user,repo" });
  assertEquals(sent.includes("code_verifier=v"), true);
  assertEquals(sent.includes("client_secret=secret"), true);
});

Deno.test("GitHub's refusal comes back as 400 with its code", async () => {
  const res = await handleGitHubToken(post({ code: "bad", verifier: "v", redirect_uri: "almanac://github-callback" }), {
    resolveUser: signedIn,
    fetch: () => Promise.resolve(new Response(JSON.stringify({ error: "bad_verification_code" }))),
    env: configured,
  });
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "bad_verification_code");
});

Deno.test("DELETE revokes the grant, and an unknown token still counts as done", async () => {
  let called = "";
  const del = new Request("http://x/github-token", {
    method: "DELETE", headers: { Authorization: "Bearer jwt" }, body: JSON.stringify({ access_token: "gho_x" }),
  });
  const res = await handleGitHubToken(del, {
    resolveUser: signedIn,
    fetch: (url, init) => {
      called = `${init?.method} ${url}`;
      return Promise.resolve(new Response(null, { status: 404 }));
    },
    env: configured,
  });
  assertEquals(res.status, 204);
  assertEquals(called, "DELETE https://api.github.com/applications/id/grant");
});
```

- [ ] **Step 2:** `cd supabase/functions/_shared && deno test --allow-env github_test.ts` → fails: module not found.

- [ ] **Step 3: Implement** `github.ts`:

```ts
// The GitHub sign-in's one server step: swapping a code for a token with a
// secret the app cannot hold, and revoking it on Disconnect. Stateless on
// purpose: nothing is stored and no token is logged, so the operator never
// holds anyone's GitHub access.

import { json } from "./supabase.ts";

type Deps = {
  resolveUser: (req: Request) => Promise<string | null>;
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
};

export async function handleGitHubToken(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);
  if (!(await deps.resolveUser(req))) return json({ error: "unauthorized" }, 401);
  const clientID = deps.env("GITHUB_CLIENT_ID");
  const secret = deps.env("GITHUB_CLIENT_SECRET");
  if (!clientID || !secret) return json({ error: "server_not_configured" }, 500);

  let body: { code?: string; verifier?: string; redirect_uri?: string; access_token?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_body" }, 400); }

  if (req.method === "DELETE") {
    if (!body.access_token) return json({ error: "invalid_body" }, 400);
    const response = await deps.fetch(`https://api.github.com/applications/${clientID}/grant`, {
      method: "DELETE",
      headers: {
        Authorization: `Basic ${btoa(`${clientID}:${secret}`)}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ access_token: body.access_token }),
    });
    // 404 or 422: GitHub no longer knows the token, which is the goal.
    return [204, 404, 422].includes(response.status)
      ? new Response(null, { status: 204 })
      : json({ error: "revoke_failed" }, 502);
  }

  if (!body.code || !body.redirect_uri) return json({ error: "invalid_body" }, 400);
  const form = new URLSearchParams({
    client_id: clientID, client_secret: secret, code: body.code, redirect_uri: body.redirect_uri,
  });
  if (body.verifier) form.set("code_verifier", body.verifier);
  const response = await deps.fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const payload = await response.json().catch(() => ({}));
  if (!payload.access_token) return json({ error: payload.error ?? "exchange_failed" }, 400);
  return json({ access_token: payload.access_token, scope: payload.scope ?? "" }, 200);
}
```

`github-token/index.ts`:

```ts
import { resolveUser } from "../_shared/supabase.ts";
import { handleGitHubToken } from "../_shared/github.ts";

Deno.serve((req: Request) => handleGitHubToken(req, { resolveUser, fetch, env: (name) => Deno.env.get(name) }));
```

- [ ] **Step 4:** `deno test --allow-env github_test.ts` → 5 pass; the whole `_shared` suite passes; `deno check ../github-token/index.ts` passes.
- [ ] **Step 5:** `git commit -m "feat(supabase): a stateless github-token function that swaps the code and revokes the grant"`

---

### Task 6: Connecting, in the app

**Files:** Modify `LIfeOS/Features/Settings/Model/AppConfig.swift`, `Config/App-Info.plist`, `Config/Secrets.example.xcconfig`, `LIfeOS/Components/Model/IntegrationContainer.swift`, `LIfeOS/App/RootView.swift`, `LIfeOS/Features/Settings/View/ConnectionsSettingsScreen.swift`; Create `LIfeOS/Features/Settings/ViewModel/GitHubConnectionViewModel.swift`.

**Interfaces — Consumes:** Tasks 3 and 4. **Produces:** `AppConfig.githubClientID: String?`, `AppConfig.githubTokenEndpoint: URL?`, `AppConfig.isGitHubConfigured: Bool`; `@MainActor @Observable final class GitHubConnectionViewModel: NSObject` with `state: State { unconfigured, disconnected, connecting, connected(login: String), failed(String) }`, `connect()`, `handle(_ url: URL) async`, `disconnect()`, `repos: [GitHubRepoRef]`, `loadRepos() async`, `pinnedRepo: String?` (get/set; set clears the day cache), `pinMissing: Bool`, `dayProvider: (any GitHubDayProviding)?`, `deactivate()`; `EnvironmentValues.github: GitHubConnectionViewModel?`; `protocol GitHubDayProviding: Sendable { func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState? }` (declared in `WeatherProviding.swift` beside the others; Task 7 uses it; `force` skips the cache's freshness check for pull to refresh).

- [ ] **Step 1: Config.** `App-Info.plist`, after `FitbitRedirectURI`: `<key>GitHubClientID</key><string>$(GITHUB_CLIENT_ID)</string>`. `Secrets.example.xcconfig`: a commented `GITHUB_CLIENT_ID =` line explaining it is public and the secret lives only in the function's environment. `AppConfig`:

```swift
    static var githubClientID: String? { string("GitHubClientID") }
    static var githubTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/github-token")
    }
    static var isGitHubConfigured: Bool { githubClientID != nil && githubTokenEndpoint != nil }
```

- [ ] **Step 2: The view model.** Write `GitHubConnectionViewModel.swift` on the shape of `FitbitConnectionViewModel` (read it first; mirror `connect()`'s `ASWebAuthenticationSession` with `callbackURLScheme: "almanac"`, the persisted pending auth, `presentationContextProvider`, cancel handling), with these differences:
  - `connect()`: `GitHubOAuth.session(clientID:)`; `tokens.savePending(GitHubPendingAuth(verifier:state:))`.
  - `handle(_:)`: `GitHubOAuth.code(from:expectedState:)` against `tokens.pending()`; `.denied` → `.disconnected`; POST `{code, verifier, redirect_uri: GitHubOAuth.redirectURI}` to `AppConfig.githubTokenEndpoint` with the Supabase bearer; decode `{access_token}`; `GET /user` through `URLSessionGitHubTransport` for `login`; `tokens.save(GitHubConnection(token:login:))`; `tokens.clearPending()`; `state = .connected(login:)`.
  - `disconnect()`: DELETE `{access_token}` to the endpoint (fire and forget, failure logged), then always `tokens.clear()`, `GitHubDayCache(defaults:).clear()`, remove `github.pinnedRepo` and `github.pinnedRepoMissing`, `state = .disconnected`.
  - `pinnedRepo`: `defaults.string(forKey: "github.pinnedRepo")`; its setter writes or removes it, clears `github.pinnedRepoMissing`, and clears the day cache. `pinMissing`: `defaults.bool(forKey: "github.pinnedRepoMissing")`.
  - `loadRepos()`: `GET /user/repos?sort=pushed&per_page=50&affiliation=owner,collaborator,organization_member` into `repos`; a 401 sets `.failed("GitHub needs reconnecting")`.
  - `dayProvider`: nil unless connected; else a `GitHubDayProvider(connection:pinnedRepo:defaults:onPinMissing:)` value (below).
  - `statusDetail`: `Not connected`, `Connecting…`, `Connected as @\(login)`, `Not configured`, or the failure.

`GitHubDayProvider`, in the same file:

```swift
/// The day screen's GitHub source: the cache first, then the loader; a
/// failed refresh falls back to the cached card with its time.
struct GitHubDayProvider: GitHubDayProviding {
    let connection: GitHubConnection
    let pinnedRepo: String?
    let defaults: UserDefaults
    let onPinMissing: @Sendable (Bool) -> Void
    var transport: any GitHubTransport = URLSessionGitHubTransport()

    func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState? {
        let calendar = Calendar.current
        let cache = GitHubDayCache(defaults: defaults)
        let cached = cache.entry(for: day, calendar: calendar)
        if !force, let cached, cache.isFresh(cached, for: day, now: .now, calendar: calendar) {
            return cached.card.map { .card($0, asOf: nil) }
        }
        let loader = GitHubDayLoader(transport: transport, connection: connection, pinnedRepo: pinnedRepo, calendar: calendar)
        do {
            let result = try await loader.load(day: day, isToday: isToday)
            onPinMissing(result.pinMissing)
            if case .reconnect = result.state { return .reconnect }
            if case .card(let card, _)? = result.state { cache.store(card, for: day, calendar: calendar) }
            else { cache.store(nil, for: day, calendar: calendar) }
            return result.state
        } catch {
            return cached?.card.map { .card($0, asOf: cached?.fetchedAt) }
        }
    }
}
```

`UserDefaults` is not `Sendable`; mark the struct `@unchecked Sendable` with a comment that `UserDefaults` is thread-safe, as Apple documents.

- [ ] **Step 3: Own it and inject it.** `IntegrationContainer`: `let githubTokens: any GitHubTokenStoring` (default `KeychainGitHubTokenStore()` in its init, matching how the others default), `private(set) lazy var github = GitHubConnectionViewModel(tokens: githubTokens, sessions: authSessionStore, defaults: userDefaults)`, and `github.deactivate()` in `deactivateAll()`. `RootView`: `.environment(\.github, integrations.github)` beside `\.noteSync` (read how `integrations` is held there first). Declare `@Entry var github: GitHubConnectionViewModel?` in the view model file.

- [ ] **Step 4: The Settings card.** In `ConnectionsSettingsScreen`, add `@Environment(\.github) private var github`, and after the Finances card a `Label("Work", systemImage: "chevron.left.forwardslash.chevron.right")` heading and, when `github` is non-nil:

```swift
connectionCard(icon: "chevron.left.forwardslash.chevron.right", hue: .recovery,
               title: "GitHub", status: github.statusDetail, chip: githubChip(github)) {
    if case .connected = github.state {} else { github.connect() }
}
.disabled(github.state == .unconfigured)
if case .connected = github.state { githubPin(github) }
```

`githubChip(_:)`: `.connected` → `Chip(text: "", standing: true)` (the card's tap does nothing once connected; Disconnect lives in `githubPin`); `.connecting` → `Chip(text: "…")`; `.unconfigured` → `Chip(text: "Setup")`; otherwise `Chip(text: "Connect")`. `githubPin(_:)`: a `Picker("Pin a repo", selection:)` over `nil` (`Automatic`) and `github.repos.map(\.fullName)`, `.pickerStyle(.menu)`, `.task { await github.loadRepos() }`; under it `Text("Pinned repo not found")` in `LifeOSType.caption`, quiet ink, when `github.pinMissing`; then `Button("Disconnect") { github.disconnect() }` as `.editorial(.destructive, size: .compact)`. Lay it out like `cycleToggle` (padding 16, the same glass rounded rectangle).

- [ ] **Step 5: Build, typography, commit.**

```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/github-card build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -5
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $W/typo-base.txt
git commit -m "feat(settings): connect GitHub, pin a repo, and disconnect"
```

---

### Task 7: The section on the day screen

**Files:** Modify `LIfeOS/Features/Day/Model/WeatherProviding.swift`, `DayBriefing.swift`, `DayStubs.swift`, `LIfeOS/Features/Day/ViewModel/DayViewModel.swift`, `LIfeOS/Features/Day/View/DayScreen.swift`, `LIfeOS/Features/Day/View/DaySections.swift`, `LIfeOS/App/RootView.swift:255`, `LIfeOS/Features/Today/View/TodayDesignPreview.swift:71`.

**Interfaces — Consumes:** `GitHubDayProviding`, `ProjectCardState`, `ProjectHeadline`, `DaySection.project`. **Produces:** `DayProviders.github: (any GitHubDayProviding)?` (init parameter defaulting to nil); `DayBriefing.project: ProjectCardState?`; `ProjectRows(state:onOpen:onReconnect:)`; `StubGitHubProvider(state:)`.

- [ ] **Step 1: Providers and briefing.** `DayProviders` gains `var github: (any GitHubDayProviding)? = nil` (a `var` with a default keeps both existing call sites compiling). `DayBriefing` gains `var project: ProjectCardState?`; add `project: nil` to the initialiser call in `DayViewModel.load()`.

- [ ] **Step 2: Load it.** In `DayViewModel`, after `if sections.contains(.weather) { loadWeather() }`: `if sections.contains(.project) { loadProject() }`, keeping the previous `project` when the date is unchanged (as `keptWeather` does). `loadProject()`:

```swift
    private var projectTask: Task<Void, Never>?

    /// The GitHub card follows the rest of the day, like the weather. No
    /// provider means not connected: no section, and no prompt.
    private func loadProject(force: Bool = false) {
        guard let github = providers?.github else { setProject(nil); return }
        let day = date
        let isToday = isOnToday
        projectTask?.cancel()
        projectTask = Task {
            let state = await github.project(for: day, isToday: isToday, force: force)
            guard !Task.isCancelled, self.date == day else { return }
            setProject(state)
        }
    }

    private func setProject(_ state: ProjectCardState?) {
        guard var briefing else { return }
        briefing.project = state
        self.briefing = briefing
    }

    /// Pull to refresh: the card is fetched again even if fresh.
    func refreshProject() async {
        loadProject(force: true)
        await projectTask?.value
    }
```

Add `.refreshable { await model.refreshProject() }` to `DayScreen`'s `ScrollView` only if it has none; if it has one, call `refreshProject()` inside it. Ledger which.

- [ ] **Step 3: Draw it.** In `DayScreen.sectionView`, a `.project` case:

```swift
        case .project:
            if let project = briefing.project {
                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: number(of: section, in: briefing), title: "Project") {
                        if case .card(let card, _) = project {
                            Button(card.repo) { openURL(card.repoURL) }
                                .buttonStyle(.plain).font(LifeOSType.label).foregroundStyle(quiet)
                        }
                    }
                    ProjectRows(state: project, onOpen: { openURL($0) }, onReconnect: { shellProfile?.open() })
                }
            }
```

with `@Environment(\.openURL) private var openURL` and `@Environment(\.shellProfile) private var shellProfile` (check its type in `RootView`: `ShellProfile(photo:open:)`; call `open()`). Note `number(of:in:)` counts every listed section; change it to skip `.project` when `briefing.project == nil` so the numbers stay consecutive:

```swift
    private func number(of section: DaySection, in briefing: DayBriefing) -> Int? {
        briefing.sections.filter { $0 != .weather && ($0 != .project || briefing.project != nil) }
            .firstIndex(of: section).map { $0 + 1 }
    }
```

`ProjectRows` in `DaySections.swift`:

```swift
/// The day's work on GitHub: the count, the first three commit subjects with
/// the rest a tap away, then the milestone or the open issues.
struct ProjectRows: View {
    let state: ProjectCardState
    var onOpen: (URL) -> Void
    var onReconnect: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var showsAll = false

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        switch state {
        case .reconnect:
            Button("GitHub needs reconnecting", action: onReconnect)
                .buttonStyle(.plain).font(LifeOSType.body).foregroundStyle(ink)
        case .card(let card, let asOf):
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(ProjectHeadline.commits(card.commitCount, isTodayWithoutCommits: card.isTodayWithoutCommits))
                    .font(LifeOSType.body).foregroundStyle(ink)
                ForEach(Array((showsAll ? card.commits : Array(card.commits.prefix(3))).enumerated()), id: \.offset) { _, commit in
                    Button(commit.subject) { onOpen(commit.url) }
                        .buttonStyle(.plain).font(LifeOSType.secondary).foregroundStyle(quiet)
                        .lineLimit(1).truncationMode(.tail)
                }
                if !showsAll, card.commits.count > 3 {
                    Button(ProjectHeadline.more(card.commits.count - 3)) { showsAll = true }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                }
                if let followUp = card.followUp {
                    Rectangle().fill(ink.opacity(0.08)).frame(height: 1).padding(.vertical, Space.half)
                    followUpRows(followUp)
                }
                if let asOf {
                    Text(ProjectHeadline.asOf(asOf, calendar: .current)).font(LifeOSType.caption).foregroundStyle(quiet)
                }
            }
        }
    }

    @ViewBuilder private func followUpRows(_ followUp: ProjectFollowUp) -> some View {
        switch followUp {
        case .milestone(let title, let open, let total, let due, let url):
            Button(ProjectHeadline.milestone(title: title, open: open, total: total, due: due, calendar: .current)) { onOpen(url) }
                .buttonStyle(.plain).font(LifeOSType.secondary).foregroundStyle(ink)
        case .issues(let count, let newest):
            Text(ProjectHeadline.issues(count)).font(LifeOSType.secondary).foregroundStyle(ink)
            ForEach(Array(newest.enumerated()), id: \.offset) { _, issue in
                Button(issue.title) { onOpen(issue.url) }
                    .buttonStyle(.plain).font(LifeOSType.secondary).foregroundStyle(quiet).lineLimit(1)
            }
        }
    }
}
```

Use the hairline helper the other day rows use if `DaySections.swift` has one (grep `Rectangle().fill` there first) instead of the inline rectangle.

- [ ] **Step 4: Wire the real provider.** `RootView:255`: `DayProviders(weather: WeatherKitProvider(), location: $0, github: integrations.github.dayProvider)`. `StubGitHubProvider` in `DayStubs.swift`: `struct StubGitHubProvider: GitHubDayProviding { var state: ProjectCardState?; func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState? { state } }` plus `static let sevenCommits: ProjectCard` (repo `LifeOS`, URL `https://github.com/shivvyas2/LifeOS`, milestone `1.1`, 4 open of 9, due Oct 20 of the current year, and these seven subjects, newest first, each with URL `https://github.com/shivvyas2/LifeOS/commit/<n>`):

```
fix(notes): close the gaps the review found
test(notes): UI tests tap through the walkthrough with its real driver
feat(design): a walkthrough script, anchors that report their frames
feat(settings): replay the Notes walkthrough and the welcome tour
feat(persistence): a page the app made goes only if it was left as made
docs(plans): the Notes walkthrough
chore(release): version 1.0.2, build 50, on every target
```

and `static let issues: ProjectCard` (same repo, three commits, `.issues(count: 3, newest:)` with `Crash when a note syncs offline` and `Widget shows yesterday after midnight`).

- [ ] **Step 5: Build, typography, run the suite, commit.**

```bash
xcodebuild ... build   # as Task 6
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $W/typo-base.txt
(cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1)
git commit -m "feat(day): a Project section with the day's commits, then the milestone or issues"
```

---

### Task 8: Preview pages, a UI test, captures

**Files:** Modify `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:135`; Create `LIfeOSUITests/DayProjectUITests.swift`.

- [ ] **Step 1: Pages.** Add `"day-github", "day-github-issues", "day-github-today-none", "day-github-reconnect", "day-github-stale"` to the `HealthActivityDesignPreview` list on line 135 and to the `case "day", ...` arm in `TodayDesignPreview`, passing `github: StubGitHubProvider(state: githubState(for: page))` into `DayProviders`, where `githubState`: `day-github` → `.card(StubGitHubProvider.sevenCommits, asOf: nil)`; `-issues` → `.card(StubGitHubProvider.issues, asOf: nil)`; `-today-none` → a card with no commits and `isTodayWithoutCommits: true`; `-reconnect` → `.reconnect`; `-stale` → `.card(StubGitHubProvider.sevenCommits, asOf: today at 9:40)`; any other day page → nil. These pages show today.

- [ ] **Step 2: The UI test** (`DayProjectUITests.swift`):

```swift
import XCTest

final class DayProjectUITests: XCTestCase {
    func testFourMoreShowsEveryCommit() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=day-github"]
        app.launch()
        let more = app.buttons["4 more"]
        for _ in 0..<4 where !more.exists { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 6), "no 4 more")
        more.tap()
        // The stub's oldest subject, repeated: the UI test target cannot import the app.
        XCTAssertTrue(app.buttons["chore(release): version 1.0.2, build 50, on every target"].waitForExistence(timeout: 4),
                      "the last subject never showed")
        XCTAssertFalse(app.buttons["4 more"].exists)
    }
}
```

The stub has seven commits, so `4 more` appears after three. Add the file to the target:

```bash
ruby -e 'require "xcodeproj"; p = Xcodeproj::Project.open("LIfeOS.xcodeproj"); t = p.targets.find { |x| x.name == "LIfeOSUITests" }; g = p.main_group["LIfeOSUITests"]; t.add_file_references([g.new_file("DayProjectUITests.swift")]); p.save'
xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/github-card 2>&1 | grep -E "Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)"
```

Expected: the new test and the five walkthrough tests pass.

- [ ] **Step 3: Captures.** Install and capture the five pages, light and `--dark`, into `$W` (the loop from the walkthrough plan: `xcrun simctl launch ... --design-preview --page=$p [--dark]`, wait 5 s, `simctl io screenshot`), scrolling is not possible, so if the section is below the fold on a phone, add `.defaultScrollAnchor(.center)` behind a `--anchor=center` flag on those pages as the badminton page does. Read each: the `Project` header with `LifeOS` trailing, the count, three subjects and `4 more`, the hairline, the milestone line; the issues page; `No commits yet today`; the reconnect row; `As of 9:40`. No accent on the card.

- [ ] **Step 4: Commit.** `git commit -m "test(day): GitHub preview pages and a UI test for the commit list"`

---

### Task 9: Whole-branch verification and the PR

- [ ] **Step 1: Gates.**

```bash
(cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1)      # 1522 + new
(cd LifeOSKit && swift build 2>&1 | tail -1)
(cd supabase/functions/_shared && deno test --allow-env 2>&1 | tail -2)
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $W/typo-base.txt
xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWidgets -destination 'id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/github-card build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

- [ ] **Step 2: Fresh whole-branch review** on the most capable model against the spec and this Review Focus; one fix pass for Critical and Important, each with a failing test first.

- [ ] **Step 3: PR.** Push `feat/github-card` and open a PR to main. The body: Summary bullets, Spec and Plan paths, Verification (counts, Deno, captures, UI tests), the owner's three steps from spec section 5 (the card cannot appear until they are done), rulings, deferred minors. Edit the body with `gh api -X PATCH repos/shivvyas2/LifeOS/pulls/N -F body=@file` if `gh pr edit` fails.
