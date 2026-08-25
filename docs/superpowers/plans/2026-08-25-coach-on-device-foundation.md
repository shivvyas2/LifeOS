# Coach On-Device Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working AI coach that runs entirely on-device — daily brief and ask-anything chat — at zero cost, with no server, no API key, and no network.

**Architecture:** A new `Insights` target in `LifeOSKit` wraps Apple's `FoundationModels`. One `@Generable` struct per coach task defines its output; `MetricsDigest` is a `Sendable` value type that carries derived numbers out of `Persistence` so raw health records can never reach a model. A `CoachRouter` runs tasks against an `OnDeviceEngine` and classifies failures through a pure `EscalationPolicy` function. The remote engine that policy escalates *to* is Plan 2 — until then, escalation resolves to `.unavailable`, which is a real, shippable behaviour rather than a stub.

**Tech Stack:** Swift 6 (strict concurrency), SwiftData, `FoundationModels` (iOS 26), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-08-25-coach-llm-routing-design.md`

## Global Constraints

- **Minimum OS:** iOS 26.0 / macOS 26.0. Already set in `LifeOSKit/Package.swift` and the Xcode project.
- **Swift 6, strict concurrency.** Every type crossing an `async` boundary must be `Sendable`. `LanguageModelSession` is a `final class` and is **not** `Sendable` — never store one in a `Sendable` type; create it inside the call.
- **Nothing outside `Insights` imports `FoundationModels`.** (Spec §4.)
- **`Insights` depends on `Persistence` only.** Never `Integrations`, never HealthKit, never Whoop. (Spec §4.)
- **`DailyMetrics` must never cross into an engine.** It is a SwiftData `@Model` class and is not `Sendable`; engines take `MetricsDigest`. (Spec §6.)
- **Test naming follows the existing codebase:** full sentences, e.g. `@Test func aTokenAboutToExpireIsTreatedAsAlreadyExpired()`. See `LifeOSKit/Tests/IntegrationsTests/WhoopTokenTests.swift`.
- **Run tests with:** `swift test --package-path LifeOSKit` (add `--filter` to narrow).
- **Commit style:** lowercase `type(scope): imperative summary`, matching recent history. No `Co-Authored-By` trailer.

---

## File Structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Package.swift` | Adds the `Insights` target and `InsightsTests` test target |
| `Sources/Insights/Tasks/DailyBrief.swift` | The `@Generable` output type for the daily brief |
| `Sources/Insights/Tasks/CoachAnswer.swift` | The `@Generable` output type for chat |
| `Sources/Insights/CoachTask.swift` | `CoachTask` protocol, `Tier`, and the two task definitions |
| `Sources/Insights/Context/MetricsDigest.swift` | The privacy boundary: `Persistence` rows → `Sendable` aggregates |
| `Sources/Insights/EscalationPolicy.swift` | Pure `GenerationError` → `Disposition` classification |
| `Sources/Insights/ModelAvailability.swift` | Pure mapping of `SystemLanguageModel.Availability` |
| `Sources/Insights/Engines/Engine.swift` | The `Engine` protocol both tiers satisfy |
| `Sources/Insights/Engines/OnDeviceEngine.swift` | `LanguageModelSession` wrapper |
| `Sources/Insights/CoachRouter.swift` | Tier selection, escalation handling, `CoachResult` |
| `Sources/Insights/BriefCache.swift` | One brief per calendar day |
| `Tests/InsightsTests/*` | One suite per source file above |

**Why `EscalationPolicy` and `ModelAvailability` are separate files rather than methods on the router:** both are pure functions over enums, and they carry the highest-value tests in this plan. Keeping them out of the router means they can be tested exhaustively without a model, a container, or a network.

---

### Task 1: The `Insights` target and the schema pin

This task exists to answer one question as cheaply as possible: **does `GenerationSchema`'s `Codable` output look like JSON Schema?** The spec's entire shared-contract decision (§5) rests on it. If it fails here, Plan 2 changes shape before a line of it is written.

**Files:**
- Modify: `LifeOSKit/Package.swift`
- Create: `LifeOSKit/Sources/Insights/Tasks/DailyBrief.swift`
- Test: `LifeOSKit/Tests/InsightsTests/SchemaEncodingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public struct DailyBrief` — `@Generable`, `Sendable`, `Equatable`, with `headline: String` and `observations: [String]`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/SchemaEncodingTests.swift`:

```swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

/// Everything in the cloud tier depends on a `@Generable` type's schema
/// surviving a round trip through JSON, so a provider that has never heard of
/// `FoundationModels` can still be told what shape to return. This suite is
/// the load-bearing assumption of the whole design, isolated and pinned.
@Suite struct SchemaEncodingTests {

    @Test func theBriefSchemaEncodesAsAJSONObject() throws {
        let data = try JSONEncoder().encode(DailyBrief.generationSchema)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "object")
    }

    @Test func theBriefSchemaCarriesOurPropertyNames() throws {
        let data = try JSONEncoder().encode(DailyBrief.generationSchema)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let properties = try #require(json["properties"] as? [String: Any])

        #expect(properties.keys.contains("headline"))
        #expect(properties.keys.contains("observations"))
    }

    /// The inverse leg: a JSON string from any provider must decode into the
    /// same type the on-device model produces.
    @Test func aJSONReplyDecodesIntoTheSameType() throws {
        let reply = """
        {"headline":"Recovery is low.","observations":["Slept 5h12m.","HRV down 18%."]}
        """
        let brief = try DailyBrief(GeneratedContent(json: reply))

        #expect(brief.headline == "Recovery is low.")
        #expect(brief.observations.count == 2)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter SchemaEncodingTests`

Expected: FAIL — `no such module 'Insights'`.

- [ ] **Step 3: Add the target to `Package.swift`**

In `LifeOSKit/Package.swift`, add to `products`:

```swift
        .library(name: "Insights", targets: ["Insights"]),
```

and to `targets`:

```swift
        .target(name: "Insights", dependencies: ["Persistence"]),
        .testTarget(name: "InsightsTests", dependencies: ["Insights"]),
```

- [ ] **Step 4: Write `DailyBrief`**

Create `LifeOSKit/Sources/Insights/Tasks/DailyBrief.swift`:

```swift
import FoundationModels

/// What the coach says about today.
///
/// Deliberately small. The on-device model has a context window measured in
/// thousands of tokens, and a wide schema is the fastest way to spend it on
/// structure instead of substance.
@Generable
public struct DailyBrief: Equatable, Sendable {

    @Guide(description: "One sentence on how the body is doing today. Plain and specific. No encouragement, no advice.")
    public var headline: String

    @Guide(
        description: "Concrete observations, each tied to a number that appears in the data. Never invent a figure.",
        .count(2...3)
    )
    public var observations: [String]
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter SchemaEncodingTests`

Expected: PASS, 3 tests.

**If `theBriefSchemaEncodesAsAJSONObject` or `...CarriesOurPropertyNames` fails**, this is the finding the task was written to produce — do not paper over it. Print the actual encoding with `String(data: data, encoding: .utf8)` and record it in the task's commit message. If the shape is JSON-Schema-compatible but nested differently (say, wrapped in an envelope), adjust the assertions to match reality and note the unwrapping that Plan 2's remote engine will need. If it is not JSON-Schema-shaped at all, stop and report: the spec's fallback is a `GenerationSchema` → JSON Schema adapter, and that is a change to Plan 2's scope that needs to be made deliberately.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/Insights LifeOSKit/Tests/InsightsTests
git commit -m "feat(insights): add the module, and pin the schema round trip

The cloud tier's whole premise is that one @Generable type can describe
its output to a provider that has never heard of FoundationModels. That
holds only if GenerationSchema's Codable output is JSON-Schema shaped and
GeneratedContent(json:) can read a reply back. Both are now asserted, so
the assumption fails here rather than halfway through the remote engine."
```

---

### Task 2: `MetricsDigest`, the privacy boundary

**Files:**
- Create: `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift`
- Test: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`

**Interfaces:**
- Consumes: `Persistence.DailyMetrics`.
- Produces:
  - `public struct MetricsDigest: Sendable, Equatable` with `days: [MetricsDigest.Day]` and `averages: MetricsDigest.Averages`
  - `public struct MetricsDigest.Day: Sendable, Equatable` — `date: Date`, `recoveryPct: Int?`, `sleepMinutes: Int?`, `strain: Double?`, `steps: Int?`, `exerciseMinutes: Int?`
  - `public struct MetricsDigest.Averages: Sendable, Equatable` — `recoveryPct: Int?`, `sleepMinutes: Int?`, `steps: Int?`
  - `public static func MetricsDigest.from(_ rows: [DailyMetrics]) -> MetricsDigest`
  - `public var MetricsDigest.promptLines: String`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct MetricsDigestTests {

    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func aDigestCarriesOneEntryPerDay() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.days.count == 1)
        #expect(digest.days[0].steps == 8_000)
    }

    /// A missing value and a zero must never become the same thing, which is
    /// the rule `DailyMetrics` is built around. The digest inherits it.
    @Test func aMissingMetricStaysNilRatherThanBecomingZero() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.days[0].steps == 8_000)
        #expect(digest.days[0].sleepMinutes == nil)
        #expect(digest.days[0].recoveryPct == nil)
    }

    @Test func averagesIgnoreDaysWithNoReading() throws {
        let store = try makeStore()
        let second = day.addingTimeInterval(86_400)
        try store.upsert(date: day) { $0.steps = 10_000 }
        try store.upsert(date: second) { $0.weightKg = 78 }   // no steps

        let digest = MetricsDigest.from(try store.metrics(from: day, to: second))

        // 10_000 over one contributing day, not 5_000 over two.
        #expect(digest.averages.steps == 10_000)
    }

    @Test func averagesAreNilWhenNothingContributes() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.weightKg = 78 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.averages.steps == nil)
    }

    /// The privacy rule made mechanical: whatever else changes about the
    /// digest, the raw Whoop surface must not appear in what we send.
    @Test func thePromptTextCarriesNoRawWhoopFields() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
            $0.skinTempCelsius = 33.4
            $0.respiratoryRate = 14.2
        }

        let text = MetricsDigest.from(try store.metrics(from: day, to: day)).promptLines

        #expect(text.contains("62"))              // the aggregate is wanted
        #expect(text.contains("41.2") == false)   // HRV series is not
        #expect(text.contains("97.5") == false)
        #expect(text.contains("33.4") == false)
        #expect(text.contains("14.2") == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter MetricsDigestTests`

Expected: FAIL — `cannot find 'MetricsDigest' in scope`.

- [ ] **Step 3: Write `MetricsDigest`**

Create `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift`:

```swift
import Foundation
import Persistence

/// The only thing an engine is ever given.
///
/// `DailyMetrics` is a SwiftData `@Model` class: not `Sendable`, and full of
/// raw per-source detail. `MetricsDigest` is a value type of derived numbers.
/// Because `Engine.run` takes a digest, the compiler — not a reviewer — is
/// what stops a raw health record reaching a model.
///
/// It is also the largest token lever in the system: a day is a handful of
/// numbers here, against thousands of tokens of rows.
public struct MetricsDigest: Sendable, Equatable {

    public struct Day: Sendable, Equatable {
        public let date: Date
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let strain: Double?
        public let steps: Int?
        public let exerciseMinutes: Int?
    }

    public struct Averages: Sendable, Equatable {
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let steps: Int?
    }

    public let days: [Day]
    public let averages: Averages

    public static func from(_ rows: [DailyMetrics]) -> MetricsDigest {
        let days = rows
            .sorted { $0.date < $1.date }
            .map { row in
                Day(
                    date: row.date,
                    recoveryPct: row.whoopRecoveryPct.map { Int($0.rounded()) },
                    sleepMinutes: row.sleepMinutes,
                    strain: row.whoopDayStrain,
                    steps: row.steps,
                    exerciseMinutes: row.exerciseMinutes
                )
            }

        return MetricsDigest(
            days: days,
            averages: Averages(
                recoveryPct: average(days.compactMap(\.recoveryPct)),
                sleepMinutes: average(days.compactMap(\.sleepMinutes)),
                steps: average(days.compactMap(\.steps))
            )
        )
    }

    /// Nil rather than zero when nothing contributed: an average of no
    /// readings is not an average of zero.
    private static func average(_ values: [Int]) -> Int? {
        guard values.isEmpty == false else { return nil }
        return values.reduce(0, +) / values.count
    }

    /// The digest as the model sees it. One line per day, omitting anything
    /// missing rather than writing "nil" — a blank costs no tokens and says
    /// the same thing.
    public var promptLines: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        return days.map { day in
            var parts: [String] = [formatter.string(from: day.date)]
            if let v = day.recoveryPct { parts.append("recovery \(v)%") }
            if let v = day.sleepMinutes { parts.append("sleep \(v / 60)h\(v % 60)m") }
            if let v = day.strain { parts.append("strain \(String(format: "%.1f", v))") }
            if let v = day.steps { parts.append("steps \(v)") }
            if let v = day.exerciseMinutes { parts.append("exercise \(v)m") }
            return parts.joined(separator: ", ")
        }
        .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter MetricsDigestTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/Context LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift
git commit -m "feat(insights): carry aggregates to the model, never rows

MetricsDigest is the only thing an engine is given. DailyMetrics is a
SwiftData model class and not Sendable, so making the digest the argument
type means the compiler stops a raw health record reaching a model rather
than a reviewer having to notice. The same choice is the largest token
lever available: a day becomes a handful of numbers instead of a row."
```

---

### Task 3: The `CoachTask` contract

**Files:**
- Create: `LifeOSKit/Sources/Insights/CoachTask.swift`
- Create: `LifeOSKit/Sources/Insights/Tasks/CoachAnswer.swift`
- Test: `LifeOSKit/Tests/InsightsTests/CoachTaskTests.swift`

**Interfaces:**
- Consumes: `MetricsDigest` (Task 2), `DailyBrief` (Task 1).
- Produces:
  - `public enum Tier: Sendable, Equatable` — `.onDevice`, `.cloud(Tier.Role)`; `public enum Tier.Role: String, Sendable, Codable` — `.reasoning`, `.vision`
  - `public protocol CoachTask: Sendable` — `associatedtype Output: Generable`, `var floor: Tier`, `var instructions: String`, `func prompt(_ digest: MetricsDigest) -> String`
  - `public struct BriefTask: CoachTask` where `Output == DailyBrief`
  - `public struct AnswerTask: CoachTask` where `Output == CoachAnswer`, `public init(question: String)`
  - `public struct CoachAnswer` — `@Generable`, `answer: String`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/CoachTaskTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct CoachTaskTests {

    private func digest() throws -> MetricsDigest {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
        }
        return MetricsDigest.from(try store.metrics(from: day, to: day))
    }

    @Test func theBriefRunsOnDeviceByDefault() {
        #expect(BriefTask().floor == .onDevice)
    }

    @Test func chatRunsOnDeviceByDefault() {
        #expect(AnswerTask(question: "why is my recovery low?").floor == .onDevice)
    }

    @Test func theBriefPromptCarriesTheDigest() throws {
        let prompt = BriefTask().prompt(try digest())

        #expect(prompt.contains("62"))
        #expect(prompt.contains("8000"))
    }

    @Test func aChatPromptCarriesBothTheQuestionAndTheDigest() throws {
        let prompt = AnswerTask(question: "how did I sleep?").prompt(try digest())

        #expect(prompt.contains("how did I sleep?"))
        #expect(prompt.contains("62"))
    }

    /// Instructions are cacheable prefix and must not vary per request; a
    /// digest baked into them would defeat that and change every call.
    @Test func instructionsDoNotVaryWithTheData() throws {
        let task = BriefTask()
        #expect(task.instructions == BriefTask().instructions)
        #expect(task.instructions.contains("62") == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter CoachTaskTests`

Expected: FAIL — `cannot find 'BriefTask' in scope`.

- [ ] **Step 3: Write the contract and the two tasks**

Create `LifeOSKit/Sources/Insights/CoachTask.swift`:

```swift
import Foundation
import FoundationModels

/// Which model a task needs at minimum.
///
/// A task names a *floor*, not a model. The app never learns that a model has
/// a name — the mapping from role to model lives server-side, so changing it
/// is configuration rather than a release.
public enum Tier: Sendable, Equatable {
    case onDevice
    case cloud(Role)

    public enum Role: String, Sendable, Codable {
        case reasoning
        case vision
    }
}

/// One unit of coach work.
///
/// The output type is `Generable`, which is what lets a single declaration
/// serve both the on-device model and a cloud provider: the same type yields
/// a schema to send and decodes the reply that comes back.
public protocol CoachTask: Sendable {
    associatedtype Output: Generable

    var floor: Tier { get }

    /// Stable across requests. Anything that varies belongs in `prompt`.
    var instructions: String { get }

    func prompt(_ digest: MetricsDigest) -> String
}

public struct BriefTask: CoachTask {
    public typealias Output = DailyBrief

    public init() {}

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You read one person's health metrics and say what today looks like.
        Be specific and quantitative. Cite only numbers that appear in the
        data given to you; never estimate or invent one. If the data is thin,
        say less rather than padding.
        """
    }

    public func prompt(_ digest: MetricsDigest) -> String {
        """
        Here are the most recent days:

        \(digest.promptLines)

        Write today's brief.
        """
    }
}

public struct AnswerTask: CoachTask {
    public typealias Output = CoachAnswer

    public let question: String

    public init(question: String) {
        self.question = question
    }

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You answer questions about one person's health metrics.
        Cite only numbers that appear in the data given to you. If the data
        does not contain the answer, say so plainly rather than guessing.
        """
    }

    public func prompt(_ digest: MetricsDigest) -> String {
        """
        Here are the most recent days:

        \(digest.promptLines)

        Question: \(question)
        """
    }
}
```

Create `LifeOSKit/Sources/Insights/Tasks/CoachAnswer.swift`:

```swift
import FoundationModels

@Generable
public struct CoachAnswer: Equatable, Sendable {

    @Guide(description: "A direct answer in one short paragraph. No preamble, no restating the question.")
    public var answer: String
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter CoachTaskTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/CoachTask.swift LifeOSKit/Sources/Insights/Tasks/CoachAnswer.swift LifeOSKit/Tests/InsightsTests/CoachTaskTests.swift
git commit -m "feat(insights): define a coach task by its output type and its floor

A task names the least capable tier that can serve it, never a model. The
app therefore never learns a model has a name, which is what keeps
changing models a server-side config change instead of a release.

Instructions are split from prompt because instructions are stable and
prompts are not; folding the digest into instructions would change the
cacheable prefix on every single call."
```

---

### Task 4: The escalation policy

The highest-value pure logic in the plan. Every branch is testable without a model, a network, or a container.

**Files:**
- Create: `LifeOSKit/Sources/Insights/EscalationPolicy.swift`
- Test: `LifeOSKit/Tests/InsightsTests/EscalationPolicyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum Disposition: Sendable, Equatable` — `.escalate`, `.retryLocally`, `.retryThenEscalate`, `.surface`, `.programmerError`
  - `public enum EscalationPolicy` with `public static func disposition(for error: LanguageModelSession.GenerationError) -> Disposition`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/EscalationPolicyTests.swift`:

```swift
import Testing
import FoundationModels
@testable import Insights

@Suite struct EscalationPolicyTests {

    private let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    @Test func runningOutOfContextEscalates() {
        #expect(EscalationPolicy.disposition(for: .exceededContextWindowSize(context)) == .escalate)
    }

    @Test func missingModelAssetsEscalate() {
        #expect(EscalationPolicy.disposition(for: .assetsUnavailable(context)) == .escalate)
    }

    @Test func aSystemThrottleEscalatesRatherThanWaits() {
        #expect(EscalationPolicy.disposition(for: .rateLimited(context)) == .escalate)
    }

    @Test func anUnsupportedLocaleEscalates() {
        #expect(EscalationPolicy.disposition(for: .unsupportedLanguageOrLocale(context)) == .escalate)
    }

    @Test func aLostSchemaIsRetriedBeforeItCostsMoney() {
        #expect(EscalationPolicy.disposition(for: .decodingFailure(context)) == .retryThenEscalate)
    }

    /// Concurrent requests are our own bug: the router is supposed to
    /// serialise. Escalating would mean paying money for a race condition.
    @Test func ourOwnConcurrencyBugIsRetriedLocallyAndNeverBilled() {
        #expect(EscalationPolicy.disposition(for: .concurrentRequests(context)) == .retryLocally)
    }

    /// A guide the model cannot honour is a static property of our schema.
    /// Escalating would hide a bug we would never otherwise find.
    @Test func anImpossibleGuideIsOurBugAndMustNotBeHidden() {
        #expect(EscalationPolicy.disposition(for: .unsupportedGuide(context)) == .programmerError)
    }

    /// The important one. Re-routing a refused request to a different
    /// provider to get the answer anyway is guardrail laundering, and in a
    /// health app the refusals cluster exactly where that is worst.
    @Test func aRefusalIsSurfacedAndNeverEscalated() {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        #expect(EscalationPolicy.disposition(for: .refusal(refusal, context)) == .surface)
    }

    @Test func aGuardrailViolationIsSurfacedAndNeverEscalated() {
        #expect(EscalationPolicy.disposition(for: .guardrailViolation(context)) == .surface)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter EscalationPolicyTests`

Expected: FAIL — `cannot find 'EscalationPolicy' in scope`.

- [ ] **Step 3: Write the policy**

Create `LifeOSKit/Sources/Insights/EscalationPolicy.swift`:

```swift
import FoundationModels

/// What to do when the on-device model fails.
public enum Disposition: Sendable, Equatable {
    /// The cloud can serve this; the on-device model cannot.
    case escalate
    /// Our fault, and transient. Try again here.
    case retryLocally
    /// One more local attempt, then the cloud.
    case retryThenEscalate
    /// Show the user. Do not route around it.
    case surface
    /// Our fault, and permanent. Fail loudly.
    case programmerError
}

/// The escalation table from the design spec, as a pure function.
///
/// Kept separate from the router precisely so that every branch can be
/// exercised without a model, a network, or a container.
public enum EscalationPolicy {

    public static func disposition(
        for error: LanguageModelSession.GenerationError
    ) -> Disposition {
        switch error {
        case .exceededContextWindowSize:
            // The expected trigger. The cloud has room; we do not.
            return .escalate

        case .assetsUnavailable, .rateLimited, .unsupportedLanguageOrLocale:
            return .escalate

        case .decodingFailure:
            // A small model losing a schema is often a one-off. Spend a free
            // retry before spending money.
            return .retryThenEscalate

        case .concurrentRequests:
            // The router is supposed to serialise. This is our bug, and
            // billing a cloud call for it would hide that.
            return .retryLocally

        case .unsupportedGuide:
            // A @Guide the model cannot honour is a static property of our
            // own schema. It will fail identically on every request forever.
            return .programmerError

        case .refusal, .guardrailViolation:
            // Never escalate. Re-routing a refused request to another
            // provider to obtain the answer anyway is guardrail laundering.
            return .surface

        @unknown default:
            // A case Apple added after this was written. Surfacing is the
            // conservative choice: it cannot spend money and cannot hide a
            // safety decision.
            return .surface
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter EscalationPolicyTests`

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/EscalationPolicy.swift LifeOSKit/Tests/InsightsTests/EscalationPolicyTests.swift
git commit -m "feat(insights): decide what a local failure means, as a pure function

Not every on-device failure should reach for the cloud. Running out of
context should; a concurrency bug of ours should not, because escalating
it means paying money for a race condition. An unsupported guide should
fail loudly, because it is a static property of our schema that would
otherwise be hidden behind a cloud call forever.

A refusal is never escalated. Re-routing a refused request to another
provider to get the answer anyway is guardrail laundering, and in a
health app those refusals cluster around exactly the subjects where
routing around them is most harmful."
```

---

### Task 5: Model availability

**Files:**
- Create: `LifeOSKit/Sources/Insights/ModelAvailability.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ModelAvailabilityTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum ModelAvailability: Sendable, Equatable` — `.available`, `.unavailablePermanently`, `.unavailableForNow`
  - `public static func ModelAvailability.from(_ availability: SystemLanguageModel.Availability) -> ModelAvailability`
  - `public var ModelAvailability.isWorthReChecking: Bool`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/ModelAvailabilityTests.swift`:

```swift
import Testing
import FoundationModels
@testable import Insights

@Suite struct ModelAvailabilityTests {

    @Test func anAvailableModelIsAvailable() {
        #expect(ModelAvailability.from(.available) == .available)
    }

    /// Hardware eligibility cannot change while the app is running, so this
    /// answer is resolved once and cached.
    @Test func anIneligibleDeviceIsPermanentlyUnavailable() {
        #expect(ModelAvailability.from(.unavailable(.deviceNotEligible)) == .unavailablePermanently)
    }

    @Test func apppleIntelligenceBeingOffIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.appleIntelligenceNotEnabled)) == .unavailableForNow)
    }

    @Test func aModelStillDownloadingIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.modelNotReady)) == .unavailableForNow)
    }

    @Test func onlyTheTransientCasesAreReChecked() {
        #expect(ModelAvailability.available.isWorthReChecking == false)
        #expect(ModelAvailability.unavailablePermanently.isWorthReChecking == false)
        #expect(ModelAvailability.unavailableForNow.isWorthReChecking == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter ModelAvailabilityTests`

Expected: FAIL — `cannot find 'ModelAvailability' in scope`.

- [ ] **Step 3: Write the mapping**

Create `LifeOSKit/Sources/Insights/ModelAvailability.swift`:

```swift
import FoundationModels

/// Apple's availability, collapsed to the distinction the router acts on:
/// is it worth asking again?
///
/// Hardware eligibility never changes while the process is alive. Apple
/// Intelligence being switched off, or a model still downloading, both do.
/// Asking the framework on every request wastes work on the first and gives
/// a stale answer on the others, so the router caches by this distinction.
public enum ModelAvailability: Sendable, Equatable {
    case available
    case unavailablePermanently
    case unavailableForNow

    public static func from(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailablePermanently
            case .appleIntelligenceNotEnabled, .modelNotReady:
                return .unavailableForNow
            @unknown default:
                // Unknown reasons are assumed transient: re-checking costs a
                // property read, while wrongly caching "never" would disable
                // the free tier for the life of the process.
                return .unavailableForNow
            }
        }
    }

    public var isWorthReChecking: Bool {
        self == .unavailableForNow
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter ModelAvailabilityTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/ModelAvailability.swift LifeOSKit/Tests/InsightsTests/ModelAvailabilityTests.swift
git commit -m "feat(insights): collapse model availability to whether it is worth asking again

Hardware eligibility cannot change while the process lives; Apple
Intelligence being off, or a model still downloading, both can. One
distinction, so the router can cache the permanent answer and re-check
only the answers that move. An unknown reason is treated as transient:
re-checking costs a property read, while wrongly caching 'never' would
disable the free tier for the whole session."
```

---

### Task 6: `OnDeviceEngine` and the router

**Files:**
- Create: `LifeOSKit/Sources/Insights/Engines/Engine.swift`
- Create: `LifeOSKit/Sources/Insights/Engines/OnDeviceEngine.swift`
- Create: `LifeOSKit/Sources/Insights/CoachRouter.swift`
- Test: `LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift`

**Interfaces:**
- Consumes: `CoachTask`, `MetricsDigest`, `EscalationPolicy`, `Disposition`, `ModelAvailability`.
- Produces:
  - `public protocol Engine: Sendable` — `func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output`
  - `public struct OnDeviceEngine: Engine` — `public init()`
  - `public enum CoachResult<Output: Sendable>: Sendable` — `.answered(Output)`, `.degraded(Output)`, `.refused(String)`, `.exhausted`, `.unavailable`
  - `public actor CoachRouter` — `public init(onDevice: any Engine, remote: (any Engine)?, availability: @Sendable () -> ModelAvailability)`, `public func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async -> CoachResult<T.Output>`

**Note on Swift 6:** `LanguageModelSession` is a `final class` with no `Sendable` conformance, so `OnDeviceEngine` must **not** store one. It creates a session per call. That is correct for one-shot tasks; multi-turn chat that reuses a transcript is a Plan 2 concern.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift`:

```swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

/// A stand-in engine, so the router's decisions can be tested without a model.
private struct StubEngine: Engine {
    let outcome: @Sendable () throws -> DailyBrief

    func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output {
        try outcome() as! T.Output
    }
}

@Suite struct CoachRouterTests {

    private let empty = MetricsDigest(
        days: [],
        averages: MetricsDigest.Averages(recoveryPct: nil, sleepMinutes: nil, steps: nil)
    )

    private let brief = DailyBrief(headline: "Fine.", observations: ["a", "b"])
    private let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    private func router(
        onDevice: @escaping @Sendable () throws -> DailyBrief,
        remote: (@Sendable () throws -> DailyBrief)? = nil,
        availability: ModelAvailability = .available
    ) -> CoachRouter {
        CoachRouter(
            onDevice: StubEngine(outcome: onDevice),
            remote: remote.map { StubEngine(outcome: $0) },
            availability: { availability }
        )
    }

    @Test func aSuccessfulLocalRunIsAnswered() async {
        let result = await router(onDevice: { self.brief }).run(BriefTask(), empty)
        #expect(result == .answered(brief))
    }

    /// With no remote engine — the shape this app ships in before the cloud
    /// tier exists — an escalating failure is unavailable, not a crash.
    @Test func anEscalationWithNoRemoteEngineIsUnavailable() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    @Test func anEscalationReachesTheRemoteEngineWhenThereIsOne() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(self.context) },
            remote: { cloud }
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    @Test func aRefusalIsSurfacedEvenWhenARemoteEngineIsAvailable() async {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.refusal(refusal, self.context) },
            remote: { DailyBrief(headline: "Should never be reached.", observations: ["a", "b"]) }
        ).run(BriefTask(), empty)

        guard case .refused = result else {
            Issue.record("a refusal must never be answered by the cloud, got \(result)")
            return
        }
    }

    @Test func anIneligibleDeviceGoesStraightToTheCloud() async {
        let cloud = DailyBrief(headline: "From the cloud.", observations: ["a", "b"])
        let result = await router(
            onDevice: { Issue.record("the on-device engine must not be called"); return self.brief },
            remote: { cloud },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .answered(cloud))
    }

    /// The policy calls a concurrency failure our own bug. This is the router
    /// honouring that: however many times it fails, it must not reach for a
    /// paid engine, even when one is sitting right there.
    @Test func ourOwnConcurrencyBugNeverReachesThePaidEngine() async {
        let result = await router(
            onDevice: { throw LanguageModelSession.GenerationError.concurrentRequests(self.context) },
            remote: {
                Issue.record("a concurrency bug of ours must never be billed to the cloud")
                return self.brief
            }
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }

    @Test func anIneligibleDeviceWithNoCloudIsUnavailable() async {
        let result = await router(
            onDevice: { self.brief },
            availability: .unavailablePermanently
        ).run(BriefTask(), empty)

        #expect(result == .unavailable)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter CoachRouterTests`

Expected: FAIL — `cannot find 'Engine' in scope`.

- [ ] **Step 3: Write the engine protocol and the on-device engine**

Create `LifeOSKit/Sources/Insights/Engines/Engine.swift`:

```swift
/// What both tiers look like from the router's side.
///
/// Deliberately one method. When iOS 27's `LanguageModelExecutor` ships, the
/// remote engine conforms to Apple's protocol instead and this one is deleted
/// without any caller changing.
public protocol Engine: Sendable {
    func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output
}
```

Create `LifeOSKit/Sources/Insights/Engines/OnDeviceEngine.swift`:

```swift
import FoundationModels

/// Apple's on-device model.
///
/// A session is created per call rather than stored: `LanguageModelSession` is
/// a non-`Sendable` final class, and `Engine` is `Sendable`. That is also the
/// right lifetime for one-shot tasks — a session carries a transcript, and a
/// brief has no conversation to remember.
public struct OnDeviceEngine: Engine {

    public init() {}

    public func run<T: CoachTask>(_ task: T, _ digest: MetricsDigest) async throws -> T.Output {
        let session = LanguageModelSession(instructions: task.instructions)
        let response = try await session.respond(
            to: task.prompt(digest),
            generating: T.Output.self
        )
        return response.content
    }
}
```

- [ ] **Step 4: Write the router**

Create `LifeOSKit/Sources/Insights/CoachRouter.swift`:

```swift
import Foundation
import FoundationModels

/// What the UI renders. Failures are states, not thrown errors, because every
/// one of them has a different right answer on screen.
public enum CoachResult<Output: Sendable>: Sendable {
    /// Served at or above the tier the task asked for.
    case answered(Output)
    /// The on-device model answered where the cloud was wanted. Say so — a
    /// weekly review that silently ran locally reads as the coach getting
    /// worse for no reason. Never mentions the allowance.
    ///
    /// Nothing in Plan 1 produces this: escalating *up* to the cloud is the
    /// router working, not degrading. Plan 2 produces it, when a cloud-floor
    /// task falls back because the allowance is spent.
    case degraded(Output)
    /// A safety refusal, with its explanation. Offers no retry.
    case refused(String)
    /// The monthly allowance is spent and this task needs the cloud.
    /// Produced by Plan 2; declared here so the UI seam is complete.
    case exhausted
    /// The cloud path cannot run right now. Transient; retry is the right
    /// affordance, and the allowance is never mentioned.
    case unavailable
}

extension CoachResult: Equatable where Output: Equatable {}

/// Picks a tier, and decides what a failure means.
///
/// An actor because `.concurrentRequests` is a real on-device failure mode:
/// serialising here is cheaper than handling it, and the escalation policy
/// treats that error as our bug precisely because this type is supposed to
/// prevent it.
public actor CoachRouter {

    private let onDevice: any Engine
    private let remote: (any Engine)?
    private let availability: @Sendable () -> ModelAvailability
    private var cachedAvailability: ModelAvailability?

    public init(
        onDevice: any Engine,
        remote: (any Engine)?,
        availability: @escaping @Sendable () -> ModelAvailability = {
            ModelAvailability.from(SystemLanguageModel.default.availability)
        }
    ) {
        self.onDevice = onDevice
        self.remote = remote
        self.availability = availability
    }

    public func run<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest
    ) async -> CoachResult<T.Output> {
        if case .cloud = task.floor {
            return await runRemote(task, digest)
        }
        guard currentAvailability() == .available else {
            return await runRemote(task, digest)
        }
        return await runLocal(task, digest, retriesLeft: 1)
    }

    private func runLocal<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest,
        retriesLeft: Int
    ) async -> CoachResult<T.Output> {
        do {
            return .answered(try await onDevice.run(task, digest))
        } catch let error as LanguageModelSession.GenerationError {
            switch EscalationPolicy.disposition(for: error) {
            case .escalate:
                return await runRemote(task, digest)

            case .retryLocally:
                // Never reaches the cloud, however many times it fails. This
                // error means the router failed to serialise, and billing a
                // cloud call for our own race condition is exactly what the
                // policy exists to prevent.
                guard retriesLeft > 0 else { return .unavailable }
                return await runLocal(task, digest, retriesLeft: retriesLeft - 1)

            case .retryThenEscalate:
                guard retriesLeft > 0 else { return await runRemote(task, digest) }
                return await runLocal(task, digest, retriesLeft: retriesLeft - 1)

            case .surface:
                return .refused(error.localizedDescription)

            case .programmerError:
                assertionFailure("schema is unusable on-device: \(error)")
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    private func runRemote<T: CoachTask>(
        _ task: T,
        _ digest: MetricsDigest
    ) async -> CoachResult<T.Output> {
        // Until Plan 2 lands there is no remote engine, and that is a real
        // shipping state rather than a stub: the coach works on-device and
        // says so when it cannot reach further.
        guard let remote else { return .unavailable }
        do {
            return .answered(try await remote.run(task, digest))
        } catch {
            return .unavailable
        }
    }

    private func currentAvailability() -> ModelAvailability {
        if let cached = cachedAvailability, cached.isWorthReChecking == false {
            return cached
        }
        let fresh = availability()
        cachedAvailability = fresh
        return fresh
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter CoachRouterTests`

Expected: PASS, 7 tests.

- [ ] **Step 6: Run the whole suite**

Run: `swift test --package-path LifeOSKit`

Expected: PASS. Confirms `Insights` has not broken `Persistence`, `Integrations`, or `DesignSystem`.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Insights/Engines LifeOSKit/Sources/Insights/CoachRouter.swift LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift
git commit -m "feat(insights): run coach tasks on-device, and route their failures

The router is an actor because .concurrentRequests is a real on-device
failure mode; serialising is cheaper than handling it, and the escalation
policy calls that error our bug precisely because this type prevents it.

OnDeviceEngine creates a session per call rather than storing one:
LanguageModelSession is a non-Sendable final class while Engine is
Sendable, and a one-shot brief has no conversation to remember anyway.

With no remote engine wired, escalation resolves to .unavailable. That is
a shipping state, not a stub -- the coach works on-device today and says
so plainly when a task needs more than the device has."
```

---

### Task 7: One brief per day

The largest avoidable cost in the whole system, per spec §10 — without this, the brief regenerates every time Today appears. It is free on-device, but it becomes the dominant line item the moment the tier moves.

**Files:**
- Create: `LifeOSKit/Sources/Insights/BriefCache.swift`
- Test: `LifeOSKit/Tests/InsightsTests/BriefCacheTests.swift`

**Interfaces:**
- Consumes: `DailyBrief`.
- Produces:
  - `public protocol BriefStore: Sendable` — `func load(for date: Date) -> DailyBrief?`, `func save(_ brief: DailyBrief, for date: Date)`
  - `public final class InMemoryBriefStore: BriefStore, @unchecked Sendable` — `public init()`
  - `public struct BriefCache: Sendable` — `public init(store: any BriefStore, calendar: Calendar = .current)`, `public func brief(for date: Date, generate: @Sendable () async -> CoachResult<DailyBrief>) async -> CoachResult<DailyBrief>`

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/InsightsTests/BriefCacheTests.swift`:

```swift
import Testing
import Foundation
@testable import Insights

@Suite struct BriefCacheTests {

    private let brief = DailyBrief(headline: "Fine.", observations: ["a", "b"])
    private let morning = Date(timeIntervalSince1970: 1_770_000_000)

    @Test func theFirstCallGenerates() async {
        let cache = BriefCache(store: InMemoryBriefStore())
        let calls = Counter()

        let result = await cache.brief(for: morning) {
            await calls.increment()
            return .answered(self.brief)
        }

        #expect(result == .answered(brief))
        #expect(await calls.count == 1)
    }

    @Test func aSecondCallOnTheSameDayDoesNotGenerateAgain() async {
        let cache = BriefCache(store: InMemoryBriefStore())
        let calls = Counter()
        let generate: @Sendable () async -> CoachResult<DailyBrief> = {
            await calls.increment()
            return .answered(self.brief)
        }

        _ = await cache.brief(for: morning, generate: generate)
        let second = await cache.brief(for: morning.addingTimeInterval(6 * 3_600), generate: generate)

        #expect(second == .answered(brief))
        #expect(await calls.count == 1)
    }

    @Test func aNewDayGeneratesAgain() async {
        let cache = BriefCache(store: InMemoryBriefStore())
        let calls = Counter()
        let generate: @Sendable () async -> CoachResult<DailyBrief> = {
            await calls.increment()
            return .answered(self.brief)
        }

        _ = await cache.brief(for: morning, generate: generate)
        _ = await cache.brief(for: morning.addingTimeInterval(86_400), generate: generate)

        #expect(await calls.count == 2)
    }

    /// Caching a failure would strand the user without a brief until
    /// midnight, so only a real answer is kept.
    @Test func aFailureIsNotCached() async {
        let cache = BriefCache(store: InMemoryBriefStore())
        let calls = Counter()

        _ = await cache.brief(for: morning) {
            await calls.increment()
            return .unavailable
        }
        let second = await cache.brief(for: morning) {
            await calls.increment()
            return .answered(self.brief)
        }

        #expect(second == .answered(brief))
        #expect(await calls.count == 2)
    }
}

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter BriefCacheTests`

Expected: FAIL — `cannot find 'BriefCache' in scope`.

- [ ] **Step 3: Write the cache**

Create `LifeOSKit/Sources/Insights/BriefCache.swift`:

```swift
import Foundation

public protocol BriefStore: Sendable {
    func load(for date: Date) -> DailyBrief?
    func save(_ brief: DailyBrief, for date: Date)
}

/// Backing for tests and previews. The app substitutes a SwiftData store when
/// the coach screen is built.
public final class InMemoryBriefStore: BriefStore, @unchecked Sendable {
    private let lock = NSLock()
    private var briefs: [Date: DailyBrief] = [:]

    public init() {}

    public func load(for date: Date) -> DailyBrief? {
        lock.withLock { briefs[date] }
    }

    public func save(_ brief: DailyBrief, for date: Date) {
        lock.withLock { briefs[date] = brief }
    }
}

/// One brief per calendar day.
///
/// Without this the brief regenerates every time Today appears, so its cost
/// tracks how often the app is opened rather than how many days have passed.
/// That is free on-device and the single largest line item the moment the
/// tier moves, which is why it is built now rather than when it starts to
/// hurt.
public struct BriefCache: Sendable {

    private let store: any BriefStore
    private let calendar: Calendar

    public init(store: any BriefStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func brief(
        for date: Date,
        generate: @Sendable () async -> CoachResult<DailyBrief>
    ) async -> CoachResult<DailyBrief> {
        let day = calendar.startOfDay(for: date)

        if let cached = store.load(for: day) {
            return .answered(cached)
        }

        let result = await generate()

        // Only a real answer is kept. Caching a refusal or an outage would
        // strand the user without a brief until midnight.
        if case .answered(let brief) = result {
            store.save(brief, for: day)
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter BriefCacheTests`

Expected: PASS, 4 tests.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path LifeOSKit`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Insights/BriefCache.swift LifeOSKit/Tests/InsightsTests/BriefCacheTests.swift
git commit -m "feat(insights): generate the daily brief once a day, not once a view

Without this the brief regenerates every time Today appears, so its cost
tracks how often the app is opened rather than how many days have passed.
That is free while the brief runs on-device and becomes the largest line
item the moment the tier moves, so it is built now rather than when it
starts to hurt.

Only a real answer is cached. Storing a refusal or an outage would strand
the user without a brief until midnight."
```

---

## What this plan deliberately leaves out

| Not here | Where it goes |
|---|---|
| `RemoteEngine`, the Edge Function, the budget schema | Plan 2. `CoachRouter` already takes a `remote:` engine and resolves to `.unavailable` without one. |
| `WeeklyReview`, `MealEstimate` | Plan 2 — both have a `.cloud` floor and cannot run until there is a cloud. |
| The Coach UI | Explicitly out of the spec's scope (§1). `CoachResult` is the seam it will consume. |
| Streaming | Spec §13. Three of four tasks do not want it, and it doubles the `Engine` surface. |
| A SwiftData `BriefStore` | Task 7 ships the protocol and an in-memory conformance; the persistent one belongs with the screen that needs it. |

## Done when

- `swift test --package-path LifeOSKit` passes.
- The daily brief and chat both work on-device with no network and no key.
- `git grep -l "import FoundationModels" LifeOSKit/Sources` lists files under `Sources/Insights/` only.
- Task 1's schema pin passes — or its failure is recorded, which changes Plan 2 before Plan 2 is written.
