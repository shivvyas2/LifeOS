# Life Sectors Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the nine-sector spine: a deterministic per-sector score proposed from stored evidence, decided by the user in a monthly close, shown on a Life board.

**Architecture:** Value types and pure scoring functions in a new `Sectors` target; storage models and the archived evidence format in `Persistence`; prose from the existing on-device engine in `Insights`; two screens in the app. Scorers are pure structs built from already-fetched values, so every scoring test runs without a database, a container, or async.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, swift-testing (`@Suite` / `@Test` / `#expect`), Apple `FoundationModels`.

**Spec:** `docs/superpowers/specs/2026-08-25-life-sectors-spine-design.md`

## Global Constraints

- Package platforms are `.iOS("26.0")`, `.macOS("26.0")`. Do not lower them.
- Tests use swift-testing, never XCTest. Suites are `@Suite struct`, tests are `@Test func`, assertions are `#expect`.
- SwiftData `@Model` classes store enums as their `rawValue` in a `...Raw` string property with a computed accessor. Follow `PlanEntry.kindRaw` exactly.
- Dates that identify a period are normalised with `Calendar.startOfDay`. `SectorScore.month` is the first day of the month being scored.
- A sector with no evidence proposes `nil`, never `0`.
- Weights are constants in code. Do not add settings UI for them.
- No em dashes in commit messages.
- Commit messages are conventional commits: `type(scope): imperative summary`, with a body explaining what and why. No AI attribution, no `Co-Authored-By` trailer.
- Run `swift test --package-path LifeOSKit` from the repo root. The suite is currently 250 tests in 36 suites and must stay green.

## File Structure

**Created in `LifeOSKit/Sources/Persistence/`** (pure value types and storage; no new dependencies):
- `LifeSector.swift` - the nine cases, titles, and board order.
- `Evidence.swift` - `EvidenceRow`, `Evidence`, and the one shared scoring rule. `Codable` so it can be archived onto a score.
- `SectorScore.swift` - the `@Model` for a scored sector-month, plus `CheckInAnswer`.
- `SectorStore.swift` - reads and writes both models.

**Created in `LifeOSKit/Sources/Sectors/`** (new target, depends on `Persistence`):
- `SectorScorer.swift` - the protocol.
- `BodyScorer.swift`, `MoneyScorer.swift`, `MissionScorer.swift`, `GrowthScorer.swift`, `JournalScorer.swift`, `CheckInScorer.swift` - one file per rule.
- `CheckInQuestion.swift` - the questions for the four relational sectors.

**Modified:**
- `LifeOSKit/Package.swift` - add the `Sectors` target and its test target.
- `LifeOSKit/Sources/Persistence/LifeOSContainer.swift` - register two models.
- `LifeOSKit/Sources/Insights/CoachTask.swift` - generalise the prompt context.
- `LifeOSKit/Sources/Insights/Engines/Engine.swift`, `OnDeviceEngine.swift` - follow that change.
- `LIfeOS/App/RootView.swift:58` - a fifth tab.

**Created in `LIfeOS/Features/Life/`:**
- `ViewModel/LifeBoardViewModel.swift`, `View/LifeBoardScreen.swift`
- `ViewModel/MonthlyCloseViewModel.swift`, `View/MonthlyCloseScreen.swift`
- `View/SectorPalette.swift` - sector to tint and icon, the only place the two meet.

`Evidence` lives in `Persistence` rather than `Sectors` because `SectorScore` archives it. Putting it in `Sectors` would make `Persistence` depend on `Sectors` while `Sectors` depends on `Persistence`, which does not build.

---

### Task 1: The `Sectors` target and `LifeSector`

**Files:**
- Create: `LifeOSKit/Sources/Persistence/LifeSector.swift`
- Create: `LifeOSKit/Sources/Sectors/SectorScorer.swift`
- Modify: `LifeOSKit/Package.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/LifeSectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `LifeSector` (enum, `String` raw, `Codable`, `Sendable`, `CaseIterable`) with `title: String` and `static boardOrder: [LifeSector]`. A `Sectors` library target that later tasks add files to.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/LifeSectorTests.swift`:

```swift
import Testing
@testable import Persistence

@Suite struct LifeSectorTests {

    @Test func thereAreNineSectors() {
        #expect(LifeSector.allCases.count == 9)
    }

    /// The board reads in the order Shiv already scores in, which is not
    /// declaration order and not alphabetical.
    @Test func boardOrderCoversEverySectorExactlyOnce() {
        #expect(LifeSector.boardOrder.count == LifeSector.allCases.count)
        #expect(Set(LifeSector.boardOrder) == Set(LifeSector.allCases))
    }

    @Test func boardOrderStartsWithFamily() {
        #expect(LifeSector.boardOrder.first == .family)
    }

    /// Raw values are persisted, so renaming a case silently orphans stored rows.
    @Test func rawValuesAreStable() {
        #expect(LifeSector.body.rawValue == "body")
        #expect(LifeSector.romance.rawValue == "romance")
        #expect(LifeSector(rawValue: "mission") == .mission)
    }

    @Test func everySectorHasATitle() {
        #expect(LifeSector.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter LifeSectorTests`
Expected: FAIL, `cannot find 'LifeSector' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Persistence/LifeSector.swift`:

```swift
import Foundation

/// The nine sectors of life this app scores.
///
/// Raw values are written to the store, so a case may be added but never
/// renamed: a rename orphans every score already recorded against it.
public enum LifeSector: String, Codable, Sendable, CaseIterable {
    case family, romance, soul, friends, growth, money, mission, body, mind

    public var title: String {
        switch self {
        case .family:  "Family"
        case .romance: "Romance"
        case .soul:    "Soul"
        case .friends: "Friends"
        case .growth:  "Growth"
        case .money:   "Money"
        case .mission: "Mission"
        case .body:    "Body"
        case .mind:    "Mind"
        }
    }

    /// Reading order on the board. Kept separate from `allCases` so that
    /// adding a sector later cannot silently reshuffle the grid.
    public static let boardOrder: [LifeSector] = [
        .family, .romance, .soul,
        .friends, .growth, .money,
        .mission, .body, .mind,
    ]
}
```

Create `LifeOSKit/Sources/Sectors/SectorScorer.swift`:

```swift
import Persistence

/// One sector's rule.
///
/// A conforming type is built from values that have already been fetched, not
/// from a store. That is what keeps every scoring test free of a container,
/// and it is why `evidence()` neither throws nor awaits.
public protocol SectorScorer: Sendable {
    var sector: LifeSector { get }
    func evidence() -> Evidence
}
```

Modify `LifeOSKit/Package.swift`. Add to `products`:

```swift
        .library(name: "Sectors", targets: ["Sectors"]),
```

Add to `targets`:

```swift
        .target(name: "Sectors", dependencies: ["Persistence"]),
        .testTarget(name: "SectorsTests", dependencies: ["Sectors"]),
```

`SectorScorer.swift` will not compile until Task 2 adds `Evidence`. Write both files now and expect the `Sectors` target to fail; `LifeSectorTests` still runs because it targets `Persistence`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter LifeSectorTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/Persistence/LifeSector.swift \
        LifeOSKit/Sources/Sectors/SectorScorer.swift \
        LifeOSKit/Tests/PersistenceTests/LifeSectorTests.swift
git commit -m "feat(sectors): name the nine sectors and open the Sectors target

Raw values are persisted, so the enum is documented as append-only. Board
order is declared separately from allCases so adding a sector later cannot
reshuffle the grid by accident."
```

---

### Task 2: `Evidence` and the shared scoring rule

**Files:**
- Create: `LifeOSKit/Sources/Persistence/Evidence.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/EvidenceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `EvidenceRow(label: String, value: String, normalised: Double, weight: Double = 1)` and `Evidence(_ rows: [EvidenceRow])` with `rows: [EvidenceRow]` and `proposedScore: Int?`. Both `Codable`, `Sendable`, `Equatable`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/EvidenceTests.swift`:

```swift
import Testing
import Foundation
@testable import Persistence

@Suite struct EvidenceTests {

    /// The whole reason the rule is shared: one arithmetic path to verify.
    @Test func aWeightedMeanScalesToTen() {
        let evidence = Evidence([
            EvidenceRow(label: "a", value: "1", normalised: 1.0, weight: 1),
            EvidenceRow(label: "b", value: "0", normalised: 0.0, weight: 1),
        ])
        #expect(evidence.proposedScore == 5)
    }

    @Test func weightsActuallyWeigh() {
        let evidence = Evidence([
            EvidenceRow(label: "heavy", value: "1", normalised: 1.0, weight: 3),
            EvidenceRow(label: "light", value: "0", normalised: 0.0, weight: 1),
        ])
        // (1*3 + 0*1) / 4 = 0.75 -> 7.5 -> 8
        #expect(evidence.proposedScore == 8)
    }

    /// A sector with nothing to say must not claim the person scored zero.
    @Test func noRowsProposesNothingRatherThanZero() {
        #expect(Evidence([]).proposedScore == nil)
    }

    @Test func zeroTotalWeightProposesNothing() {
        let evidence = Evidence([
            EvidenceRow(label: "ignored", value: "0", normalised: 1.0, weight: 0)
        ])
        #expect(evidence.proposedScore == nil)
    }

    @Test func normalisedValuesAreClampedIntoRange() {
        let high = EvidenceRow(label: "over", value: "x", normalised: 4.2, weight: 1)
        let low = EvidenceRow(label: "under", value: "x", normalised: -1.0, weight: 1)
        #expect(high.normalised == 1.0)
        #expect(low.normalised == 0.0)
    }

    @Test func aNegativeWeightIsTreatedAsZero() {
        let row = EvidenceRow(label: "bad", value: "x", normalised: 1.0, weight: -5)
        #expect(row.weight == 0)
    }

    @Test func scoresAreBoundedByTheScale() {
        let perfect = Evidence([EvidenceRow(label: "a", value: "1", normalised: 1.0)])
        let empty = Evidence([EvidenceRow(label: "a", value: "0", normalised: 0.0)])
        #expect(perfect.proposedScore == 10)
        #expect(empty.proposedScore == 0)
    }

    /// Archived onto a score, so it has to survive a round trip unchanged.
    @Test func evidenceRoundTripsThroughCoding() throws {
        let original = Evidence([
            EvidenceRow(label: "journal entries", value: "5", normalised: 0.42, weight: 2)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Evidence.self, from: data)
        #expect(decoded == original)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter EvidenceTests`
Expected: FAIL, `cannot find 'Evidence' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Persistence/Evidence.swift`:

```swift
import Foundation

/// One line of reasoning behind a proposed score.
///
/// `value` is the figure as it should be shown, already formatted. The close
/// screen renders these rows directly, which is what stops the explanation
/// drifting away from the arithmetic that produced the number.
public struct EvidenceRow: Codable, Sendable, Equatable {
    public let label: String
    public let value: String
    /// Always within 0...1. Clamped on the way in rather than trusted.
    public let normalised: Double
    /// Never negative. A zero-weight row is shown but does not count.
    public let weight: Double

    public init(label: String, value: String, normalised: Double, weight: Double = 1) {
        self.label = label
        self.value = value
        self.normalised = min(max(normalised, 0), 1)
        self.weight = max(weight, 0)
    }
}

/// The rows behind one sector-month, and the number they add up to.
///
/// Every sector uses this one rule, so a sector with two rows behaves exactly
/// like a sector with six and there is a single arithmetic path to test.
public struct Evidence: Codable, Sendable, Equatable {
    public let rows: [EvidenceRow]

    public init(_ rows: [EvidenceRow] = []) {
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// The weighted mean of the rows, on a 0...10 scale.
    ///
    /// `nil` when there is nothing to go on. Deliberately not zero: a sector
    /// with no evidence has not been judged badly, it has not been judged.
    public var proposedScore: Int? {
        guard !rows.isEmpty else { return nil }
        let totalWeight = rows.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weighted = rows.reduce(0) { $0 + $1.normalised * $1.weight }
        return Int(((weighted / totalWeight) * 10).rounded())
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter EvidenceTests`
Expected: 8 tests PASS.

- [ ] **Step 5: Verify the whole suite still builds**

Run: `swift test --package-path LifeOSKit`
Expected: PASS. The `Sectors` target now compiles because `Evidence` exists.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/Evidence.swift \
        LifeOSKit/Tests/PersistenceTests/EvidenceTests.swift
git commit -m "feat(sectors): add evidence rows and the one shared scoring rule

Every sector normalises its rows to 0...1, weights them, and takes the
weighted mean on a ten point scale. One arithmetic path means one thing to
test and one thing to explain.

An empty set proposes nil rather than zero, because a sector with no evidence
has not been judged badly, it has not been judged."
```

---

### Task 3: The stored models

**Files:**
- Create: `LifeOSKit/Sources/Persistence/SectorScore.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift:5-16`
- Test: `LifeOSKit/Tests/PersistenceTests/SectorScoreTests.swift`

**Interfaces:**
- Consumes: `LifeSector`, `Evidence` (Tasks 1, 2).
- Produces: `@Model SectorScore` with `sector: LifeSector`, `month: Date`, `proposedScore: Int?`, `userScore: Int?`, `closedAt: Date?`, `archivedEvidence: Evidence`. `@Model CheckInAnswer` with `sector: LifeSector`, `month: Date`, `questionID: String`, `answer: String`. `Date.startOfMonth(_:)` helper.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/SectorScoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SectorScoreTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    private var august: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    }

    @Test func aScoreRoundTripsThroughTheStore() throws {
        let context = try makeContext()
        let evidence = Evidence([
            EvidenceRow(label: "journal entries", value: "5", normalised: 0.42)
        ])
        let score = SectorScore(sector: .soul, month: august, proposedScore: 4)
        score.archivedEvidence = evidence
        context.insert(score)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SectorScore>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.sector == .soul)
        #expect(fetched.first?.archivedEvidence == evidence)
    }

    /// The gap between the two is the most interesting signal in the system.
    /// Collapsing them into one column would destroy it.
    @Test func theUserScoreIsSeparateFromTheProposal() throws {
        let context = try makeContext()
        let score = SectorScore(sector: .body, month: august, proposedScore: 8)
        score.userScore = 5
        context.insert(score)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SectorScore>()).first
        #expect(fetched?.proposedScore == 8)
        #expect(fetched?.userScore == 5)
    }

    @Test func anUnscoredSectorHasNoUserScore() throws {
        let score = SectorScore(sector: .romance, month: august, proposedScore: nil)
        #expect(score.userScore == nil)
        #expect(score.closedAt == nil)
    }

    /// A score recorded on 3 September for August must store 1 August.
    @Test func aMonthIsNormalisedToItsFirstDay() {
        let calendar = Calendar.current
        let thirdOfSeptember = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 3, hour: 14)
        )!
        let normalised = Date.startOfMonth(thirdOfSeptember)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: normalised)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 1)
        #expect(parts.hour == 0)
    }

    @Test func aCheckInAnswerRoundTrips() throws {
        let context = try makeContext()
        context.insert(CheckInAnswer(
            sector: .friends, month: august,
            questionID: "friends.seen", answer: "3"
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CheckInAnswer>()).first
        #expect(fetched?.sector == .friends)
        #expect(fetched?.questionID == "friends.seen")
        #expect(fetched?.answer == "3")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SectorScoreTests`
Expected: FAIL, `cannot find 'SectorScore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Persistence/SectorScore.swift`:

```swift
import Foundation
import SwiftData

public extension Date {
    /// The first instant of the month a date falls in.
    ///
    /// Every sector row is keyed by this, so closing August on 3 September
    /// files the score under 1 August rather than under the day it was typed.
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }
}

/// One sector, scored for one month.
///
/// `proposedScore` and `userScore` are both kept, permanently. The distance
/// between what the rule computed and what the person actually felt is the
/// most interesting number here, and averaging them would erase it.
@Model
public final class SectorScore {
    public var sectorRaw: String
    /// Always the first day of the month being scored.
    public var month: Date
    /// What the rule said, or nil when there was no evidence at all.
    public var proposedScore: Int?
    /// What the person said. Nil until they pass through this sector.
    public var userScore: Int?
    public var closedAt: Date?

    /// The rows behind the proposal, frozen at close time.
    ///
    /// Archived rather than recomputed: change a goal in March and February's
    /// reasoning must still read the way it did in February.
    public var evidenceData: Data?

    public var sector: LifeSector {
        get { LifeSector(rawValue: sectorRaw) ?? .body }
        set { sectorRaw = newValue.rawValue }
    }

    public var archivedEvidence: Evidence {
        get {
            guard let evidenceData,
                  let decoded = try? JSONDecoder().decode(Evidence.self, from: evidenceData)
            else { return Evidence() }
            return decoded
        }
        set { evidenceData = try? JSONEncoder().encode(newValue) }
    }

    /// A sector the person has actually passed through and answered.
    public var isScored: Bool { userScore != nil }

    public init(sector: LifeSector, month: Date, proposedScore: Int?) {
        self.sectorRaw = sector.rawValue
        self.month = Date.startOfMonth(month)
        self.proposedScore = proposedScore
        self.userScore = nil
        self.closedAt = nil
        self.evidenceData = nil
    }
}

/// One answer to one check-in question, for one sector-month.
///
/// Stored as text whatever the question's shape, because the value of these
/// is comparison against last month rather than arithmetic.
@Model
public final class CheckInAnswer {
    public var sectorRaw: String
    public var month: Date
    public var questionID: String
    public var answer: String
    public var createdAt: Date

    public var sector: LifeSector {
        get { LifeSector(rawValue: sectorRaw) ?? .body }
        set { sectorRaw = newValue.rawValue }
    }

    public init(sector: LifeSector, month: Date, questionID: String, answer: String) {
        self.sectorRaw = sector.rawValue
        self.month = Date.startOfMonth(month)
        self.questionID = questionID
        self.answer = answer
        self.createdAt = .now
    }
}
```

Modify `LifeOSKit/Sources/Persistence/LifeOSContainer.swift`, adding two lines to the schema array after `MoneyAccount.self,`:

```swift
        SectorScore.self,
        CheckInAnswer.self,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter SectorScoreTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/SectorScore.swift \
        LifeOSKit/Sources/Persistence/LifeOSContainer.swift \
        LifeOSKit/Tests/PersistenceTests/SectorScoreTests.swift
git commit -m "feat(sectors): store a scored sector month and its check-in answers

Proposal and user score are separate columns and stay that way: the gap
between what the rule computed and what the person felt is the signal worth
keeping, and one averaged column would erase it.

Evidence is archived as JSON on the row rather than recomputed, so changing a
goal in March cannot rewrite February's reasoning."
```

---

### Task 4: `SectorStore`

**Files:**
- Create: `LifeOSKit/Sources/Persistence/SectorStore.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/SectorStoreTests.swift`

**Interfaces:**
- Consumes: `SectorScore`, `CheckInAnswer`, `Evidence`, `LifeSector`.
- Produces: `@MainActor struct SectorStore(context:calendar:)` with `scores(forMonth:) throws -> [SectorScore]`, `score(_ sector:month:) throws -> SectorScore?`, `record(sector:month:proposed:evidence:) throws -> SectorScore`, `commit(userScore:to:) throws`, `answers(sector:month:) throws -> [CheckInAnswer]`, `saveAnswer(sector:month:questionID:answer:) throws`, `history(sector:months:) throws -> [SectorScore]`, `oldestUnclosedMonth(before:) throws -> Date?`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/SectorStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SectorStoreTests {

    private func makeStore() throws -> SectorStore {
        SectorStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    @Test func recordingAProposalIsIdempotentPerSectorMonth() throws {
        let store = try makeStore()
        let august = month(2026, 8)

        _ = try store.record(sector: .body, month: august, proposed: 7, evidence: Evidence())
        _ = try store.record(sector: .body, month: august, proposed: 9, evidence: Evidence())

        let scores = try store.scores(forMonth: august)
        #expect(scores.count == 1)
        #expect(scores.first?.proposedScore == 9)
    }

    @Test func committingAUserScoreClosesTheSector() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        let score = try store.record(sector: .soul, month: august, proposed: 6, evidence: Evidence())

        try store.commit(userScore: 4, to: score)

        let stored = try store.score(.soul, month: august)
        #expect(stored?.userScore == 4)
        #expect(stored?.proposedScore == 6)
        #expect(stored?.closedAt != nil)
    }

    /// Once a sector is decided, its reasoning is history. Recomputing must
    /// not rewrite either the decision or the evidence behind it.
    @Test func rerecordingLeavesAClosedScoreEntirelyAlone() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        let original = Evidence([
            EvidenceRow(label: "kept of what came in", value: "40%", normalised: 0.8)
        ])
        let score = try store.record(
            sector: .money, month: august, proposed: 5, evidence: original
        )
        try store.commit(userScore: 8, to: score)

        _ = try store.record(
            sector: .money, month: august, proposed: 2, evidence: Evidence()
        )

        let stored = try store.score(.money, month: august)
        #expect(stored?.userScore == 8)
        #expect(stored?.proposedScore == 5)
        #expect(stored?.archivedEvidence == original)
    }

    @Test func historyIsNewestLastAndLimited() throws {
        let store = try makeStore()
        for m in 1...8 {
            let score = try store.record(
                sector: .body, month: month(2026, m), proposed: m, evidence: Evidence()
            )
            try store.commit(userScore: m, to: score)
        }

        let history = try store.history(sector: .body, months: 6)
        #expect(history.count == 6)
        #expect(history.first?.userScore == 3)
        #expect(history.last?.userScore == 8)
    }

    /// A month never closed stays offered rather than being replaced by a
    /// newer one, so a gap in the history is always visible and fillable.
    @Test func theOldestUnclosedMonthIsOfferedFirst() throws {
        let store = try makeStore()
        let july = month(2026, 7)
        let august = month(2026, 8)
        _ = try store.record(sector: .body, month: july, proposed: 5, evidence: Evidence())
        _ = try store.record(sector: .body, month: august, proposed: 5, evidence: Evidence())

        #expect(try store.oldestUnclosedMonth(before: month(2026, 9)) == july)
    }

    @Test func aFullyClosedMonthIsNotOffered() throws {
        let store = try makeStore()
        let july = month(2026, 7)
        for sector in LifeSector.allCases {
            let score = try store.record(
                sector: sector, month: july, proposed: 5, evidence: Evidence()
            )
            try store.commit(userScore: 5, to: score)
        }

        #expect(try store.oldestUnclosedMonth(before: month(2026, 8)) == nil)
    }

    @Test func answersAreKeptPerSectorMonth() throws {
        let store = try makeStore()
        let august = month(2026, 8)

        try store.saveAnswer(sector: .friends, month: august, questionID: "seen", answer: "3")
        try store.saveAnswer(sector: .friends, month: august, questionID: "seen", answer: "5")

        let answers = try store.answers(sector: .friends, month: august)
        #expect(answers.count == 1)
        #expect(answers.first?.answer == "5")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SectorStoreTests`
Expected: FAIL, `cannot find 'SectorStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Persistence/SectorStore.swift`:

```swift
import Foundation
import SwiftData

/// Reads and writes sector scores and their check-in answers.
///
/// Follows `PlanStore` and `MoneyStore`: a `@MainActor` value type over a
/// context, with the calendar injected so tests are not at the mercy of the
/// machine's locale.
@MainActor
public struct SectorStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func scores(forMonth month: Date) throws -> [SectorScore] {
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<SectorScore>(predicate: #Predicate { $0.month == key })
        )
    }

    public func score(_ sector: LifeSector, month: Date) throws -> SectorScore? {
        let raw = sector.rawValue
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.month == key }
            )
        ).first
    }

    /// Writes a proposal, creating the row if it is new.
    ///
    /// A sector already decided is returned untouched. Recomputing is routine,
    /// and once a person has scored a month both their number and the reasoning
    /// they saw are history: rewriting either would make the archive lie.
    @discardableResult
    public func record(
        sector: LifeSector, month: Date, proposed: Int?, evidence: Evidence
    ) throws -> SectorScore {
        if let existing = try score(sector, month: month) {
            guard !existing.isScored else { return existing }
            existing.proposedScore = proposed
            existing.archivedEvidence = evidence
            try context.save()
            return existing
        }
        let created = SectorScore(sector: sector, month: month, proposedScore: proposed)
        created.archivedEvidence = evidence
        context.insert(created)
        try context.save()
        return created
    }

    public func commit(userScore: Int, to score: SectorScore) throws {
        score.userScore = userScore
        score.closedAt = .now
        try context.save()
    }

    /// The last `months` scored entries for a sector, oldest first, for the
    /// board sparkline.
    public func history(sector: LifeSector, months: Int) throws -> [SectorScore] {
        let raw = sector.rawValue
        let all = try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.userScore != nil },
                sortBy: [SortDescriptor(\.month)]
            )
        )
        return Array(all.suffix(months))
    }

    /// The earliest month that still has an unscored sector.
    ///
    /// Deliberately the oldest rather than the most recent: skipping August
    /// must not bury it under September, or the gap is lost silently.
    public func oldestUnclosedMonth(before limit: Date) throws -> Date? {
        let key = Date.startOfMonth(limit, calendar: calendar)
        let open = try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.month < key && $0.userScore == nil },
                sortBy: [SortDescriptor(\.month)]
            )
        )
        return open.first?.month
    }

    public func answers(sector: LifeSector, month: Date) throws -> [CheckInAnswer] {
        let raw = sector.rawValue
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<CheckInAnswer>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.month == key },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    /// One answer per question per sector-month. Answering again replaces.
    public func saveAnswer(
        sector: LifeSector, month: Date, questionID: String, answer: String
    ) throws {
        let existing = try answers(sector: sector, month: month)
            .first { $0.questionID == questionID }
        if let existing {
            existing.answer = answer
        } else {
            context.insert(CheckInAnswer(
                sector: sector, month: month, questionID: questionID, answer: answer
            ))
        }
        try context.save()
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter SectorStoreTests`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/SectorStore.swift \
        LifeOSKit/Tests/PersistenceTests/SectorStoreTests.swift
git commit -m "feat(sectors): read and write sector scores and check-in answers

Recording a proposal leaves an existing decision alone, because recomputing
is routine and must never undo a score the person already gave.

The oldest unclosed month is what gets offered, not the most recent, so
skipping a month leaves a visible fillable gap instead of losing it."
```

---

### Task 5: The Body scorer

**Files:**
- Create: `LifeOSKit/Sources/Sectors/BodyScorer.swift`
- Test: `LifeOSKit/Tests/SectorsTests/BodyScorerTests.swift`

**Interfaces:**
- Consumes: `SectorScorer`, `Evidence`, `EvidenceRow`, and `DayReading` / `GoalTargets` / `DayStatus` / `evaluate(_:against:)` from `Persistence/GoalEvaluation.swift`.
- Produces: `BodyScorer(readings: [DayReading], targets: GoalTargets)`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/BodyScorerTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BodyScorerTests {

    private func day(steps: Int? = 9000, sleep: Int? = 450, exercise: Int? = 40) -> DayReading {
        DayReading(steps: steps, sleepMinutes: sleep, exerciseMinutes: exercise, waterML: 2600)
    }

    @Test func aMonthOnTargetScoresAtTheTop() {
        let scorer = BodyScorer(
            readings: Array(repeating: day(), count: 30), targets: .default
        )
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .body)
    }

    @Test func aMonthOfMissesScoresLow() {
        let poor = day(steps: 200, sleep: 200, exercise: 0)
        let scorer = BodyScorer(readings: Array(repeating: poor, count: 30), targets: .default)
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! <= 2)
    }

    /// Leaving the watch on the charger is not a failure, so blank days are
    /// excluded rather than counted as misses.
    @Test func daysWithNoDataDoNotDragTheScoreDown() {
        let blank = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        let mixed = Array(repeating: day(), count: 10) + Array(repeating: blank, count: 20)
        let scorer = BodyScorer(readings: mixed, targets: .default)
        #expect(scorer.evidence().proposedScore == 10)
    }

    @Test func aMonthWithNoDataAtAllProposesNothing() {
        let blank = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        let scorer = BodyScorer(readings: Array(repeating: blank, count: 30), targets: .default)
        #expect(scorer.evidence().proposedScore == nil)
        #expect(scorer.evidence().rows.isEmpty)
    }

    @Test func noReadingsAtAllProposesNothing() {
        #expect(BodyScorer(readings: [], targets: .default).evidence().proposedScore == nil)
    }

    @Test func theEvidenceNamesWhatItCounted() {
        let scorer = BodyScorer(readings: Array(repeating: day(), count: 30), targets: .default)
        let labels = scorer.evidence().rows.map(\.label)
        #expect(labels.contains("days on target"))
        #expect(labels.contains("sleep vs goal"))
        #expect(labels.contains("exercise vs goal"))
    }

    @Test func theDaysOnTargetRowShowsTheCount() {
        let mixed = Array(repeating: day(), count: 15)
            + Array(repeating: day(steps: 100, sleep: 100, exercise: 0), count: 15)
        let scorer = BodyScorer(readings: mixed, targets: .default)
        let row = scorer.evidence().rows.first { $0.label == "days on target" }
        #expect(row?.value == "15/30")
        #expect(row?.normalised == 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter BodyScorerTests`
Expected: FAIL, `cannot find 'BodyScorer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/BodyScorer.swift`:

```swift
import Foundation
import Persistence

/// Body, from the metrics the app already collects.
///
/// Days on target carry twice the weight of the two averages, because a month
/// is made of days met or missed; the averages only say by how much.
public struct BodyScorer: SectorScorer {
    public let sector = LifeSector.body

    private let readings: [DayReading]
    private let targets: GoalTargets

    public init(readings: [DayReading], targets: GoalTargets) {
        self.readings = readings
        self.targets = targets
    }

    public func evidence() -> Evidence {
        let judged = readings.map { evaluate($0, against: targets) }
        let counted = judged.filter { $0 != .noData }
        guard !counted.isEmpty else { return Evidence() }

        let onTarget = counted.filter { $0 == .onTarget }.count
        var rows = [
            EvidenceRow(
                label: "days on target",
                value: "\(onTarget)/\(counted.count)",
                normalised: Double(onTarget) / Double(counted.count),
                weight: 2
            )
        ]

        if let row = average(
            label: "sleep vs goal",
            values: readings.compactMap { $0.sleepMinutes.map(Double.init) },
            goal: Double(targets.sleepMinutes),
            format: { "\(Int($0 / 60))h \(Int($0.truncatingRemainder(dividingBy: 60)))m" }
        ) {
            rows.append(row)
        }

        if let row = average(
            label: "exercise vs goal",
            values: readings.compactMap { $0.exerciseMinutes.map(Double.init) },
            goal: Double(targets.exerciseMinutes),
            format: { "\(Int($0))m" }
        ) {
            rows.append(row)
        }

        return Evidence(rows)
    }

    /// One row comparing a month's average against its goal.
    ///
    /// Returns nil rather than a zero row when nothing was logged, so an
    /// untracked metric stays absent from the reasoning instead of arguing
    /// against the person.
    private func average(
        label: String, values: [Double], goal: Double, format: (Double) -> String
    ) -> EvidenceRow? {
        guard !values.isEmpty, goal > 0 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return EvidenceRow(
            label: label, value: format(mean), normalised: mean / goal, weight: 1
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter BodyScorerTests`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/BodyScorer.swift \
        LifeOSKit/Tests/SectorsTests/BodyScorerTests.swift
git commit -m "feat(sectors): score Body from the metrics already collected

Reuses the existing evaluate(_:against:) judgement so the sector agrees with
what the Today screen already shows. Days with no data are excluded rather
than counted as misses, and a metric that was never logged produces no row
at all instead of a zero that argues against the person."
```

---

### Task 6: The Money scorer

**Files:**
- Create: `LifeOSKit/Sources/Sectors/MoneyScorer.swift`
- Test: `LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift`

**Interfaces:**
- Consumes: `SectorScorer`, `Evidence`.
- Produces: `MoneyScorer(amounts: [Double], previousAmounts: [Double])`. Amounts follow `MoneyEntry`'s convention: positive is money in, negative is money out.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct MoneyScorerTests {

    @Test func savingMoreThanHalfOfIncomeScoresWell() {
        let scorer = MoneyScorer(amounts: [5000, -2000], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! >= 8)
    }

    @Test func spendingMoreThanEarningScoresBadly() {
        let scorer = MoneyScorer(amounts: [3000, -4500], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! <= 2)
    }

    /// The sign convention is inherited from MoneyEntry and a flip here would
    /// turn every good month into a bad one.
    @Test func positiveIsIncomeAndNegativeIsSpend() {
        let evidence = MoneyScorer(amounts: [4000, -1000], previousAmounts: []).evidence()
        #expect(evidence.rows.first { $0.label == "earned" }?.value == "4000")
        #expect(evidence.rows.first { $0.label == "spent" }?.value == "1000")
    }

    @Test func spendingLessThanLastMonthIsCredited() {
        let scorer = MoneyScorer(amounts: [4000, -1000], previousAmounts: [4000, -2000])
        let row = scorer.evidence().rows.first { $0.label == "spend vs last month" }
        #expect(row != nil)
        #expect(row!.normalised > 0.5)
    }

    @Test func withNoPreviousMonthThereIsNoComparisonRow() {
        let scorer = MoneyScorer(amounts: [4000, -1000], previousAmounts: [])
        #expect(!scorer.evidence().rows.contains { $0.label == "spend vs last month" })
    }

    @Test func aMonthWithNoTransactionsProposesNothing() {
        #expect(MoneyScorer(amounts: [], previousAmounts: []).evidence().proposedScore == nil)
    }

    /// No income and no way to compute a rate must not read as a perfect month.
    @Test func spendWithNoIncomeDoesNotScoreTop() {
        let scorer = MoneyScorer(amounts: [-500], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! < 10)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter MoneyScorerTests`
Expected: FAIL, `cannot find 'MoneyScorer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/MoneyScorer.swift`:

```swift
import Foundation
import Persistence

/// Money, from this month's transactions.
///
/// **Sign convention, inherited from `MoneyEntry`: positive is money in,
/// negative is money out.** A flip here turns every good month into a bad one,
/// which is why the split is done once, at the top, and named.
public struct MoneyScorer: SectorScorer {
    public let sector = LifeSector.money

    private let amounts: [Double]
    private let previousAmounts: [Double]

    public init(amounts: [Double], previousAmounts: [Double]) {
        self.amounts = amounts
        self.previousAmounts = previousAmounts
    }

    public func evidence() -> Evidence {
        guard !amounts.isEmpty else { return Evidence() }

        let earned = amounts.filter { $0 > 0 }.reduce(0, +)
        let spent = -amounts.filter { $0 < 0 }.reduce(0, +)

        var rows = [
            EvidenceRow(label: "earned", value: Self.money(earned), normalised: 0, weight: 0),
            EvidenceRow(label: "spent", value: Self.money(spent), normalised: 0, weight: 0),
        ]

        // A month that earned nothing cannot have a saving rate. It scores
        // poorly rather than perfectly, and says why.
        let savingRate = earned > 0 ? (earned - spent) / earned : 0
        rows.append(EvidenceRow(
            label: "kept of what came in",
            value: earned > 0 ? "\(Int((savingRate * 100).rounded()))%" : "no income",
            normalised: savingRate / 0.5,
            weight: 3
        ))

        let previousSpend = -previousAmounts.filter { $0 < 0 }.reduce(0, +)
        if previousSpend > 0 {
            let change = (previousSpend - spent) / previousSpend
            rows.append(EvidenceRow(
                label: "spend vs last month",
                value: "\(change >= 0 ? "-" : "+")\(Int((abs(change) * 100).rounded()))%",
                normalised: 0.5 + change,
                weight: 1
            ))
        }

        return Evidence(rows)
    }

    private static func money(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
```

The `earned` and `spent` rows carry `weight: 0` on purpose: they are shown as
context but the judgement belongs to the rate, which already accounts for both.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter MoneyScorerTests`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/MoneyScorer.swift \
        LifeOSKit/Tests/SectorsTests/MoneyScorerTests.swift
git commit -m "feat(sectors): score Money from the month's transactions

Judgement rests on what was kept of what came in, with earned and spent shown
as zero weight context so the same figures are not counted twice.

A month with no income scores poorly and says no income rather than dividing
by zero into a perfect score."
```

---

### Task 7: The Mission and Growth scorers

**Files:**
- Create: `LifeOSKit/Sources/Sectors/MissionScorer.swift`
- Create: `LifeOSKit/Sources/Sectors/GrowthScorer.swift`
- Test: `LifeOSKit/Tests/SectorsTests/PlanScorerTests.swift`

**Interfaces:**
- Consumes: `SectorScorer`, `Evidence`, `PlanStatus` from `Persistence`.
- Produces: `MissionScorer(statuses: [PlanStatus], habitTickRate: Double?)` and `GrowthScorer(goalStatuses: [PlanStatus], targetsMet: Int, targetsTotal: Int)`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/PlanScorerTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct MissionScorerTests {

    @Test func everythingDoneScoresAtTheTop() {
        let scorer = MissionScorer(
            statuses: Array(repeating: .done, count: 5), habitTickRate: 1.0
        )
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .mission)
    }

    @Test func nothingMovedScoresAtTheBottom() {
        let scorer = MissionScorer(
            statuses: Array(repeating: .todo, count: 5), habitTickRate: 0
        )
        #expect(scorer.evidence().proposedScore == 0)
    }

    /// In progress is movement, not completion, and is worth part credit.
    @Test func inProgressCountsForSomethingButNotEverything() {
        let all = MissionScorer(statuses: Array(repeating: .inProgress, count: 4), habitTickRate: nil)
        let score = all.evidence().proposedScore
        #expect(score != nil)
        #expect(score! > 0 && score! < 10)
    }

    /// Blocked is not the person's failure and must not be scored as a miss.
    @Test func blockedItemsAreExcludedFromJudgement() {
        let mixed = MissionScorer(statuses: [.done, .done, .blocked, .blocked], habitTickRate: nil)
        #expect(mixed.evidence().proposedScore == 10)
    }

    @Test func noEntriesProposesNothing() {
        #expect(MissionScorer(statuses: [], habitTickRate: nil).evidence().proposedScore == nil)
    }

    @Test func onlyBlockedEntriesProposeNothing() {
        let scorer = MissionScorer(statuses: [.blocked, .blocked], habitTickRate: nil)
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func aMissingHabitRateAddsNoRow() {
        let scorer = MissionScorer(statuses: [.done], habitTickRate: nil)
        #expect(!scorer.evidence().rows.contains { $0.label == "habits kept" })
    }
}

@Suite struct GrowthScorerTests {

    @Test func metTargetsAndFinishedGoalsScoreAtTheTop() {
        let scorer = GrowthScorer(goalStatuses: [.done, .done], targetsMet: 4, targetsTotal: 4)
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .growth)
    }

    @Test func halfTheTargetsScoresInTheMiddle() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 2, targetsTotal: 4)
        #expect(scorer.evidence().proposedScore == 5)
    }

    @Test func noGoalsAndNoTargetsProposesNothing() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 0, targetsTotal: 0)
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func theEvidenceNamesTheTargetCount() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 3, targetsTotal: 4)
        let row = scorer.evidence().rows.first { $0.label == "targets met" }
        #expect(row?.value == "3/4")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter Scorer`
Expected: FAIL, `cannot find 'MissionScorer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/MissionScorer.swift`:

```swift
import Foundation
import Persistence

/// How far a plan entry got this month, on the shared 0...1 scale.
///
/// Blocked returns nil rather than zero: waiting on someone else is not a
/// failure of the person being scored, so it is excluded rather than punished.
func progressFraction(_ status: PlanStatus) -> Double? {
    switch status {
    case .done:       1.0
    case .inProgress: 0.5
    case .scheduled:  0.25
    case .todo:       0.0
    case .blocked:    nil
    }
}

/// Mission, from what actually moved on the plan.
public struct MissionScorer: SectorScorer {
    public let sector = LifeSector.mission

    private let statuses: [PlanStatus]
    private let habitTickRate: Double?

    public init(statuses: [PlanStatus], habitTickRate: Double?) {
        self.statuses = statuses
        self.habitTickRate = habitTickRate
    }

    public func evidence() -> Evidence {
        let judged = statuses.compactMap(progressFraction)
        guard !judged.isEmpty else { return Evidence() }

        let done = statuses.filter { $0 == .done }.count
        var rows = [
            EvidenceRow(
                label: "goals moved",
                value: "\(done)/\(judged.count)",
                normalised: judged.reduce(0, +) / Double(judged.count),
                weight: 2
            )
        ]

        if let habitTickRate {
            rows.append(EvidenceRow(
                label: "habits kept",
                value: "\(Int((habitTickRate * 100).rounded()))%",
                normalised: habitTickRate,
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
```

Create `LifeOSKit/Sources/Sectors/GrowthScorer.swift`:

```swift
import Foundation
import Persistence

/// Growth, from the targets set in `UserGoals` and the goals raised against them.
public struct GrowthScorer: SectorScorer {
    public let sector = LifeSector.growth

    private let goalStatuses: [PlanStatus]
    private let targetsMet: Int
    private let targetsTotal: Int

    public init(goalStatuses: [PlanStatus], targetsMet: Int, targetsTotal: Int) {
        self.goalStatuses = goalStatuses
        self.targetsMet = targetsMet
        self.targetsTotal = targetsTotal
    }

    public func evidence() -> Evidence {
        var rows: [EvidenceRow] = []

        if targetsTotal > 0 {
            rows.append(EvidenceRow(
                label: "targets met",
                value: "\(targetsMet)/\(targetsTotal)",
                normalised: Double(targetsMet) / Double(targetsTotal),
                weight: 2
            ))
        }

        let judged = goalStatuses.compactMap(progressFraction)
        if !judged.isEmpty {
            let done = goalStatuses.filter { $0 == .done }.count
            rows.append(EvidenceRow(
                label: "goals completed",
                value: "\(done)/\(judged.count)",
                normalised: judged.reduce(0, +) / Double(judged.count),
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter Scorer`
Expected: all Mission, Growth and Body scorer tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/MissionScorer.swift \
        LifeOSKit/Sources/Sectors/GrowthScorer.swift \
        LifeOSKit/Tests/SectorsTests/PlanScorerTests.swift
git commit -m "feat(sectors): score Mission and Growth from the plan

Both share one progress fraction, where blocked returns nil rather than zero.
Waiting on someone else is not a failure of the person being scored, so a
blocked item is excluded from the judgement instead of counted as a miss."
```

---

### Task 8: The journal-fed scorers, Mind and Soul

**Files:**
- Create: `LifeOSKit/Sources/Sectors/JournalScorer.swift`
- Test: `LifeOSKit/Tests/SectorsTests/JournalScorerTests.swift`

**Interfaces:**
- Consumes: `SectorScorer`, `Evidence`.
- Produces: `JournalScorer(sector: LifeSector, entryDates: [Date], daysInMonth: Int, previousEntryCount: Int?, calendar: Calendar = .current)`.

Mind and Soul share a rule because they share their only data source. When
sub-project two gives them distinct inputs, this splits.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/JournalScorerTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct JournalScorerTests {

    private func dates(_ count: Int) -> [Date] {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        return (0..<count).map {
            Calendar.current.date(byAdding: .day, value: $0, to: start)!
        }
    }

    @Test func writingMostDaysScoresWell() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(24), daysInMonth: 30, previousEntryCount: nil
        )
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! >= 7)
    }

    @Test func aSilentMonthProposesNothing() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: [], daysInMonth: 30, previousEntryCount: nil
        )
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func theSectorIsWhicheverWasAskedFor() {
        let mind = JournalScorer(
            sector: .mind, entryDates: dates(5), daysInMonth: 30, previousEntryCount: nil
        )
        #expect(mind.sector == .mind)
    }

    /// Twelve entries on one day is not twelve days of reflection.
    @Test func severalEntriesOnOneDayCountAsOneDay() {
        let sameDay = Array(repeating: dates(1)[0], count: 12)
        let scorer = JournalScorer(
            sector: .soul, entryDates: sameDay, daysInMonth: 30, previousEntryCount: nil
        )
        let row = scorer.evidence().rows.first { $0.label == "days written" }
        #expect(row?.value == "1/30")
    }

    @Test func writingMoreThanLastMonthIsCredited() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(10), daysInMonth: 30, previousEntryCount: 5
        )
        let row = scorer.evidence().rows.first { $0.label == "vs last month" }
        #expect(row != nil)
        #expect(row!.normalised > 0.5)
    }

    @Test func withNoPreviousMonthThereIsNoComparisonRow() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(10), daysInMonth: 30, previousEntryCount: nil
        )
        #expect(!scorer.evidence().rows.contains { $0.label == "vs last month" })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter JournalScorerTests`
Expected: FAIL, `cannot find 'JournalScorer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/JournalScorer.swift`:

```swift
import Foundation
import Persistence

/// Mind and Soul, from journal entries.
///
/// One rule for two sectors because they share their only data source today.
/// This is the thinnest evidence in the system and it is meant to be: when
/// sub-project two gives the two sectors distinct inputs, this type splits.
public struct JournalScorer: SectorScorer {
    public let sector: LifeSector

    private let entryDates: [Date]
    private let daysInMonth: Int
    private let previousEntryCount: Int?
    private let calendar: Calendar

    public init(
        sector: LifeSector,
        entryDates: [Date],
        daysInMonth: Int,
        previousEntryCount: Int?,
        calendar: Calendar = .current
    ) {
        self.sector = sector
        self.entryDates = entryDates
        self.daysInMonth = daysInMonth
        self.previousEntryCount = previousEntryCount
        self.calendar = calendar
    }

    public func evidence() -> Evidence {
        guard !entryDates.isEmpty, daysInMonth > 0 else { return Evidence() }

        // Distinct days, not entries: twelve entries on one afternoon is one
        // day of reflection, and counting them separately would flatter it.
        let daysWritten = Set(entryDates.map { calendar.startOfDay(for: $0) }).count

        var rows = [
            EvidenceRow(
                label: "days written",
                value: "\(daysWritten)/\(daysInMonth)",
                normalised: Double(daysWritten) / Double(daysInMonth),
                weight: 2
            )
        ]

        if let previousEntryCount, previousEntryCount > 0 {
            let change = Double(entryDates.count - previousEntryCount) / Double(previousEntryCount)
            rows.append(EvidenceRow(
                label: "vs last month",
                value: "\(change >= 0 ? "+" : "")\(Int((change * 100).rounded()))%",
                normalised: 0.5 + change / 2,
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter JournalScorerTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/JournalScorer.swift \
        LifeOSKit/Tests/SectorsTests/JournalScorerTests.swift
git commit -m "feat(sectors): score Mind and Soul from journal entries

One rule for both, because today they share their only data source. Counts
distinct days rather than entries: twelve entries in one afternoon is one day
of reflection and should not read as twelve.

This is the thinnest evidence in the system by design, and splits when the
two sectors get distinct inputs."
```

---

### Task 9: Check-in questions and the relational scorer

**Files:**
- Create: `LifeOSKit/Sources/Sectors/CheckInQuestion.swift`
- Create: `LifeOSKit/Sources/Sectors/CheckInScorer.swift`
- Test: `LifeOSKit/Tests/SectorsTests/CheckInTests.swift`

**Interfaces:**
- Consumes: `SectorScorer`, `Evidence`, `LifeSector`.
- Produces: `CheckInQuestion(id: String, prompt: String, options: [CheckInOption], weight: Double)`, `CheckInOption(label: String, normalised: Double)`, `CheckInQuestion.questions(for: LifeSector) -> [CheckInQuestion]`, and `CheckInScorer(sector: LifeSector, answers: [String: String])` keyed by question id.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/CheckInTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct CheckInQuestionTests {

    /// These four sectors have no other source, so a missing question set
    /// would leave them permanently unscorable.
    @Test func everyRelationalSectorHasQuestions() {
        for sector in [LifeSector.family, .romance, .friends, .soul] {
            #expect(!CheckInQuestion.questions(for: sector).isEmpty)
        }
    }

    @Test func questionIDsAreUniqueWithinASector() {
        for sector in LifeSector.allCases {
            let ids = CheckInQuestion.questions(for: sector).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    /// IDs are persisted on CheckInAnswer, so a rename orphans stored answers.
    @Test func questionIDsAreNamespacedBySector() {
        for sector in LifeSector.allCases {
            let questions = CheckInQuestion.questions(for: sector)
            #expect(questions.allSatisfy { $0.id.hasPrefix("\(sector.rawValue).") })
        }
    }

    /// A free text question carries no options by definition, so only the
    /// scored questions are checked for a usable set.
    @Test func everyScoredQuestionHasAUsableOptionSet() {
        for sector in LifeSector.allCases {
            for question in CheckInQuestion.questions(for: sector) where !question.isFreeText {
                #expect(question.options.count >= 2)
                #expect(question.options.allSatisfy { (0...1).contains($0.normalised) })
            }
        }
    }

    @Test func freeTextQuestionsCarryNoOptions() {
        let notes = CheckInQuestion.questions(for: .romance).filter(\.isFreeText)
        #expect(notes.count == 1)
        #expect(notes.first?.options.isEmpty == true)
    }
}

@Suite struct CheckInScorerTests {

    private var romanceQuestions: [CheckInQuestion] {
        CheckInQuestion.questions(for: .romance)
    }

    /// Free text questions are skipped: they have no options to pick a best
    /// from, and they carry no weight in the score anyway.
    @Test func answeringEveryScoredQuestionAtTheTopScoresTen() {
        var answers: [String: String] = [:]
        for question in romanceQuestions where !question.isFreeText {
            guard let best = question.options.max(by: { $0.normalised < $1.normalised })
            else { continue }
            answers[question.id] = best.label
        }
        let scorer = CheckInScorer(sector: .romance, answers: answers)
        #expect(scorer.evidence().proposedScore == 10)
    }

    @Test func noAnswersProposesNothing() {
        #expect(CheckInScorer(sector: .romance, answers: [:]).evidence().proposedScore == nil)
    }

    /// A half-finished check-in scores on what was answered, so leaving the
    /// close midway does not silently score the person down.
    @Test func unansweredQuestionsAreSkippedNotCountedAsZero() {
        let first = romanceQuestions[0]
        let best = first.options.max { $0.normalised < $1.normalised }!
        let scorer = CheckInScorer(sector: .romance, answers: [first.id: best.label])
        #expect(scorer.evidence().rows.count == 1)
        #expect(scorer.evidence().proposedScore == 10)
    }

    /// Free text has no scale, so it is recorded as context and left unweighted.
    @Test func freeTextIsShownButNotScored() {
        let scorer = CheckInScorer(sector: .romance, answers: ["romance.note": "a good month"])
        let row = scorer.evidence().rows.first { $0.label.contains("worth remembering") }
        #expect(row?.weight == 0)
    }

    @Test func anUnrecognisedAnswerIsIgnored() {
        let first = romanceQuestions[0]
        let scorer = CheckInScorer(sector: .romance, answers: [first.id: "nonsense"])
        #expect(scorer.evidence().proposedScore == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter CheckIn`
Expected: FAIL, `cannot find 'CheckInQuestion' in scope`.

- [ ] **Step 3: Write the implementation**

Create `LifeOSKit/Sources/Sectors/CheckInQuestion.swift`:

```swift
import Foundation
import Persistence

/// One choice, and what it is worth on the shared scale.
public struct CheckInOption: Sendable, Equatable {
    public let label: String
    public let normalised: Double

    public init(_ label: String, _ normalised: Double) {
        self.label = label
        self.normalised = normalised
    }
}

/// A question asked at close time for a sector with no tracked data.
///
/// `id` is written to `CheckInAnswer` and compared against next month, so ids
/// are append-only in exactly the way `LifeSector`'s raw values are. Renaming
/// one orphans every answer already stored against it.
public struct CheckInQuestion: Sendable, Equatable {
    public let id: String
    public let prompt: String
    /// Empty means free text: recorded as context, never scored.
    public let options: [CheckInOption]
    public let weight: Double

    public init(id: String, prompt: String, options: [CheckInOption], weight: Double = 1) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.weight = weight
    }

    public var isFreeText: Bool { options.isEmpty }

    private static let scale: [CheckInOption] = [
        CheckInOption("barely", 0.0),
        CheckInOption("some", 0.35),
        CheckInOption("a fair amount", 0.7),
        CheckInOption("a lot", 1.0),
    ]

    public static func questions(for sector: LifeSector) -> [CheckInQuestion] {
        switch sector {
        case .family:
            [
                CheckInQuestion(id: "family.contact", prompt: "How much did you speak with family?", options: scale, weight: 2),
                CheckInQuestion(id: "family.showedUp", prompt: "Were you there when it mattered?", options: [
                    CheckInOption("no", 0.0), CheckInOption("once or twice", 0.5), CheckInOption("yes", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "family.note", prompt: "One thing worth remembering", options: []),
            ]
        case .romance:
            [
                CheckInQuestion(id: "romance.state", prompt: "Where are things?", options: [
                    CheckInOption("alone, and not looking", 0.5),
                    CheckInOption("alone, and looking", 0.3),
                    CheckInOption("seeing someone", 0.7),
                    CheckInOption("together", 1.0),
                ], weight: 1),
                CheckInQuestion(id: "romance.time", prompt: "Time together felt", options: [
                    CheckInOption("too little", 0.2), CheckInOption("about right", 0.8), CheckInOption("plenty", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "romance.note", prompt: "One thing worth remembering", options: []),
            ]
        case .friends:
            [
                CheckInQuestion(id: "friends.seen", prompt: "How often did you see friends?", options: scale, weight: 2),
                CheckInQuestion(id: "friends.depth", prompt: "Did any of it go beyond small talk?", options: [
                    CheckInOption("no", 0.0), CheckInOption("once", 0.5), CheckInOption("more than once", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "friends.note", prompt: "Who is worth calling next month?", options: []),
            ]
        case .soul:
            [
                CheckInQuestion(id: "soul.settled", prompt: "How settled did you feel?", options: scale, weight: 2),
                CheckInQuestion(id: "soul.note", prompt: "One thing worth remembering", options: []),
            ]
        case .mind:
            [
                CheckInQuestion(id: "mind.clarity", prompt: "How clear was your head?", options: scale, weight: 2),
            ]
        case .growth, .money, .mission, .body:
            []
        }
    }
}
```

Create `LifeOSKit/Sources/Sectors/CheckInScorer.swift`:

```swift
import Foundation
import Persistence

/// A sector scored from what the person answered at close time.
///
/// This is what makes month one scorable for the four sectors with no tracked
/// data at all, and over time the answers themselves become the trend line.
public struct CheckInScorer: SectorScorer {
    public let sector: LifeSector

    /// Answers keyed by question id, holding the chosen option's label or the
    /// free text.
    private let answers: [String: String]

    public init(sector: LifeSector, answers: [String: String]) {
        self.sector = sector
        self.answers = answers
    }

    public func evidence() -> Evidence {
        let rows: [EvidenceRow] = CheckInQuestion.questions(for: sector).compactMap { question in
            guard let answer = answers[question.id], !answer.isEmpty else { return nil }

            if question.isFreeText {
                // No scale to place it on, so it is context and nothing more.
                return EvidenceRow(
                    label: question.prompt.lowercased(), value: answer,
                    normalised: 0, weight: 0
                )
            }

            // An answer that matches no option is stale data from a question
            // that has since changed. Dropping it beats guessing at it.
            guard let option = question.options.first(where: { $0.label == answer }) else {
                return nil
            }

            return EvidenceRow(
                label: question.prompt.lowercased(), value: option.label,
                normalised: option.normalised, weight: question.weight
            )
        }

        return Evidence(rows)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter CheckIn`
Expected: 9 tests PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, and the total is now well above the starting 250.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Sectors/CheckInQuestion.swift \
        LifeOSKit/Sources/Sectors/CheckInScorer.swift \
        LifeOSKit/Tests/SectorsTests/CheckInTests.swift
git commit -m "feat(sectors): ask the relational sectors for their evidence

Family, Romance, Friends and Soul have no tracked data, so they are asked two
or three questions at close time and scored on the answers. That is what makes
month one scorable rather than half empty.

Unanswered questions are skipped rather than counted as zero, so abandoning a
close midway cannot score someone down. Free text is recorded as unweighted
context because it sits on no scale."
```

---

### Task 10: Generalise the coach context and add the sector note

**Files:**
- Modify: `LifeOSKit/Sources/Insights/CoachTask.swift:23-33` and the two task types below it
- Modify: `LifeOSKit/Sources/Insights/Engines/Engine.swift`
- Modify: `LifeOSKit/Sources/Insights/Engines/OnDeviceEngine.swift`
- Create: `LifeOSKit/Sources/Insights/Tasks/SectorNote.swift`
- Test: `LifeOSKit/Tests/InsightsTests/SectorNoteTests.swift`

**Interfaces:**
- Consumes: `Evidence` (Task 2).
- Produces: `CoachTask` with `associatedtype Context: Sendable` and `func prompt(_ context: Context) -> String`; `Engine.run<T>(_ task: T, _ context: T.Context)`; `@Generable SectorNote` with `summary: String`; `SectorNoteTask(sectorTitle:)` with `Context == SectorEvidenceContext`; `SectorEvidenceContext(sectorTitle:evidence:previousUserScore:)` with `promptLines: String`.

`CoachTask.prompt` currently takes `MetricsDigest` specifically, so a task about
sector evidence cannot be expressed at all. One associated type fixes that for
every future task and changes no behaviour.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/SectorNoteTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Insights

@Suite struct SectorNoteTests {

    private var evidence: Evidence {
        Evidence([
            EvidenceRow(label: "days written", value: "5/30", normalised: 0.16, weight: 2),
            EvidenceRow(label: "vs last month", value: "-58%", normalised: 0.2, weight: 1),
        ])
    }

    /// The model is shown only what the rule used, so it cannot cite a figure
    /// that played no part in the score.
    @Test func thePromptCarriesEveryEvidenceRow() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", evidence: evidence, previousUserScore: 7
        )
        let prompt = SectorNoteTask(sectorTitle: "Soul").prompt(context)

        #expect(prompt.contains("days written"))
        #expect(prompt.contains("5/30"))
        #expect(prompt.contains("vs last month"))
        #expect(prompt.contains("Soul"))
    }

    @Test func lastMonthsScoreIsOfferedForComparison() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", evidence: evidence, previousUserScore: 7
        )
        #expect(context.promptLines.contains("7"))
    }

    @Test func aFirstMonthMentionsNoPreviousScore() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", evidence: evidence, previousUserScore: nil
        )
        #expect(!context.promptLines.lowercased().contains("last month you scored"))
    }

    /// The number is the rule's job. The model describes and nothing more.
    @Test func theInstructionsForbidJudgingOrScoring() {
        let instructions = SectorNoteTask(sectorTitle: "Soul").instructions.lowercased()
        #expect(instructions.contains("never"))
        #expect(instructions.contains("score"))
    }

    @Test func theTaskRunsOnDevice() {
        #expect(SectorNoteTask(sectorTitle: "Soul").floor == .onDevice)
    }

    @Test func emptyEvidenceStillProducesAUsablePrompt() {
        let context = SectorEvidenceContext(
            sectorTitle: "Romance", evidence: Evidence(), previousUserScore: nil
        )
        #expect(!SectorNoteTask(sectorTitle: "Romance").prompt(context).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SectorNoteTests`
Expected: FAIL, `cannot find 'SectorNoteTask' in scope`.

- [ ] **Step 3: Generalise the protocol**

In `LifeOSKit/Sources/Insights/CoachTask.swift`, change the protocol:

```swift
public protocol CoachTask: Sendable {
    associatedtype Output: Generable
    /// What this task needs to see. Was fixed at `MetricsDigest`, which made
    /// any task about something other than health metrics inexpressible.
    associatedtype Context: Sendable

    var floor: Tier { get }

    /// Stable across requests. Anything that varies belongs in `prompt`.
    var instructions: String { get }

    func prompt(_ context: Context) -> String
}
```

In the same file, add one line to each existing task so they keep their
current context. Inside `BriefTask`, above `floor`:

```swift
    public typealias Context = MetricsDigest
```

And the same line inside `AnswerTask`.

In `LifeOSKit/Sources/Insights/Engines/Engine.swift`:

```swift
public protocol Engine: Sendable {
    func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output
}
```

In `LifeOSKit/Sources/Insights/Engines/OnDeviceEngine.swift`, rename the
parameter and nothing else:

```swift
    public func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output {
        let session = LanguageModelSession(instructions: task.instructions)
        let response = try await session.respond(
            to: task.prompt(context),
            generating: T.Output.self
        )
        return response.content
    }
}
```

- [ ] **Step 4: Verify nothing regressed**

Run: `swift test --package-path LifeOSKit`
Expected: PASS. If `CoachRouter` or `EscalationPolicy` fails to compile, they
call `run` and need the same parameter rename, no logic change.

- [ ] **Step 5: Add the sector note**

Create `LifeOSKit/Sources/Insights/Tasks/SectorNote.swift`:

```swift
import Foundation
import FoundationModels
import Persistence

/// One sentence about what changed in a sector this month.
@Generable
public struct SectorNote: Equatable, Sendable {

    @Guide(description: "One or two sentences describing what changed this month. Plain and specific. No advice, no encouragement, no score.")
    public var summary: String
}

/// Everything the model is allowed to see about a sector-month.
///
/// Deliberately only the rows the rule actually used, so the sentence cannot
/// cite a figure that played no part in the number.
public struct SectorEvidenceContext: Sendable {
    public let sectorTitle: String
    public let evidence: Evidence
    public let previousUserScore: Int?

    public init(sectorTitle: String, evidence: Evidence, previousUserScore: Int?) {
        self.sectorTitle = sectorTitle
        self.evidence = evidence
        self.previousUserScore = previousUserScore
    }

    public var promptLines: String {
        var lines = evidence.rows.map { "\($0.label): \($0.value)" }
        if let previousUserScore {
            lines.append("last month you scored this \(previousUserScore) out of 10")
        }
        return lines.isEmpty ? "no data recorded" : lines.joined(separator: "\n")
    }
}

public struct SectorNoteTask: CoachTask {
    public typealias Output = SectorNote
    public typealias Context = SectorEvidenceContext

    public let sectorTitle: String

    public init(sectorTitle: String) {
        self.sectorTitle = sectorTitle
    }

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You describe one month in one area of a person's life, from figures
        already computed for you. Cite only figures you are given; never
        estimate or invent one. Never propose or mention a score, and never
        give advice. If the figures are thin, say less rather than padding.
        """
    }

    public func prompt(_ context: Context) -> String {
        """
        Area: \(context.sectorTitle)

        \(context.promptLines)

        Describe what changed this month.
        """
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter SectorNoteTests`
Expected: 6 tests PASS.

- [ ] **Step 7: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Insights
git add LifeOSKit/Tests/InsightsTests/SectorNoteTests.swift
git commit -m "feat(sectors): let the on-device model describe a sector month

CoachTask's prompt was fixed at MetricsDigest, which made any task about
something other than health metrics inexpressible. One associated Context
type fixes that for every future task and changes no behaviour.

The note task sees only the evidence rows the rule actually used, so the
sentence cannot cite a figure that played no part in the number, and it is
instructed never to mention a score. The number is the rule's job."
```

---

### Task 11: The Life board

**Files:**
- Create: `LIfeOS/Features/Life/ViewModel/LifeBoardViewModel.swift`
- Create: `LIfeOS/Features/Life/View/SectorPalette.swift`
- Create: `LIfeOS/Features/Life/View/LifeBoardScreen.swift`
- Modify: `LIfeOS/App/RootView.swift:58` and `:170-176`
- Test: `LifeOSKit/Tests/SectorsTests/BoardSummaryTests.swift`
- Create: `LifeOSKit/Sources/Sectors/BoardSummary.swift`

**Interfaces:**
- Consumes: `SectorStore`, `LifeSector`, `SectorScore`.
- Produces: `BoardSummary(scores: [LifeSector: Int], previous: [LifeSector: Int])` with `lowest: LifeSector?` and `biggestMover: (sector: LifeSector, delta: Int)?`.

The header facts are pure logic, so they live in `Sectors` and are tested
there rather than in a view.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/BoardSummaryTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BoardSummaryTests {

    @Test func theLowestSectorIsFound() {
        let summary = BoardSummary(
            scores: [.body: 8, .friends: 3, .money: 6], previous: [:]
        )
        #expect(summary.lowest == .friends)
    }

    @Test func anEmptyBoardHasNoLowest() {
        #expect(BoardSummary(scores: [:], previous: [:]).lowest == nil)
    }

    @Test func theBiggestMoverIsFound() {
        let summary = BoardSummary(
            scores: [.body: 8, .friends: 3], previous: [.body: 7, .friends: 8]
        )
        #expect(summary.biggestMover?.sector == .friends)
        #expect(summary.biggestMover?.delta == -5)
    }

    /// A first month has nothing to compare against and must not claim a move.
    @Test func withNoPreviousMonthThereIsNoMover() {
        let summary = BoardSummary(scores: [.body: 8], previous: [:])
        #expect(summary.biggestMover == nil)
    }

    @Test func aSectorMissingLastMonthIsNotAMover() {
        let summary = BoardSummary(
            scores: [.body: 8, .romance: 9], previous: [.body: 8]
        )
        #expect(summary.biggestMover == nil)
    }

    /// A drop and a rise of equal size: the drop is the one worth surfacing.
    @Test func tiesGoToTheDrop() {
        let summary = BoardSummary(
            scores: [.body: 9, .friends: 3], previous: [.body: 6, .friends: 6]
        )
        #expect(summary.biggestMover?.sector == .friends)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter BoardSummaryTests`
Expected: FAIL, `cannot find 'BoardSummary' in scope`.

- [ ] **Step 3: Write the summary**

Create `LifeOSKit/Sources/Sectors/BoardSummary.swift`:

```swift
import Foundation
import Persistence

/// The two facts the board header carries.
///
/// There is deliberately no combined life score. An average of nine sectors
/// sits near the middle forever and moves by fractions, which reads as nothing
/// happening in a month where one sector collapsed and another soared. Worse,
/// it invites protecting the average instead of attending to the weak sector.
public struct BoardSummary: Sendable, Equatable {
    private let scores: [LifeSector: Int]
    private let previous: [LifeSector: Int]

    public init(scores: [LifeSector: Int], previous: [LifeSector: Int]) {
        self.scores = scores
        self.previous = previous
    }

    /// The sector most worth attention.
    ///
    /// Walks board order and `min(by:)` keeps the first of equal elements, so
    /// a tie breaks by board order rather than by dictionary iteration, which
    /// would make the header flicker between two equally low sectors.
    public var lowest: LifeSector? {
        LifeSector.boardOrder
            .compactMap { sector in scores[sector].map { (sector, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// The largest change since last month, counting only sectors scored in
    /// both. A tie goes to the drop, which is the more useful thing to say.
    public var biggestMover: (sector: LifeSector, delta: Int)? {
        let moves: [(LifeSector, Int)] = LifeSector.boardOrder.compactMap { sector in
            guard let now = scores[sector], let then = previous[sector] else { return nil }
            let delta = now - then
            return delta == 0 ? nil : (sector, delta)
        }
        guard let best = moves.max(by: { lhs, rhs in
            abs(lhs.1) < abs(rhs.1) || (abs(lhs.1) == abs(rhs.1) && lhs.1 > rhs.1)
        }) else { return nil }
        return (best.0, best.1)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter BoardSummaryTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Write the palette and the view model**

Create `LIfeOS/Features/Life/View/SectorPalette.swift`:

```swift
import SwiftUI
import Persistence

/// The one place a sector meets a colour and an icon.
///
/// Kept out of `LifeSector` so the Persistence target never imports SwiftUI.
enum SectorPalette {
    static func tint(_ sector: LifeSector) -> Color {
        switch sector {
        case .family:  .orange
        case .romance: .pink
        case .soul:    .purple
        case .friends: .yellow
        case .growth:  .green
        case .money:   .teal
        case .mission: .indigo
        case .body:    .red
        case .mind:    .blue
        }
    }

    static func icon(_ sector: LifeSector) -> String {
        switch sector {
        case .family:  "house.fill"
        case .romance: "heart.fill"
        case .soul:    "sparkles"
        case .friends: "person.2.fill"
        case .growth:  "chart.line.uptrend.xyaxis"
        case .money:   "dollarsign"
        case .mission: "target"
        case .body:    "figure.run"
        case .mind:    "brain.head.profile"
        }
    }
}
```

Create `LIfeOS/Features/Life/ViewModel/LifeBoardViewModel.swift`:

```swift
import Foundation
import SwiftData
import Persistence
import Sectors

@MainActor
@Observable
final class LifeBoardViewModel {
    struct Card: Identifiable {
        let sector: LifeSector
        let score: Int?
        let history: [Int]
        var id: LifeSector { sector }
    }

    private(set) var cards: [Card] = []
    private(set) var summary = BoardSummary(scores: [:], previous: [:])
    private(set) var monthAwaitingClose: Date?

    private let store: SectorStore
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.store = SectorStore(context: context, calendar: calendar)
        self.calendar = calendar
    }

    /// The month the board displays: the most recent one that has been closed,
    /// or the previous month when nothing has been.
    func load(now: Date = .now) {
        let thisMonth = Date.startOfMonth(now, calendar: calendar)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let monthBefore = calendar.date(byAdding: .month, value: -2, to: thisMonth) ?? thisMonth

        monthAwaitingClose = (try? store.oldestUnclosedMonth(before: thisMonth))

        let current = scoreMap(for: lastMonth)
        let previous = scoreMap(for: monthBefore)
        summary = BoardSummary(scores: current, previous: previous)

        cards = LifeSector.boardOrder.map { sector in
            Card(
                sector: sector,
                score: current[sector],
                history: (try? store.history(sector: sector, months: 6))?
                    .compactMap(\.userScore) ?? []
            )
        }
    }

    private func scoreMap(for month: Date) -> [LifeSector: Int] {
        let rows = (try? store.scores(forMonth: month)) ?? []
        return rows.reduce(into: [:]) { map, row in
            if let userScore = row.userScore { map[row.sector] = userScore }
        }
    }
}
```

- [ ] **Step 6: Write the board screen**

Create `LIfeOS/Features/Life/View/LifeBoardScreen.swift`:

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct LifeBoardScreen: View {
    @Environment(\.modelContext) private var context
    @State private var model: LifeBoardViewModel?
    @State private var isClosing = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: Space.m)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let model {
                    if let month = model.monthAwaitingClose {
                        AlertBanner(
                            title: "Close \(month.formatted(.dateTime.month(.wide)))",
                            message: "Score your nine sectors for the month."
                        ) {
                            isClosing = true
                        }
                    }

                    header(for: model)

                    LazyVGrid(columns: columns, spacing: Space.m) {
                        ForEach(model.cards) { card in
                            SectorCard(card: card)
                        }
                    }
                }
            }
            .padding(Space.m)
        }
        .task {
            let model = model ?? LifeBoardViewModel(context: context)
            self.model = model
            model.load()
        }
        .sheet(isPresented: $isClosing) {
            if let month = model?.monthAwaitingClose {
                MonthlyCloseScreen(month: month) {
                    isClosing = false
                    model?.load()
                }
            }
        }
    }

    @ViewBuilder
    private func header(for model: LifeBoardViewModel) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let lowest = model.summary.lowest {
                Text("Lowest: \(lowest.title)")
                    .font(.headline)
            }
            if let mover = model.summary.biggestMover {
                Text("Biggest move: \(mover.sector.title) \(mover.delta > 0 ? "+" : "")\(mover.delta)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SectorCard: View {
    let card: LifeBoardViewModel.Card

    var body: some View {
        PastelFillCard(tint: SectorPalette.tint(card.sector)) {
            VStack(alignment: .leading, spacing: Space.s) {
                Label(card.sector.title, systemImage: SectorPalette.icon(card.sector))
                    .font(.subheadline)

                if let score = card.score {
                    HeroNumeral(text: "\(score)")
                } else {
                    Text("-")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

                if card.history.count > 1 {
                    RoundedBarChart(values: card.history.map(Double.init))
                        .frame(height: 32)
                }
            }
        }
    }
}
```

**Read before writing this file.** The component initialisers and the `Space`
constants above are written from their names, not from their declarations.
Open `LifeOSKit/Sources/DesignSystem/PastelFillCard.swift`, `HeroNumeral.swift`,
`RoundedBarChart.swift`, `AlertBanner.swift` and `Space.swift`, and match what
is actually there. Adapt this screen to the components; do not change the
components to fit this screen. The same applies to the close screen in Task 12.

- [ ] **Step 7: Add the tab**

In `LIfeOS/App/RootView.swift:58`, extend the enum:

```swift
    private enum AppTab: Hashable { case today, health, money, plan, life }
```

In `navItems` around line 170, append:

```swift
            PillNavItem(value: AppTab.life, systemImage: "square.grid.3x3.fill", label: "Life"),
```

Add the matching branch wherever the other tabs map to their screens, following
whatever pattern the surrounding `switch` already uses:

```swift
        case .life: LifeBoardScreen()
```

- [ ] **Step 8: Build and check both idioms**

Run:
```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'generic/platform=iOS Simulator' build
```
Expected: BUILD SUCCEEDED.

Then run on an iPad simulator and confirm the board shows nine cards in three
columns beside the side rail, and on an iPhone simulator that it shows two.

- [ ] **Step 9: Commit**

```bash
git add LifeOSKit/Sources/Sectors/BoardSummary.swift \
        LifeOSKit/Tests/SectorsTests/BoardSummaryTests.swift \
        LIfeOS/Features/Life LIfeOS/App/RootView.swift
git commit -m "feat(sectors): add the Life board and its fifth tab

Nine cards from the existing component kit, so the board matches the app by
construction rather than by imitation.

The header carries the lowest sector and the biggest mover instead of a
combined life score. An average of nine sectors sits near the middle forever
and invites protecting the average instead of attending to the weak sector."
```

---

### Task 12: The monthly close

**Files:**
- Create: `LifeOSKit/Sources/Sectors/CloseProgress.swift`
- Create: `LIfeOS/Features/Life/ViewModel/MonthlyCloseViewModel.swift`
- Create: `LIfeOS/Features/Life/View/MonthlyCloseScreen.swift`
- Test: `LifeOSKit/Tests/SectorsTests/CloseProgressTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `CloseProgress(scored: Set<LifeSector>)` with `next: LifeSector?`, `position: Int`, `total: Int`, `isComplete: Bool`.

The resume rule is pure logic and is tested without a view.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/SectorsTests/CloseProgressTests.swift`:

```swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct CloseProgressTests {

    @Test func aFreshCloseStartsAtTheFirstSectorInBoardOrder() {
        let progress = CloseProgress(scored: [])
        #expect(progress.next == LifeSector.boardOrder.first)
        #expect(progress.position == 1)
        #expect(progress.total == 9)
    }

    /// Leaving midway is normal, so returning resumes rather than restarting.
    @Test func aResumedCloseSkipsWhatIsAlreadyScored() {
        let done = Set(LifeSector.boardOrder.prefix(4))
        let progress = CloseProgress(scored: done)
        #expect(progress.next == LifeSector.boardOrder[4])
        #expect(progress.position == 5)
    }

    /// A skipped sector stays genuinely unscored, so it is offered again
    /// rather than being treated as finished.
    @Test func aSkippedSectorIsStillOffered() {
        let progress = CloseProgress(scored: [LifeSector.boardOrder[1]])
        #expect(progress.next == LifeSector.boardOrder[0])
    }

    @Test func aFinishedCloseHasNoNextSector() {
        let progress = CloseProgress(scored: Set(LifeSector.allCases))
        #expect(progress.next == nil)
        #expect(progress.isComplete)
    }

    @Test func anUnfinishedCloseIsNotComplete() {
        #expect(!CloseProgress(scored: [.body]).isComplete)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter CloseProgressTests`
Expected: FAIL, `cannot find 'CloseProgress' in scope`.

- [ ] **Step 3: Write the progress type**

Create `LifeOSKit/Sources/Sectors/CloseProgress.swift`:

```swift
import Foundation
import Persistence

/// Where a close has got to.
///
/// Membership of `scored` means the person actually decided, which is why a
/// skipped sector is offered again on the next visit: a score nobody looked at
/// is noise in the history.
public struct CloseProgress: Sendable, Equatable {
    private let scored: Set<LifeSector>

    public init(scored: Set<LifeSector>) {
        self.scored = scored
    }

    public var next: LifeSector? {
        LifeSector.boardOrder.first { !scored.contains($0) }
    }

    public var position: Int { scored.count + 1 }
    public var total: Int { LifeSector.boardOrder.count }
    public var isComplete: Bool { next == nil }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter CloseProgressTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Write the close view model**

Create `LIfeOS/Features/Life/ViewModel/MonthlyCloseViewModel.swift`:

```swift
import Foundation
import SwiftData
import Persistence
import Sectors
import Insights

@MainActor
@Observable
final class MonthlyCloseViewModel {
    private(set) var sector: LifeSector?
    private(set) var evidence = Evidence()
    private(set) var proposed: Int?
    private(set) var previousUserScore: Int?
    private(set) var note: String?
    private(set) var position = 1
    private(set) var total = 9
    private(set) var isComplete = false

    /// Answers for the sector on screen, keyed by question id.
    var answers: [String: String] = [:]
    var chosenScore: Int = 5

    private let store: SectorStore
    private let month: Date
    private let calendar: Calendar
    private let engine: Engine?

    init(context: ModelContext, month: Date, engine: Engine? = nil, calendar: Calendar = .current) {
        self.store = SectorStore(context: context, calendar: calendar)
        self.month = month
        self.calendar = calendar
        self.engine = engine
    }

    var questions: [CheckInQuestion] {
        sector.map { CheckInQuestion.questions(for: $0) } ?? []
    }

    func advance() {
        let scoredSectors = Set(
            ((try? store.scores(forMonth: month)) ?? [])
                .filter(\.isScored)
                .map(\.sector)
        )
        let progress = CloseProgress(scored: scoredSectors)
        position = progress.position
        total = progress.total
        isComplete = progress.isComplete
        sector = progress.next
        answers = [:]
        note = nil

        guard let sector else { return }

        previousUserScore = previousScore(for: sector)
        for stored in (try? store.answers(sector: sector, month: month)) ?? [] {
            answers[stored.questionID] = stored.answer
        }
        recompute()
    }

    /// Rebuilds the proposal from the answers on screen.
    ///
    /// Only the check-in sectors recompute live. The data-fed sectors are
    /// scored once when the close reaches them, because nothing the person can
    /// type on this screen changes what the month's data says.
    func recompute() {
        guard let sector else { return }
        evidence = CheckInScorer(sector: sector, answers: answers).evidence()
        proposed = evidence.proposedScore
        chosenScore = proposed ?? previousUserScore ?? 5
    }

    func answer(_ question: CheckInQuestion, with value: String) {
        answers[question.id] = value
        try? store.saveAnswer(
            sector: sector ?? .body, month: month,
            questionID: question.id, answer: value
        )
        recompute()
    }

    func commit() {
        guard let sector else { return }
        let score = try? store.record(
            sector: sector, month: month, proposed: proposed, evidence: evidence
        )
        if let score {
            try? store.commit(userScore: chosenScore, to: score)
        }
        advance()
    }

    /// Moves on without deciding. The sector stays unscored on purpose.
    func skip() {
        guard let sector, let index = LifeSector.boardOrder.firstIndex(of: sector) else { return }
        let remaining = LifeSector.boardOrder[(index + 1)...]
        let scoredSectors = Set(
            ((try? store.scores(forMonth: month)) ?? []).filter(\.isScored).map(\.sector)
        )
        self.sector = remaining.first { !scoredSectors.contains($0) }
        isComplete = self.sector == nil
        if self.sector != nil { recompute() }
    }

    func loadNote() async {
        guard let sector, let engine, !evidence.isEmpty else { return }
        let context = SectorEvidenceContext(
            sectorTitle: sector.title, evidence: evidence, previousUserScore: previousUserScore
        )
        note = try? await engine.run(SectorNoteTask(sectorTitle: sector.title), context).summary
    }

    private func previousScore(for sector: LifeSector) -> Int? {
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: month) else { return nil }
        return (try? store.score(sector, month: lastMonth))?.userScore
    }
}
```

Wiring the data-fed scorers (Body, Money, Mission, Growth, Mind, Soul) into
`recompute()` needs `MetricsStore`, `MoneyStore` and `PlanStore` reads for the
month. Add them one sector at a time, each behind its own commit, using the
scorer initialisers from Tasks 5 to 8. Until then those sectors fall through
to `CheckInScorer`, which returns empty evidence and therefore proposes
nothing, which is the correct behaviour for a sector with no evidence.

- [ ] **Step 6: Write the close screen**

Create `LIfeOS/Features/Life/View/MonthlyCloseScreen.swift`:

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

struct MonthlyCloseScreen: View {
    let month: Date
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @State private var model: MonthlyCloseViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model, let sector = model.sector {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.l) {
                            Text(sector.title.uppercased())
                                .font(.title2.weight(.semibold))

                            ForEach(model.questions, id: \.id) { question in
                                questionView(question, model: model)
                            }

                            if let proposed = model.proposed {
                                Text("Proposed \(proposed)")
                                    .font(.headline)
                            }

                            ForEach(model.evidence.rows, id: \.label) { row in
                                HStack {
                                    Text(row.label)
                                    Spacer()
                                    Text(row.value).foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }

                            if let note = model.note {
                                Text(note).font(.callout).foregroundStyle(.secondary)
                            }

                            if let previous = model.previousUserScore {
                                Text("Last month you said \(previous).")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }

                            Stepper(
                                "Your score: \(model.chosenScore)",
                                value: Binding(
                                    get: { model.chosenScore },
                                    set: { model.chosenScore = $0 }
                                ),
                                in: 0...10
                            )
                        }
                        .padding(Space.m)
                    }
                    .navigationTitle("\(model.position) of \(model.total)")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Skip") { model.skip() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Next") { model.commit() }
                        }
                    }
                    .task(id: sector) { await model.loadNote() }
                } else {
                    VStack(spacing: Space.m) {
                        Text("Month closed").font(.title2)
                        Button("Done", action: onFinish)
                    }
                }
            }
        }
        .task {
            let model = model ?? MonthlyCloseViewModel(context: context, month: month)
            self.model = model
            model.advance()
        }
    }

    @ViewBuilder
    private func questionView(_ question: CheckInQuestion, model: MonthlyCloseViewModel) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(question.prompt).font(.subheadline)
            if question.isFreeText {
                TextField("", text: Binding(
                    get: { model.answers[question.id] ?? "" },
                    set: { model.answer(question, with: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                ForEach(question.options, id: \.label) { option in
                    Button(option.label) { model.answer(question, with: option.label) }
                        .buttonStyle(.bordered)
                        .tint(model.answers[question.id] == option.label ? .accentColor : .gray)
                }
            }
        }
    }
}
```

- [ ] **Step 7: Build and walk the close by hand**

Run:
```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'generic/platform=iOS Simulator' build
```
Expected: BUILD SUCCEEDED.

Then in a simulator: open Life, tap the close banner, score three sectors,
close the sheet, reopen it, and confirm it resumes at the fourth sector rather
than restarting. Skip one sector and confirm it is offered again next time.

- [ ] **Step 8: Run the whole suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add LifeOSKit/Sources/Sectors/CloseProgress.swift \
        LifeOSKit/Tests/SectorsTests/CloseProgressTests.swift \
        LIfeOS/Features/Life
git commit -m "feat(sectors): walk the nine sectors in a monthly close

Each sector commits as the person passes it, so leaving midway is normal
rather than an error state and returning resumes at the first unscored
sector.

A skipped sector stays genuinely unscored and is offered again, because a
score nobody looked at is noise in the history."
```

---

## Verification

After Task 12:

- [ ] `swift test --package-path LifeOSKit` passes, and the count has grown from 250 by roughly 70 tests.
- [ ] `xcodebuild ... -destination 'generic/platform=iOS Simulator' build` succeeds.
- [ ] On an iPad simulator in both portrait and landscape, the board shows nine cards and the close is readable.
- [ ] A fresh install shows nine cards each reading `-`, and the close banner offers the previous month.
- [ ] Scoring a sector, killing the app, and reopening shows that sector's number on the board.

## Deferred

From the spec's "Out of scope", plus one thing this plan defers on its own:

- Mood tracking and between-close logging for the relational sectors.
- Money budgeting, targets, loans. Mission PARA and goal horizons.
- A single combined life score. User-editable weights. Close reminders.
- **Wiring the six data-fed scorers into `recompute()`.** Task 12 leaves them
  falling through to an empty proposal. Each needs a store read for the month
  and is a small commit of its own; do them before calling the feature done.
