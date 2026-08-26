# Sector Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every card on the Life board tappable, opening a screen that shows what that sector has actually looked like over time.

**Architecture:** All assembly logic is a pure value type in the `Sectors` package, because `LIfeOS.xcodeproj` has no test target and anything in a view model is untestable by construction. The screen reads an already-assembled `SectorHistory` and renders four bands from existing DesignSystem components.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, swift-testing (`@Suite` / `@Test` / `#expect`).

**Spec:** `docs/superpowers/specs/2026-08-25-sector-screens-design.md`

## Global Constraints

- Swift 6. Package platforms are `.iOS("26.0")`, `.macOS("26.0")`. Do not change them.
- Tests use swift-testing, never XCTest. `@Suite struct`, `@Test func`, `#expect`.
- Run tests with `swift test --package-path LifeOSKit` from the repo root. The suite is **404 tests in 53+ suites** and must stay green. State exact counts in reports; the controller verifies them.
- Verify the app with `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`. The package suite does NOT compile the app target. Do not boot a simulator; disk on this machine is limited.
- **No new models, no new logging, no new data collection.** This project reads what the close already writes.
- **No new DesignSystem components, and no modifications to existing ones.** Adapt the screen to the components.
- **No model calls from these screens.** Observations are computed rules.
- Commit messages: conventional commits (`type(scope): imperative summary`) with a body explaining what and why. No em dashes. No AI attribution, no `Co-Authored-By` trailer.
- SourceKit reports bogus "cannot find type" and "no such module" errors in this repo. `swift build`, `swift test` and `xcodebuild` are the authority.

## Real component APIs, verified

Written from declarations, not from names. Do not trust memory of these:

- `SoftCard { content }` — a `@ViewBuilder` container, 16pt padding, 24pt radius. Its doc warns it is screen furniture and not for long repeated list rows.
- `RoundedBarChart(bars: [Bar], hue: ModuleHue? = nil, goal: Double? = nil, baseline: Baseline = .zero, spacing: CGFloat = 10, height: CGFloat = 150)`, where `Bar(id: Date, label: String, value: Double?)` and `Baseline` is `.zero` or `.windowMinimum`.
- `RoundedBarChart.fraction(of:in:baseline:)` is a **pure static** and can be called directly in a test.
- `PastelFillCard(icon: String, hue: ModuleHue, label: String, value: String?, unit: String? = nil, caption: String? = nil, captionColor: Color? = nil)`. Not a container. Renders an em dash when `value == nil`.
- `HeroNumeral(value: String, unit: String? = nil, label: String)`.
- Spacing is `Space.x1` (8), `Space.x2` (16), `Space.x3` (24), `Space.x4` (32), plus `Space.half` (4) and `Space.small` (12). There is no `Space.m`, `.s`, `.l` or `.xs`.
- `SectorPalette.tint(_:) -> ModuleHue` and `SectorPalette.icon(_:) -> String` already exist in `LIfeOS/Features/Life/View/SectorPalette.swift`.

## File Structure

**Created in `LifeOSKit/Sources/Sectors/`:**
- `SectorHistory.swift` — the assembled history and its value types.
- `SectorObservations.swift` — the two computed rules.

**Created in `LIfeOS/Features/Life/`:**
- `View/SectorDetailScreen.swift` — the four bands.
- `ViewModel/SectorDetailViewModel.swift` — fetch, then one call to `SectorHistory.build`.

**Modified:**
- `LIfeOS/Features/Life/View/LifeBoardScreen.swift` — `NavigationStack`, cards become links.
- `LIfeOS/App/RootView.swift` — pass a tab-change closure to the board.

---

### Task 1: `SectorHistory` assembly

**Files:**
- Create: `LifeOSKit/Sources/Sectors/SectorHistory.swift`
- Test: `LifeOSKit/Tests/SectorsTests/SectorHistoryTests.swift`

**Interfaces:**
- Consumes: `LifeSector`, `EvidenceRow`, `CheckInQuestion` from the package.
- Produces: `SectorHistory`, `MonthEntry`, `QuestionTrack`, `HistoryNote`, and `SectorHistory.build(sector:months:answers:calendar:)`.

**Input shape.** `build` takes plain values, never `@Model` objects, so tests need no container:

```swift
public struct ScoreRecord: Sendable, Equatable {
    public let month: Date
    public let userScore: Int?
    public let proposedScore: Int?
    public let evidenceRows: [EvidenceRow]
    public init(month: Date, userScore: Int?, proposedScore: Int?, evidenceRows: [EvidenceRow])
}

public struct AnswerRecord: Sendable, Equatable {
    public let month: Date
    public let questionID: String
    public let answer: String
    public init(month: Date, questionID: String, answer: String)
}
```

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/SectorHistoryTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorHistoryTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func month(_ m: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: 1))!
    }

    private func score(_ m: Int, user: Int?, proposed: Int? = nil,
                       rows: [EvidenceRow] = []) -> ScoreRecord {
        ScoreRecord(month: month(m), userScore: user, proposedScore: proposed, evidenceRows: rows)
    }

    @Test func monthsAreOrderedOldestFirst() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4), score(6, user: 7), score(7, user: 6)],
            answers: [], calendar: calendar
        )
        #expect(history.months.map(\.userScore) == [7, 6, 4])
    }

    /// A month recorded but never decided is not history yet.
    @Test func onlyDecidedMonthsAppear() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: nil)],
            answers: [], calendar: calendar
        )
        #expect(history.months.count == 1)
        #expect(history.months.first?.userScore == 7)
    }

    @Test func aSectorWithNothingProducesEmptyBandsNotNil() {
        let history = SectorHistory.build(
            sector: .romance, months: [], answers: [], calendar: calendar
        )
        #expect(history.months.isEmpty)
        #expect(history.questions.isEmpty)
        #expect(history.notes.isEmpty)
        #expect(history.observations.isEmpty)
    }

    /// The archive is the source. Recomputing history is history that lies.
    @Test func evidenceRowsComeFromTheArchive() {
        let archived = EvidenceRow(label: "days written", value: "5/30", normalised: 0.16)
        let history = SectorHistory.build(
            sector: .soul,
            months: [score(8, user: 6, rows: [archived])],
            answers: [], calendar: calendar
        )
        #expect(history.months.first?.evidenceRows == [archived])
    }

    @Test func answersAreGroupedByQuestionInAskedOrder() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: 6)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.seen", answer: "some"),
                AnswerRecord(month: month(7), questionID: "friends.seen", answer: "barely"),
                AnswerRecord(month: month(6), questionID: "friends.depth", answer: "once"),
            ],
            calendar: calendar
        )
        let ids = history.questions.map(\.questionID)
        #expect(ids == ["friends.seen", "friends.depth"])
    }

    /// A month with no answer must leave a gap, not shift later answers left.
    @Test func aMissingAnswerLeavesAGapRatherThanShifting() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: 6), score(8, user: 4)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.seen", answer: "some"),
                AnswerRecord(month: month(8), questionID: "friends.seen", answer: "barely"),
            ],
            calendar: calendar
        )
        let track = history.questions.first { $0.questionID == "friends.seen" }
        #expect(track?.answers == ["some", nil, "barely"])
    }

    /// Free text is a note, not a comparable answer track.
    @Test func freeTextBecomesANoteNotAQuestionTrack() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4)],
            answers: [AnswerRecord(month: month(8), questionID: "friends.note", answer: "call Ravi")],
            calendar: calendar
        )
        #expect(history.questions.contains { $0.questionID == "friends.note" } == false)
        #expect(history.notes.map(\.text) == ["call Ravi"])
    }

    @Test func notesAreNewestFirst() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(8, user: 4)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.note", answer: "older"),
                AnswerRecord(month: month(8), questionID: "friends.note", answer: "newer"),
            ],
            calendar: calendar
        )
        #expect(history.notes.map(\.text) == ["newer", "older"])
    }

    /// An answer to a question that has since been removed must not crash or
    /// invent a track with no prompt.
    @Test func anAnswerToAnUnknownQuestionIsDropped() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4)],
            answers: [AnswerRecord(month: month(8), questionID: "friends.gone", answer: "x")],
            calendar: calendar
        )
        #expect(history.questions.isEmpty)
        #expect(history.notes.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SectorHistoryTests`
Expected: FAIL, `cannot find 'SectorHistory' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/SectorHistory.swift`:

**Naming, deliberate:** the note type is `HistoryNote`, NOT `SectorNote`.
`Insights` already exports a `SectorNote` (the `@Generable` prose type from the
spine). The app target imports both `Sectors` and `Insights`, so a second
`SectorNote` would be ambiguous at every use site in the app and force
module-qualified names throughout. Do not rename it back.

```swift
import Foundation
import Persistence

/// One stored score, as plain values. Records rather than `@Model` objects so
/// the whole assembly is testable without a container.
public struct ScoreRecord: Sendable, Equatable {
    public let month: Date
    public let userScore: Int?
    public let proposedScore: Int?
    public let evidenceRows: [EvidenceRow]

    public init(month: Date, userScore: Int?, proposedScore: Int?, evidenceRows: [EvidenceRow]) {
        self.month = month
        self.userScore = userScore
        self.proposedScore = proposedScore
        self.evidenceRows = evidenceRows
    }
}

/// One stored check-in answer, as plain values.
public struct AnswerRecord: Sendable, Equatable {
    public let month: Date
    public let questionID: String
    public let answer: String

    public init(month: Date, questionID: String, answer: String) {
        self.month = month
        self.questionID = questionID
        self.answer = answer
    }
}

/// One decided month, as it was decided.
public struct MonthEntry: Sendable, Equatable {
    public let month: Date
    public let userScore: Int
    public let proposedScore: Int?
    /// Frozen at close time. Never recomputed, so a goal changed later cannot
    /// rewrite what an earlier month's reasoning said.
    public let evidenceRows: [EvidenceRow]
}

/// One question's answers laid across the months, aligned by index to
/// `SectorHistory.months`. `nil` is a month that question was not answered in.
public struct QuestionTrack: Sendable, Equatable {
    public let questionID: String
    public let prompt: String
    public let answers: [String?]
}

/// One free-text answer, kept apart from the comparable tracks because it sits
/// on no scale and is read rather than compared.
public struct HistoryNote: Sendable, Equatable {
    public let month: Date
    public let text: String
}

/// Everything one sector has looked like over time, assembled from stored
/// values.
///
/// Pure and built from plain records rather than `@Model` objects, in the same
/// shape as every scorer. The app target has no test target, so anything that
/// decides something lives here where it can be covered.
public struct SectorHistory: Sendable, Equatable {
    public let sector: LifeSector
    public let months: [MonthEntry]
    public let questions: [QuestionTrack]
    public let notes: [HistoryNote]
    public let observations: [String]

    public static func build(
        sector: LifeSector,
        months: [ScoreRecord],
        answers: [AnswerRecord],
        calendar: Calendar = .current
    ) -> SectorHistory {
        // A month recorded but never decided is not history yet: the person
        // has not passed through it, so there is nothing of theirs to show.
        let decided = months
            .compactMap { record -> MonthEntry? in
                guard let userScore = record.userScore else { return nil }
                return MonthEntry(
                    month: Date.startOfMonth(record.month, calendar: calendar),
                    userScore: userScore,
                    proposedScore: record.proposedScore,
                    evidenceRows: record.evidenceRows
                )
            }
            .sorted { $0.month < $1.month }

        let questionSet = CheckInQuestion.questions(for: sector)
        let byMonth = Dictionary(grouping: answers) {
            Date.startOfMonth($0.month, calendar: calendar)
        }

        // Tracks follow the order the questions are asked in, so the screen
        // reads the way the close did.
        let tracks: [QuestionTrack] = questionSet
            .filter { !$0.isFreeText }
            .compactMap { question in
                let answers = decided.map { entry in
                    byMonth[entry.month]?.first { $0.questionID == question.id }?.answer
                }
                guard answers.contains(where: { $0 != nil }) else { return nil }
                return QuestionTrack(
                    questionID: question.id, prompt: question.prompt, answers: answers
                )
            }

        let freeTextIDs = Set(questionSet.filter(\.isFreeText).map(\.id))
        let notes = answers
            .filter { freeTextIDs.contains($0.questionID) && !$0.answer.isEmpty }
            .map { HistoryNote(month: Date.startOfMonth($0.month, calendar: calendar), text: $0.answer) }
            .sorted { $0.month > $1.month }

        return SectorHistory(
            sector: sector,
            months: decided,
            questions: tracks,
            notes: notes,
            observations: SectorObservations.all(months: decided, questions: tracks)
        )
    }
}
```

Task 2 creates `SectorObservations`. Until then this will not compile, so write
Task 1 and Task 2 in that order and run the suite after Task 2. If you prefer a
green step here, stub `observations: []` and replace it in Task 2, saying so in
your report.

- [ ] **Step 4: Commit**

```bash
git add LifeOSKit/Sources/Sectors/SectorHistory.swift \
        LifeOSKit/Tests/SectorsTests/SectorHistoryTests.swift
git commit -m "feat(sectors): assemble one sector's history from stored records

Takes plain records rather than model objects, so the whole assembly is
testable without a container, matching the shape every scorer already uses.

Undecided months are excluded because the person has not passed through them,
free text is separated from the comparable tracks because it sits on no scale,
and a month with no answer leaves a nil in the track rather than shifting later
answers left, which would silently misalign a column against its month."
```

---

### Task 2: The two observation rules

**Files:**
- Create: `LifeOSKit/Sources/Sectors/SectorObservations.swift`
- Test: `LifeOSKit/Tests/SectorsTests/SectorObservationsTests.swift`

**Interfaces:**
- Consumes: `MonthEntry`, `QuestionTrack` from Task 1.
- Produces: `SectorObservations.all(months:questions:) -> [String]`.

Both rules require **three consecutive months**, so a single unusual month never fires one.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/SectorObservationsTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorObservationsTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func entry(_ m: Int, user: Int, proposed: Int?) -> MonthEntry {
        MonthEntry(
            month: calendar.date(from: DateComponents(year: 2026, month: m, day: 1))!,
            userScore: user, proposedScore: proposed, evidenceRows: []
        )
    }

    private func track(_ answers: [String?]) -> QuestionTrack {
        QuestionTrack(questionID: "friends.seen", prompt: "How often did you see friends?", answers: answers)
    }

    @Test func threeIdenticalAnswersInARowIsWorthSaying() {
        let said = SectorObservations.all(
            months: [], questions: [track(["barely", "barely", "barely"])]
        )
        #expect(said.contains { $0.contains("barely") })
    }

    /// Two is a coincidence. Three is a pattern.
    @Test func twoIdenticalAnswersIsNot() {
        let said = SectorObservations.all(
            months: [], questions: [track(["some", "barely", "barely"])]
        )
        #expect(said.isEmpty)
    }

    @Test func aGapInTheRunBreaksIt() {
        let said = SectorObservations.all(
            months: [], questions: [track(["barely", nil, "barely", "barely"])]
        )
        #expect(said.isEmpty)
    }

    /// The signal the spine kept two score columns to preserve.
    @Test func scoringBelowTheProposalThreeMonthsRunningIsWorthSaying() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.contains { $0.lowercased().contains("lower") })
    }

    @Test func aSingleMonthBelowTheProposalIsNot() {
        let said = SectorObservations.all(
            months: [entry(6, user: 7, proposed: 7),
                     entry(7, user: 8, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }

    /// A month the rule could not propose for cannot be part of a gap run.
    @Test func aMonthWithNoProposalBreaksTheGapRun() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: nil),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }

    @Test func scoringAboveTheProposalSaysNothing() {
        let said = SectorObservations.all(
            months: [entry(6, user: 9, proposed: 7),
                     entry(7, user: 9, proposed: 8),
                     entry(8, user: 8, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SectorObservationsTests`
Expected: FAIL, `cannot find 'SectorObservations' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/SectorObservations.swift`:

```swift
import Foundation

/// Short computed remarks about a sector's history.
///
/// Deliberately rules rather than model prose, matching the spine's decision
/// that the rule owns what is asserted. That also keeps this screen free and
/// instant, with no model call at all.
///
/// Every rule needs three consecutive months. Two of anything is a
/// coincidence, and a remark that fires on a coincidence teaches the reader to
/// ignore remarks.
public enum SectorObservations {
    private static let run = 3

    public static func all(months: [MonthEntry], questions: [QuestionTrack]) -> [String] {
        questions.compactMap(repeatedAnswer) + [standingGap(months)].compactMap { $0 }
    }

    /// The same answer, three months running, ending at the most recent month.
    static func repeatedAnswer(_ track: QuestionTrack) -> String? {
        let tail = track.answers.suffix(run)
        guard tail.count == run,
              let first = tail.first ?? nil,
              tail.allSatisfy({ $0 == first })
        else { return nil }
        return "You have said \"\(first)\" three months running."
    }

    /// The person scoring themselves below the rule, three months running.
    ///
    /// This is the signal the spine kept `proposedScore` and `userScore` in
    /// separate columns to preserve: the rule is measuring something the person
    /// does not feel.
    static func standingGap(_ months: [MonthEntry]) -> String? {
        let tail = months.suffix(run)
        guard tail.count == run else { return nil }
        // A month the rule could not propose for is not evidence either way,
        // so it breaks the run rather than being skipped over.
        guard tail.allSatisfy({ entry in
            guard let proposed = entry.proposedScore else { return false }
            return entry.userScore < proposed
        }) else { return nil }
        return "You have scored this lower than the app for three months running."
    }
}
```

- [ ] **Step 4: Run both suites to verify they pass**

Run: `swift test --package-path LifeOSKit --filter Sector`
Expected: `SectorHistoryTests` and `SectorObservationsTests` PASS, and the whole suite still builds.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, count risen from 404 by the tests added in Tasks 1 and 2.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Sectors/SectorObservations.swift \
        LifeOSKit/Tests/SectorsTests/SectorObservationsTests.swift
git commit -m "feat(sectors): say when an answer repeats or a score sits low

Two rules, each needing three consecutive months. Two of anything is a
coincidence, and a remark that fires on a coincidence teaches the reader to
ignore remarks.

The second rule reads the gap between the proposal and the person's own score,
which is the signal the spine kept those two columns separate to preserve. A
month the rule could not propose for breaks the run rather than being skipped,
because it is not evidence either way."
```

---

### Task 3: The sector detail screen

**Files:**
- Create: `LIfeOS/Features/Life/ViewModel/SectorDetailViewModel.swift`
- Create: `LIfeOS/Features/Life/View/SectorDetailScreen.swift`

**Interfaces:**
- Consumes: `SectorHistory`, `SectorStore`, `SectorPalette`.
- Produces: `SectorDetailScreen(sector:onOpenTab:)`, used by Task 4.

**Read before writing.** Open `LIfeOS/Features/Life/View/LifeBoardScreen.swift` and match its conventions: the `attach`/`load` view model pattern, the canvas background, and how it reads `layout.isRegular`.

- [ ] **Step 1: Write the view model**

Create `LIfeOS/Features/Life/ViewModel/SectorDetailViewModel.swift`:

```swift
import Foundation
import SwiftData
import Persistence
import Sectors

@MainActor
@Observable
final class SectorDetailViewModel {
    private(set) var history: SectorHistory?

    private var store: SectorStore?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        store = SectorStore(context: context, calendar: calendar)
    }

    /// Fetch, map to plain records, then one pure call. No decisions here.
    func load(sector: LifeSector, months: Int = 12) {
        guard let store else { return }
        let scores = (try? store.history(sector: sector, months: months)) ?? []
        let records = scores.map {
            ScoreRecord(
                month: $0.month, userScore: $0.userScore,
                proposedScore: $0.proposedScore, evidenceRows: $0.archivedEvidence.rows
            )
        }
        let answers = records.flatMap { record in
            ((try? store.answers(sector: sector, month: record.month)) ?? []).map {
                AnswerRecord(month: $0.month, questionID: $0.questionID, answer: $0.answer)
            }
        }
        history = SectorHistory.build(
            sector: sector, months: records, answers: answers, calendar: calendar
        )
    }
}
```

- [ ] **Step 2: Write the screen**

Create `LIfeOS/Features/Life/View/SectorDetailScreen.swift`. The four bands, each in a `SoftCard`, each omitted when it has nothing:

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

struct SectorDetailScreen: View {
    let sector: LifeSector
    /// Non-nil only for sectors that own a full tab. Nil hides the row.
    let onOpenTab: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var model = SectorDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                if let history = model.history {
                    header(history)
                    if !history.observations.isEmpty { observations(history) }
                    if !history.months.isEmpty { trend(history) }
                    if let latest = history.months.last, !latest.evidenceRows.isEmpty {
                        reasoning(latest)
                    }
                    if !history.questions.isEmpty { answers(history) }
                    if !history.notes.isEmpty { notes(history) }
                    if let onOpenTab { openTabRow(onOpenTab) }
                } else {
                    ProgressView()
                }
            }
            .padding(Space.x2)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle(sector.title)
        .task {
            model.attach(context)
            model.load(sector: sector)
        }
    }
```

Write the six band builders below it. Notes on the ones with real decisions:

**`trend`** uses `RoundedBarChart` with one `Bar` per month:

```swift
    private func trend(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Trend").font(.subheadline).foregroundStyle(.secondary)
                RoundedBarChart(
                    bars: history.months.map {
                        RoundedBarChart.Bar(
                            id: $0.month,
                            label: $0.month.formatted(.dateTime.month(.narrow)),
                            value: Double($0.userScore)
                        )
                    },
                    hue: SectorPalette.tint(sector),
                    baseline: .zero,
                    height: 120
                )
            }
        }
    }
```

`baseline: .zero` is correct here and its consequence is intended: the chart
scales within its own window, so a flat year of 4s renders as steady
half-height bars rather than a flat line at 40%. The component's own doc says a
flat window reads as "steady", which is the honest reading. The absolute value
is carried by the header numeral, not by bar height.

**`answers`** is the band that earns the screen. One row per question, the last
six months across it, oldest to newest, horizontally scrollable:

```swift
    private func answers(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Answers over time").font(.subheadline).foregroundStyle(.secondary)
                ForEach(history.questions, id: \.questionID) { track in
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(track.prompt).font(.footnote)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.small) {
                                ForEach(Array(zip(history.months, track.answers).suffix(6)),
                                        id: \.0.month) { entry, answer in
                                    VStack(spacing: Space.half) {
                                        Text(entry.month.formatted(.dateTime.month(.narrow)))
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(answer ?? "—").font(.callout)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

An unanswered month renders an em dash, matching how the board shows an
unscored sector. Do not substitute a blank or a zero.

**`header`** relies on the component's own em dash rather than formatting one:

```swift
    private func header(_ history: SectorHistory) -> some View {
        PastelFillCard(
            icon: SectorPalette.icon(sector),
            hue: SectorPalette.tint(sector),
            label: sector.title,
            // nil renders PastelFillCard's em dash, so a sector never closed
            // reads the same here as it does on the board.
            value: history.months.last.map { String($0.userScore) },
            unit: history.months.last == nil ? nil : "/10",
            caption: history.months.last.map {
                $0.month.formatted(.dateTime.month(.wide).year())
            }
        )
    }
```

**`reasoning`** renders the archived rows verbatim, label left, value right:

```swift
    private func reasoning(_ entry: MonthEntry) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Why \(entry.month.formatted(.dateTime.month(.wide)))")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(entry.evidenceRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
```

`observations`, `notes` and `openTabRow` are the same `SoftCard` shape with no
further decisions in them: a section label in `.subheadline`/`.secondary`, then
the content. `observations` is a `ForEach` of strings; `notes` is a `ForEach` of
`HistoryNote` showing the month in `.caption2` above the text; `openTabRow` is a
single `Button` calling the closure, labelled "Open \(sector.title)". Follow the
two blocks above rather than inventing a different arrangement.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'generic/platform=iOS Simulator' build
```
Expected: BUILD SUCCEEDED. Do not boot a simulator.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Life
git commit -m "feat(life): show one sector's history in four bands

Trend, the reasoning frozen at close time, every answer laid across the months,
and the notes. Bands with nothing to say are omitted rather than rendered
empty.

The view model fetches and maps; every decision is already made by
SectorHistory in the package, because the app target has no test target and
logic placed here could not be covered."
```

---

### Task 4: Navigation and the tab hand-off

**Files:**
- Modify: `LIfeOS/Features/Life/View/LifeBoardScreen.swift`
- Modify: `LIfeOS/App/RootView.swift`

**Interfaces:**
- Consumes: `SectorDetailScreen` from Task 3.
- Produces: tappable cards, and a tab change for the three sectors that own one.

- [ ] **Step 1: Make the cards tappable**

Wrap the board's grid in a `NavigationStack` and each `SectorCard` in a
`NavigationLink(value:)` with `.navigationDestination(for: LifeSector.self)`.
`LifeSector` is already `Hashable` via its `String` raw value.

Keep everything Task 11 built: the hue mapping, the em dash for an unscored
sector, the three/two column split on `layout.isRegular`, and the close banner
and its sheet. Add to the screen; do not restructure it.

- [ ] **Step 2: Pass the tab-change closure**

`AppTab` is private to `RootView` and stays private. Give `LifeBoardScreen` a
stored closure instead:

```swift
    /// Called with the sector whose full tab should open. The board does not
    /// know how the tab bar works, and `AppTab` stays private to RootView.
    let onOpenTab: (LifeSector) -> Void
```

In `RootView`, pass `LifeBoardScreen(onOpenTab: { sector in ... })` mapping
`.body` to `.health`, `.money` to `.money`, `.mission` to `.plan`, and ignoring
every other sector. Set `tab` in the closure.

`SectorDetailScreen` receives `onOpenTab` as `(() -> Void)?`, non-nil only for
those three, so the row simply does not render for the other six.

- [ ] **Step 3: Build and check both idioms**

Run:
```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'generic/platform=iOS Simulator' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, unchanged from Task 2's count since Tasks 3 and 4 add no package code.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS
git commit -m "feat(life): open a sector from its card, and its tab from there

Every card opens the same shape of screen, so no card behaves differently from
another. Body, Money and Mission additionally offer a row through to their full
tab.

The board takes a closure rather than learning the tab bar: AppTab stays
private to RootView, and the six sectors without a tab simply never render the
row."
```

---

## Verification

After Task 4:

- [ ] `swift test --package-path LifeOSKit` passes, risen from 404 by the Task 1 and 2 tests.
- [ ] `xcodebuild ... build` succeeds with no warnings originating in `Features/Life` or `Sources/Sectors`.
- [ ] A sector never closed opens a screen showing the header with an em dash and no empty bands.
- [ ] Body, Money and Mission show the open-tab row; the other six do not.

## Deferred

- Any new logging or new models. Reading only.
- Editing a past score or a past answer.
- Model-written prose on these screens.
- Money budgeting, Mission PARA, goal horizons. Sub-project three.
- Mood tracking, still unresolved from sub-project one.
