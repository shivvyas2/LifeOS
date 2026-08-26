# Calendar Assistant (Phase B, on-device) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The conversational calendar assistant: an on-device chat sheet that answers schedule questions and creates, moves, and deletes events by calling tools, with a structural confirmation gate on destructive writes.

**Architecture:** `CoachTool` (the general tool contract) and a confirmation-gated `ToolInvoker` land in `Insights`; a thin `SessionTool` adapter binds them to FoundationModels, whose `LanguageModelSession` drives tool execution on-device. A new `Assistant` target holds the six calendar tools behind injected `CalendarReading`/`CalendarWriting` protocols so every tool is testable with fakes. `ChatMessage` persistence lands in `Persistence`. The app gains `AssistantSheet` presented from the Today surface.

**Tech Stack:** Swift 6, SwiftData, FoundationModels (`LanguageModelSession`, `Tool`, `GenerationSchema`, `@Generable`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-25-calendar-and-assistant-design.md` (Sections 4, 5, 8, 9, 10, 11, 13.2, 15 Phase B, 16). Phase A (calendar core) is merged. Phases C and D remain out of scope.

**Scope ruling (recorded here because the spec predates reality):** the coach's REMOTE engine and `coach` Edge Function do not exist yet (`CoachRouter` ships with `remote: nil`; the coach plan defers the proxy to its Plan 2). Phase B therefore ships **on-device only**, which is the spec's own floor and its dominant path. Consequences, each deliberate:
- No change to `supabase/functions/` (spec S7.1's second request shape lands with the coach proxy, not before).
- The loop is the spec's ON-DEVICE binding (S8.1's table): FoundationModels calls tools itself, so the round loop, cap, and confirmation gate live in the tool adapter layer, not in an OpenAI-style message loop. The provider-neutral wire loop arrives with the remote engine.
- The S14 "content leaves the device on escalation" disclosure is moot until a remote engine exists; on these turns nothing ever leaves the device.
- Spec S13.1's undo affordance on created events is deferred: `CalendarWriting.create` returns no id today. Deferred, not dropped.

## Global Constraints

- Platforms `.iOS("26.0")`, `.macOS("26.0")`; every new file compiles for both (`swift test` runs on macOS).
- Swift Testing (`@Suite`, `#expect`), never XCTest. All tests run under `swift test` with no simulator, no network, and NO live language model — anything needing `LanguageModelSession.respond` is untestable by design and stays a thin shim.
- Tool invocation cap per user turn: **6**. Conversation history cap: **20** messages.
- Gated tools (`update_event`, `delete_event`) are structurally unexecutable without confirmation: the only code path that runs a gated tool's `call` sits behind the broker's decision. Cancel yields the exact result string `"User declined this change."` so the model can acknowledge.
- A failing tool returns its error as a result string, never drops it. An unknown event id is rejected, never dispatched. A recurring event (`isRecurring == true`) is refused by update/delete with an explaining message.
- Ids the model sees are local `CalendarEvent.id` UUIDs handed out by `get_events`; never provider ids.
- `Insights` stays calendar-blind: it may not import `Integrations` or name any calendar type. Calendar knowledge lives in the new `Assistant` target (deps: `Insights`, `Persistence`).
- Module deps: `Assistant` depends on `Insights` and `Persistence` only. App-level wiring (CalendarSync conformance, EventKit) happens in the app target.
- FoundationModels API adaptation rule: if the compiler rejects an exact construct written here (initializer labels, protocol requirements), make the smallest change that preserves the stated interface and behavior, and record the deviation.
- Commits: conventional, no em dashes, no trailers. Branch work only, never on main.

---

### Task 1: ChatMessage model and ChatStore

**Files:**
- Create: `LifeOSKit/Sources/Persistence/ChatMessage.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift` (schema array)
- Test: `LifeOSKit/Tests/PersistenceTests/ChatStoreTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ChatRole` (`.user`, `.assistant`), `ChatMessage` (`@Model`), `ChatMessageSnapshot` (`Equatable, Identifiable, Sendable`), `ChatStore` (`@MainActor` struct): `init(context: ModelContext)`, `append(conversationID: UUID, role: ChatRole, text: String, toolSummaries: [String] = []) throws -> ChatMessageSnapshot` (`@discardableResult`), `recent(conversationID: UUID, limit: Int = 20) throws -> [ChatMessageSnapshot]` (oldest-first, most recent `limit`), `latestConversationID() throws -> UUID?`. Task 6 consumes all of it.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/PersistenceTests/ChatStoreTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct ChatStoreTests {
    private func makeStore() throws -> ChatStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return ChatStore(context: ModelContext(container))
    }

    @Test func recentReturnsOldestFirstAndCapsAtTheLimit() throws {
        let store = try makeStore()
        let conversation = UUID()
        let base = Date(timeIntervalSince1970: 1_756_209_600)
        for index in 0..<25 {
            try store.append(
                conversationID: conversation, role: .user, text: "m\(index)",
                at: base.addingTimeInterval(Double(index))
            )
        }

        let recent = try store.recent(conversationID: conversation, limit: 20)
        #expect(recent.count == 20)
        #expect(recent.first?.text == "m5")
        #expect(recent.last?.text == "m24")
    }

    @Test func conversationsDoNotBleedIntoEachOther() throws {
        let store = try makeStore()
        let mine = UUID()
        try store.append(conversationID: mine, role: .user, text: "mine")
        try store.append(conversationID: UUID(), role: .user, text: "theirs")

        #expect(try store.recent(conversationID: mine).map(\.text) == ["mine"])
    }

    @Test func toolSummariesRoundTrip() throws {
        let store = try makeStore()
        let conversation = UUID()
        try store.append(
            conversationID: conversation, role: .assistant,
            text: "Done", toolSummaries: ["Checked your calendar", "Created an event"]
        )

        let saved = try store.recent(conversationID: conversation)
        #expect(saved[0].toolSummaries == ["Checked your calendar", "Created an event"])
        #expect(saved[0].role == .assistant)
    }

    @Test func latestConversationIsTheMostRecentlyWrittenOne() throws {
        let store = try makeStore()
        let older = UUID()
        let newer = UUID()
        try store.append(conversationID: older, role: .user, text: "a")
        try store.append(conversationID: newer, role: .user, text: "b")

        #expect(try store.latestConversationID() == newer)
    }

    @Test func anEmptyStoreHasNoLatestConversation() throws {
        let store = try makeStore()
        #expect(try store.latestConversationID() == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter ChatStoreTests`
Expected: FAIL to compile with "cannot find 'ChatStore' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Persistence/ChatMessage.swift
import Foundation
import SwiftData

public enum ChatRole: String, Codable, Sendable {
    case user, assistant
}

/// Detached value form, safe to hand to a view.
public struct ChatMessageSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let role: ChatRole
    public let text: String
    /// Rendered as activity chips. Empty for plain replies.
    public let toolSummaries: [String]
    public let createdAt: Date

    public init(
        id: UUID, conversationID: UUID, role: ChatRole,
        text: String, toolSummaries: [String], createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.toolSummaries = toolSummaries
        self.createdAt = createdAt
    }
}

@Model
public final class ChatMessage {
    public var id: UUID
    public var conversationID: UUID
    /// Stored raw so the enum can gain cases without a migration.
    public var roleRaw: String
    public var text: String
    public var toolSummaries: [String]
    public var createdAt: Date

    public init(conversationID: UUID, role: ChatRole, text: String,
                toolSummaries: [String] = [], createdAt: Date = .now) {
        self.id = UUID()
        self.conversationID = conversationID
        self.roleRaw = role.rawValue
        self.text = text
        self.toolSummaries = toolSummaries
        self.createdAt = createdAt
    }

    public var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    public func snapshot() -> ChatMessageSnapshot {
        ChatMessageSnapshot(
            id: id, conversationID: conversationID, role: role,
            text: text, toolSummaries: toolSummaries, createdAt: createdAt
        )
    }
}

/// Conversation persistence. Local only: chat history never leaves the device.
@MainActor
public struct ChatStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// `at` exists for tests: appends in a tight loop can share a wall-clock
    /// timestamp, and the recency ordering must not be flaky over ties.
    @discardableResult
    public func append(
        conversationID: UUID, role: ChatRole, text: String,
        toolSummaries: [String] = [], at date: Date = .now
    ) throws -> ChatMessageSnapshot {
        let message = ChatMessage(
            conversationID: conversationID, role: role,
            text: text, toolSummaries: toolSummaries, createdAt: date
        )
        context.insert(message)
        try context.save()
        return message.snapshot()
    }

    /// The last `limit` messages of one conversation, oldest first, which is
    /// the order both a transcript render and a prompt want.
    public func recent(conversationID: UUID, limit: Int = 20) throws -> [ChatMessageSnapshot] {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).reversed().map { $0.snapshot() }
    }

    public func latestConversationID() throws -> UUID? {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.conversationID
    }
}
```

In `LifeOSContainer.swift`, add one line to the schema array after `CalendarEvent.self`:

```swift
        ChatMessage.self,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter ChatStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/ChatMessage.swift LifeOSKit/Sources/Persistence/LifeOSContainer.swift LifeOSKit/Tests/PersistenceTests/ChatStoreTests.swift
git commit -m "feat(assistant): persist chat conversations locally"
```

---

### Task 2: The CoachTool contract and the schema pin

**Files:**
- Create: `LifeOSKit/Sources/Insights/CoachTool.swift`
- Test: `LifeOSKit/Tests/InsightsTests/CoachToolTests.swift`

**Interfaces:**
- Consumes: FoundationModels (`GenerationSchema`, `GeneratedContent`).
- Produces: `CoachTool` protocol exactly as below. Tasks 3-5 build on it; the coach adopts it later at no cost (spec S8.1).

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/InsightsTests/CoachToolTests.swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable
private struct ProbeArguments {
    @Guide(description: "Any short string")
    var value: String
}

private struct ProbeTool: CoachTool {
    let name = "probe"
    let description = "A probe"
    var parameters: GenerationSchema { ProbeArguments.generationSchema }
    func call(_ arguments: GeneratedContent) async throws -> String { "ok" }
}

@Suite struct CoachToolTests {
    /// Pins the schema-sharing assumption: `GenerationSchema` is Codable, so
    /// one declaration can serve the on-device binding today and a remote
    /// `tools[]` payload later. If an OS update breaks this, Phase B's remote
    /// story changes and this test says so first.
    @Test func toolParametersRoundTripThroughJSON() throws {
        let encoded = try JSONEncoder().encode(ProbeTool().parameters)
        #expect(!encoded.isEmpty)
        let decoded = try JSONDecoder().decode(GenerationSchema.self, from: encoded)
        _ = decoded
    }

    @Test func confirmationAndSummaryHaveSafeDefaults() async {
        let tool = ProbeTool()
        #expect(tool.requiresConfirmation == false)
        #expect(tool.summary("x".generatedContent) == "probe")
        #expect(await tool.confirmationPreview("x".generatedContent) == ["probe"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CoachToolTests`
Expected: FAIL to compile with "cannot find type 'CoachTool' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Insights/CoachTool.swift
import Foundation
import FoundationModels

/// A capability the model can invoke. General, not calendar-specific: the
/// contract lives here so the coach can adopt tools later without a new seam.
///
/// `parameters` is a `GenerationSchema`, which is Codable: the same
/// declaration binds to `LanguageModelSession` on-device today and will
/// serialize into a remote `tools[]` payload when a remote engine exists.
public protocol CoachTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: GenerationSchema { get }
    /// True for tools the invoker must not execute without confirmation.
    var requiresConfirmation: Bool { get }
    /// One short line for the activity chip shown after execution.
    func summary(_ arguments: GeneratedContent) -> String
    /// Lines the confirmation card renders before a gated call may run.
    /// Async so an implementation can read current state for a before/after.
    func confirmationPreview(_ arguments: GeneratedContent) async -> [String]
    func call(_ arguments: GeneratedContent) async throws -> String
}

public extension CoachTool {
    var requiresConfirmation: Bool { false }
    func summary(_ arguments: GeneratedContent) -> String { name }
    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] { [name] }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CoachToolTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/CoachTool.swift LifeOSKit/Tests/InsightsTests/CoachToolTests.swift
git commit -m "feat(assistant): add the CoachTool contract and pin its Codable schema"
```

---

### Task 3: The confirmation gate and the tool invoker

**Files:**
- Create: `LifeOSKit/Sources/Insights/ToolGate.swift`
- Create: `LifeOSKit/Sources/Insights/ToolInvoker.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ToolInvokerTests.swift`

**Interfaces:**
- Consumes: `CoachTool` (Task 2).
- Produces: `PendingWrite` (`Identifiable, Sendable, Equatable`: `id: UUID`, `toolName: String`, `preview: [String]`), `ConfirmationBroker` (actor: `init(onPending:)`, `confirm(_ id: UUID)`, `cancel(_ id: UUID)`, `pendingWrites() -> [PendingWrite]`), `ToolInvoker` (actor: `init(tools: [any CoachTool], broker: ConfirmationBroker)`, `invoke(name: String, arguments: GeneratedContent) async -> String`, `toolSummaries() -> [String]`, `static invocationLimit = 6`). Task 4 binds these to FoundationModels; Task 6's view model calls confirm/cancel.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/InsightsTests/ToolInvokerTests.swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

/// Records calls; scriptable result. All access from the test's actor context.
private final class SpyTool: CoachTool, @unchecked Sendable {
    let name: String
    let description = "spy"
    let requiresConfirmation: Bool
    var result: Result<String, Error> = .success("done")
    private(set) var callCount = 0

    init(name: String, gated: Bool = false) {
        self.name = name
        self.requiresConfirmation = gated
    }

    var parameters: GenerationSchema { EmptyArguments.generationSchema }
    func summary(_ arguments: GeneratedContent) -> String { "ran \(name)" }
    func call(_ arguments: GeneratedContent) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

@Generable
private struct EmptyArguments {}

private struct Boom: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@Suite struct ToolInvokerTests {
    private var noArguments: GeneratedContent { "x".generatedContent }

    @Test func anUngatedToolExecutesAndRecordsItsSummary() async {
        let tool = SpyTool(name: "read")
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        let result = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(result == "done")
        #expect(tool.callCount == 1)
        #expect(await invoker.toolSummaries() == ["ran read"])
    }

    @Test func theSeventhInvocationIsRefused() async {
        let tool = SpyTool(name: "read")
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        for _ in 0..<ToolInvoker.invocationLimit {
            _ = await invoker.invoke(name: "read", arguments: noArguments)
        }
        let refused = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(refused.contains("could not be completed"))
        #expect(tool.callCount == ToolInvoker.invocationLimit)
    }

    @Test func aThrowingToolReturnsItsErrorAsTheResult() async {
        let tool = SpyTool(name: "read")
        tool.result = .failure(Boom())
        let invoker = ToolInvoker(tools: [tool], broker: ConfirmationBroker())

        let result = await invoker.invoke(name: "read", arguments: noArguments)

        #expect(result.contains("boom"))
        #expect(await invoker.toolSummaries().isEmpty)
    }

    @Test func anUnknownToolNameIsAnErrorResultNotACrash() async {
        let invoker = ToolInvoker(tools: [], broker: ConfirmationBroker())
        let result = await invoker.invoke(name: "ghost", arguments: noArguments)
        #expect(result.contains("ghost"))
    }

    @Test func aGatedToolDoesNotExecuteUntilConfirmed() async throws {
        let tool = SpyTool(name: "write", gated: true)
        let broker = ConfirmationBroker()
        let invoker = ToolInvoker(tools: [tool], broker: broker)

        let turn = Task { await invoker.invoke(name: "write", arguments: noArguments) }
        let pending = try await firstPendingWrite(on: broker)
        #expect(tool.callCount == 0)
        #expect(pending.toolName == "write")

        await broker.confirm(pending.id)
        let result = await turn.value

        #expect(result == "done")
        #expect(tool.callCount == 1)
    }

    @Test func cancellingAGatedToolYieldsTheDeclinedResult() async throws {
        let tool = SpyTool(name: "write", gated: true)
        let broker = ConfirmationBroker()
        let invoker = ToolInvoker(tools: [tool], broker: broker)

        let turn = Task { await invoker.invoke(name: "write", arguments: noArguments) }
        let pending = try await firstPendingWrite(on: broker)
        await broker.cancel(pending.id)
        let result = await turn.value

        #expect(result == "User declined this change.")
        #expect(tool.callCount == 0)
        #expect(await invoker.toolSummaries().isEmpty)
    }

    /// Polls until the broker holds a pending write. The suspension inside
    /// `decision(for:)` is the structural gate under test, so the test must
    /// meet it from the outside exactly as the UI would.
    private func firstPendingWrite(on broker: ConfirmationBroker) async throws -> PendingWrite {
        for _ in 0..<200 {
            if let pending = await broker.pendingWrites().first { return pending }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Boom()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter ToolInvokerTests`
Expected: FAIL to compile with "cannot find 'ToolInvoker' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Insights/ToolGate.swift
import Foundation

/// A gated tool call waiting on the user. Carries what the card renders;
/// the call itself stays inside the invoker, where nothing the model emits
/// can reach it.
public struct PendingWrite: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let toolName: String
    public let preview: [String]

    public init(id: UUID = UUID(), toolName: String, preview: [String]) {
        self.id = id
        self.toolName = toolName
        self.preview = preview
    }
}

/// The structural confirmation gate. `decision(for:)` suspends the tool's
/// execution path until the UI resolves it; there is no other way a gated
/// call proceeds, which is what makes the gate a property of the code rather
/// than a request in the prompt.
public actor ConfirmationBroker {
    private var pending: [PendingWrite] = []
    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private let onPending: @Sendable (PendingWrite) -> Void

    public init(onPending: @escaping @Sendable (PendingWrite) -> Void = { _ in }) {
        self.onPending = onPending
    }

    public func pendingWrites() -> [PendingWrite] { pending }

    func decision(for write: PendingWrite) async -> Bool {
        pending.append(write)
        onPending(write)
        return await withCheckedContinuation { continuation in
            continuations[write.id] = continuation
        }
    }

    public func confirm(_ id: UUID) { resolve(id, allowed: true) }
    public func cancel(_ id: UUID) { resolve(id, allowed: false) }

    private func resolve(_ id: UUID, allowed: Bool) {
        pending.removeAll { $0.id == id }
        continuations.removeValue(forKey: id)?.resume(returning: allowed)
    }
}
```

```swift
// LifeOSKit/Sources/Insights/ToolInvoker.swift
import Foundation
import FoundationModels

/// Executes tool calls on the model's behalf: enforces the per-turn cap,
/// holds gated calls at the broker, turns failures into result strings the
/// model can recover from, and records chips for the UI.
///
/// One invoker per user turn; the cap and the summaries are turn state.
public actor ToolInvoker {
    public static let invocationLimit = 6

    private let toolsByName: [String: any CoachTool]
    private let broker: ConfirmationBroker
    private var invocations = 0
    private var summaries: [String] = []

    public init(tools: [any CoachTool], broker: ConfirmationBroker) {
        self.toolsByName = Dictionary(
            tools.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.broker = broker
    }

    public func toolSummaries() -> [String] { summaries }

    public func invoke(name: String, arguments: GeneratedContent) async -> String {
        guard let tool = toolsByName[name] else {
            return "No tool named \(name) is available."
        }
        guard invocations < Self.invocationLimit else {
            return "The tool limit for this request was reached. Tell the user the request could not be completed."
        }
        invocations += 1

        if tool.requiresConfirmation {
            let write = PendingWrite(
                toolName: tool.name,
                preview: await tool.confirmationPreview(arguments)
            )
            guard await broker.decision(for: write) else {
                return "User declined this change."
            }
        }

        do {
            let result = try await tool.call(arguments)
            summaries.append(tool.summary(arguments))
            return result
        } catch {
            return "The \(name) tool failed: \(error.localizedDescription). Recover or explain what happened."
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter ToolInvokerTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/ToolGate.swift LifeOSKit/Sources/Insights/ToolInvoker.swift LifeOSKit/Tests/InsightsTests/ToolInvokerTests.swift
git commit -m "feat(assistant): gate and cap tool execution behind a confirmation broker"
```

---

### Task 4: The FoundationModels binding

**Files:**
- Create: `LifeOSKit/Sources/Insights/Engines/SessionTool.swift`
- Create: `LifeOSKit/Sources/Insights/AssistantTurn.swift`

**Interfaces:**
- Consumes: `CoachTool`, `ToolInvoker`, `ConfirmationBroker` (Tasks 2-3).
- Produces: `AssistantTurn.Reply` (`text: String`, `toolSummaries: [String]`) and `AssistantTurn.run(instructions: String, prompt: String, tools: [any CoachTool], broker: ConfirmationBroker) async throws -> Reply`. Task 6's view model calls it.

No unit tests: `AssistantTurn.run` needs a live `LanguageModelSession`, which CI does not have; every piece of logic it composes was tested in Task 3, and `SessionTool` is a two-line delegation. This mirrors `EventKitSource` in Phase A. Verification is the full suite (compilation on both platforms) plus the Task 6 app run.

- [ ] **Step 1: Write the implementation**

```swift
// LifeOSKit/Sources/Insights/Engines/SessionTool.swift
import FoundationModels

/// Binds one `CoachTool` into a `LanguageModelSession`. The session drives
/// `call`; everything of substance (gating, cap, error shaping) happens in
/// the shared invoker so it is identical for every tool and testable without
/// a model.
struct SessionTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    private let invoker: ToolInvoker

    init(_ tool: any CoachTool, invoker: ToolInvoker) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.invoker = invoker
    }

    func call(arguments: GeneratedContent) async throws -> String {
        await invoker.invoke(name: name, arguments: arguments)
    }
}
```

```swift
// LifeOSKit/Sources/Insights/AssistantTurn.swift
import FoundationModels

/// One user turn of the tool-calling assistant, on-device.
///
/// A session is created per turn: the conversation's memory lives in the
/// prompt (rendered from the capped history), not in the session, so a turn
/// is stateless here the way `OnDeviceEngine` is for one-shot tasks. When a
/// remote engine exists this type grows a provider-neutral loop against
/// `Engine`; today FoundationModels drives the rounds itself.
public enum AssistantTurn {
    public struct Reply: Sendable, Equatable {
        public let text: String
        public let toolSummaries: [String]

        public init(text: String, toolSummaries: [String]) {
            self.text = text
            self.toolSummaries = toolSummaries
        }
    }

    public static func run(
        instructions: String,
        prompt: String,
        tools: [any CoachTool],
        broker: ConfirmationBroker
    ) async throws -> Reply {
        let invoker = ToolInvoker(tools: tools, broker: broker)
        let session = LanguageModelSession(
            tools: tools.map { SessionTool($0, invoker: invoker) },
            instructions: instructions
        )
        let response = try await session.respond(to: prompt)
        return Reply(
            text: response.content,
            toolSummaries: await invoker.toolSummaries()
        )
    }
}
```

- [ ] **Step 2: Verify the whole kit still compiles and passes**

Run: `cd LifeOSKit && swift test`
Expected: PASS, same totals as before this task plus nothing broken.

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/Insights/Engines/SessionTool.swift LifeOSKit/Sources/Insights/AssistantTurn.swift
git commit -m "feat(assistant): bind coach tools into an on-device session turn"
```

---

### Task 5: The Assistant target and the six calendar tools

**Files:**
- Modify: `LifeOSKit/Package.swift` (new library, target, test target)
- Create: `LifeOSKit/Sources/Assistant/CalendarAccess.swift`
- Create: `LifeOSKit/Sources/Assistant/ToolDates.swift`
- Create: `LifeOSKit/Sources/Assistant/CalendarTools.swift`
- Create: `LifeOSKit/Sources/Assistant/AssistantContext.swift`
- Test: `LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift`
- Test: `LifeOSKit/Tests/AssistantTests/AssistantContextTests.swift`

**Interfaces:**
- Consumes: `CoachTool`, `PendingWrite` defaults (Task 2); `CalendarEventSnapshot`, `CalendarEventDraft`, `CalendarStore` (Phase A).
- Produces:
  - `CalendarReading` (`@MainActor` protocol: `events(from:to:) throws -> [CalendarEventSnapshot]`, `snapshot(id:) throws -> CalendarEventSnapshot?`, `freeSlots(from:to:durationMinutes:) throws -> [DateInterval]`) with `extension CalendarStore: CalendarReading {}`.
  - `CalendarWriting` (protocol: `create(_ draft: CalendarEventDraft) async throws`, `update(id: UUID, with: CalendarEventDraft) async throws`, `delete(id: UUID) async throws`) — Task 6 conforms `CalendarSync` to it in the app.
  - `CalendarAssistant.tools(reading: any CalendarReading, writing: any CalendarWriting) -> [any CoachTool]` (the six tools), `CalendarAssistant.instructions(authorized: Bool) -> String`, `CalendarAssistant.contextPrefix(now: Date, timeZone: TimeZone, today: [CalendarEventSnapshot], tomorrow: [CalendarEventSnapshot]) -> String`.

Package.swift additions, verbatim:

```swift
        .library(name: "Assistant", targets: ["Assistant"]),
```
(in `products`, after the `Sectors` line), and in `targets`:
```swift
        .target(name: "Assistant", dependencies: ["Insights", "Persistence"]),
        .testTarget(name: "AssistantTests", dependencies: ["Assistant"]),
```

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift
import Testing
import Foundation
import FoundationModels
import Persistence
@testable import Assistant

@MainActor
private final class FakeCalendar: CalendarReading, CalendarWriting, @unchecked Sendable {
    var stored: [CalendarEventSnapshot] = []
    var slots: [DateInterval] = []
    private(set) var created: [CalendarEventDraft] = []
    private(set) var updated: [(id: UUID, draft: CalendarEventDraft)] = []
    private(set) var deleted: [UUID] = []

    nonisolated init() {}

    func events(from: Date, to: Date) throws -> [CalendarEventSnapshot] {
        stored.filter { $0.startDate < to && $0.endDate > from }
    }
    func snapshot(id: UUID) throws -> CalendarEventSnapshot? {
        stored.first { $0.id == id }
    }
    func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval] {
        slots
    }
    nonisolated func create(_ draft: CalendarEventDraft) async throws {
        await MainActor.run { created.append(draft) }
    }
    nonisolated func update(id: UUID, with draft: CalendarEventDraft) async throws {
        await MainActor.run { updated.append((id, draft)) }
    }
    nonisolated func delete(id: UUID) async throws {
        await MainActor.run { deleted.append(id) }
    }
}

@Suite @MainActor struct CalendarToolsTests {
    private let noon = Date(timeIntervalSince1970: 1_756_209_600)

    private func event(_ title: String, id: UUID = UUID(), recurring: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: .eventKit, sourceID: "ek-\(title)",
            calendarTitle: "Cal", title: title,
            startDate: noon, endDate: noon.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: recurring, location: nil, notes: nil
        )
    }

    private func tool(named name: String, on fake: FakeCalendar) throws -> any CoachTool {
        let tools = CalendarAssistant.tools(reading: fake, writing: fake)
        return try #require(tools.first { $0.name == name })
    }

    private func arguments(_ pairs: [String: String]) -> GeneratedContent {
        GeneratedContent(properties: pairs.mapValues { $0 as any ConvertibleToGeneratedContent })
    }

    @Test func thereAreSixToolsAndOnlyWritesAreGated() throws {
        let fake = FakeCalendar()
        let tools = CalendarAssistant.tools(reading: fake, writing: fake)
        #expect(tools.map(\.name).sorted() == [
            "analyze_schedule", "create_event", "delete_event",
            "find_free_time", "get_events", "update_event",
        ])
        #expect(tools.filter(\.requiresConfirmation).map(\.name).sorted() == ["delete_event", "update_event"])
    }

    @Test func getEventsReturnsIDsAndTitlesInTheRange() async throws {
        let fake = FakeCalendar()
        let mine = event("Standup")
        fake.stored = [mine]
        let result = try await tool(named: "get_events", on: fake).call(arguments([
            "start": "2026-08-26T00:00:00Z", "end": "2026-08-27T00:00:00Z",
        ]))
        #expect(result.contains("Standup"))
        #expect(result.contains(mine.id.uuidString))
    }

    @Test func aGarbledDateIsAThrownErrorNotACrash() async throws {
        let fake = FakeCalendar()
        await #expect(throws: (any Error).self) {
            _ = try await tool(named: "get_events", on: fake).call(arguments([
                "start": "yesterday-ish", "end": "2026-08-27T00:00:00Z",
            ]))
        }
    }

    @Test func findFreeTimeReportsTheSlots() async throws {
        let fake = FakeCalendar()
        fake.slots = [DateInterval(start: noon, duration: 3_600)]
        let result = try await tool(named: "find_free_time", on: fake).call(arguments([
            "start": "2026-08-26T00:00:00Z", "end": "2026-08-27T00:00:00Z",
            "durationMinutes": "30",
        ]))
        #expect(result.contains("free"))
    }

    @Test func createEventMapsItsArgumentsOntoTheDraft() async throws {
        let fake = FakeCalendar()
        _ = try await tool(named: "create_event", on: fake).call(arguments([
            "title": "Dentist", "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "12 Main St", "notes": "",
        ]))
        #expect(fake.created.count == 1)
        #expect(fake.created[0].title == "Dentist")
        #expect(fake.created[0].location == "12 Main St")
        #expect(fake.created[0].notes == nil)
    }

    @Test func updateRejectsAnUnknownID() async throws {
        let fake = FakeCalendar()
        let result = try await tool(named: "update_event", on: fake).call(arguments([
            "id": UUID().uuidString, "title": "X",
            "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        #expect(result.contains("No event"))
        #expect(fake.updated.isEmpty)
    }

    @Test func writesToARecurringEventAreRefusedWithAnExplanation() async throws {
        let fake = FakeCalendar()
        let series = event("Standup", recurring: true)
        fake.stored = [series]

        let update = try await tool(named: "update_event", on: fake).call(arguments([
            "id": series.id.uuidString, "title": "Standup",
            "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        let delete = try await tool(named: "delete_event", on: fake).call(arguments([
            "id": series.id.uuidString,
        ]))

        #expect(update.contains("recurring"))
        #expect(delete.contains("recurring"))
        #expect(fake.updated.isEmpty)
        #expect(fake.deleted.isEmpty)
    }

    @Test func deleteDispatchesForAKnownOneOffEvent() async throws {
        let fake = FakeCalendar()
        let mine = event("Old plan")
        fake.stored = [mine]
        _ = try await tool(named: "delete_event", on: fake).call(arguments([
            "id": mine.id.uuidString,
        ]))
        #expect(fake.deleted == [mine.id])
    }

    @Test func confirmationPreviewShowsTheCurrentEvent() async throws {
        let fake = FakeCalendar()
        let mine = event("Gym")
        fake.stored = [mine]
        let preview = await tool(named: "delete_event", on: fake).confirmationPreview(arguments([
            "id": mine.id.uuidString,
        ]))
        #expect(preview.joined(separator: "\n").contains("Gym"))
    }
}
```

```swift
// LifeOSKit/Tests/AssistantTests/AssistantContextTests.swift
import Testing
import Foundation
import Persistence
@testable import Assistant

@Suite struct AssistantContextTests {
    private let noon = Date(timeIntervalSince1970: 1_756_209_600)

    @Test func unauthorizedInstructionsSayThereAreNoCalendarTools() {
        let text = CalendarAssistant.instructions(authorized: false)
        #expect(text.contains("no calendar"))
    }

    @Test func theContextPrefixInlinesTodayAndTomorrow() {
        let event = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-1",
            calendarTitle: "Cal", title: "Standup",
            startDate: noon, endDate: noon.addingTimeInterval(1_800),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
        let prefix = CalendarAssistant.contextPrefix(
            now: noon, timeZone: TimeZone(identifier: "UTC")!,
            today: [event], tomorrow: []
        )
        #expect(prefix.contains("Standup"))
        #expect(prefix.contains("Tomorrow: nothing scheduled"))
        #expect(prefix.contains("UTC"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter CalendarToolsTests`
Expected: FAIL to compile (no `Assistant` target yet). Add the Package.swift changes FIRST if the failure is "no such module", then re-run to get the real "cannot find CalendarAssistant" failure.

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Assistant/CalendarAccess.swift
import Foundation
import Persistence

/// What the tools may read. MainActor because the store's ModelContext is;
/// tools hop to it per call.
@MainActor
public protocol CalendarReading: Sendable {
    func events(from: Date, to: Date) throws -> [CalendarEventSnapshot]
    func snapshot(id: UUID) throws -> CalendarEventSnapshot?
    func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval]
}

extension CalendarStore: CalendarReading {}

/// The only calendar mutation surface the tools can reach. The app satisfies
/// it with CalendarSync, so every write goes through the provider and a
/// re-sync, exactly like a tap in the UI would.
public protocol CalendarWriting: Sendable {
    func create(_ draft: CalendarEventDraft) async throws
    func update(id: UUID, with draft: CalendarEventDraft) async throws
    func delete(id: UUID) async throws
}
```

```swift
// LifeOSKit/Sources/Assistant/ToolDates.swift
import Foundation

enum ToolDateError: Error, LocalizedError {
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .unparseable(let raw):
            "\(raw) is not an ISO-8601 date. Use e.g. 2026-08-26T09:00:00Z."
        }
    }
}

enum ToolDates {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) throws -> Date {
        guard let date = formatter.date(from: raw) else {
            throw ToolDateError.unparseable(raw)
        }
        return date
    }

    static func render(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE MMM d HH:mm"
        return formatter.string(from: date)
    }
}
```

```swift
// LifeOSKit/Sources/Assistant/CalendarTools.swift
import Foundation
import FoundationModels
import Insights
import Persistence

@Generable
struct RangeArguments {
    @Guide(description: "ISO-8601 range start, e.g. 2026-08-26T00:00:00Z")
    var start: String
    @Guide(description: "ISO-8601 range end")
    var end: String
}

@Generable
struct FreeTimeArguments {
    @Guide(description: "ISO-8601 range start")
    var start: String
    @Guide(description: "ISO-8601 range end")
    var end: String
    @Guide(description: "Minimum slot length in minutes")
    var durationMinutes: Int
}

@Generable
struct EventDraftArguments {
    @Guide(description: "Event title")
    var title: String
    @Guide(description: "ISO-8601 start")
    var start: String
    @Guide(description: "ISO-8601 end")
    var end: String
    @Guide(description: "true only for all-day events")
    var isAllDay: Bool
    @Guide(description: "Location, or empty when there is none")
    var location: String
    @Guide(description: "Notes, or empty when there are none")
    var notes: String
}

@Generable
struct UpdateArguments {
    @Guide(description: "The event id exactly as get_events reported it")
    var id: String
    @Guide(description: "Event title")
    var title: String
    @Guide(description: "ISO-8601 start")
    var start: String
    @Guide(description: "ISO-8601 end")
    var end: String
    @Guide(description: "true only for all-day events")
    var isAllDay: Bool
    @Guide(description: "Location, or empty when there is none")
    var location: String
    @Guide(description: "Notes, or empty when there are none")
    var notes: String
}

@Generable
struct DeleteArguments {
    @Guide(description: "The event id exactly as get_events reported it")
    var id: String
}

/// Renders one event the way every tool result and the inline context do,
/// id first so the model can only reference ids it has actually seen.
func eventLine(_ event: CalendarEventSnapshot, timeZone: TimeZone = .current) -> String {
    let start = ToolDates.render(event.startDate, timeZone: timeZone)
    let end = ToolDates.render(event.endDate, timeZone: timeZone)
    let span = event.isAllDay ? "all day" : "\(start) to \(end)"
    return "\(event.id.uuidString) | \(span) | \(event.title)"
}

struct GetEventsTool: CoachTool {
    let reading: any CalendarReading
    let name = "get_events"
    let description = "List calendar events in a date range, with their ids."
    var parameters: GenerationSchema { RangeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Checked your calendar" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try RangeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let events = try await reading.events(from: from, to: to)
        guard !events.isEmpty else { return "No events in that range." }
        return events.map { eventLine($0) }.joined(separator: "\n")
    }
}

struct FindFreeTimeTool: CoachTool {
    let reading: any CalendarReading
    let name = "find_free_time"
    let description = "Find open slots of at least a given length in a date range."
    var parameters: GenerationSchema { FreeTimeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Looked for free time" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try FreeTimeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let slots = try await reading.freeSlots(from: from, to: to, durationMinutes: args.durationMinutes)
        guard !slots.isEmpty else { return "No free slots of that length in the range." }
        let lines = slots.map { slot in
            "free \(ToolDates.render(slot.start, timeZone: .current)) to \(ToolDates.render(slot.end, timeZone: .current))"
        }
        return lines.joined(separator: "\n")
    }
}

struct AnalyzeScheduleTool: CoachTool {
    let reading: any CalendarReading
    let name = "analyze_schedule"
    let description = "Summarize how busy a date range is: event count and busy hours."
    var parameters: GenerationSchema { RangeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Analyzed your schedule" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try RangeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let events = try await reading.events(from: from, to: to)
        let timed = events.filter { !$0.isAllDay }
        let busySeconds = timed.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let busyHours = Int((busySeconds / 3_600).rounded())
        return "\(events.count) events, \(timed.count) with times, about \(busyHours) busy hours."
    }
}

struct CreateEventTool: CoachTool {
    let writing: any CalendarWriting
    let name = "create_event"
    let description = "Create a calendar event."
    var parameters: GenerationSchema { EventDraftArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Created an event" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try EventDraftArguments(arguments)
        let draft = CalendarEventDraft(
            title: args.title,
            startDate: try ToolDates.parse(args.start),
            endDate: try ToolDates.parse(args.end),
            isAllDay: args.isAllDay,
            location: args.location.isEmpty ? nil : args.location,
            notes: args.notes.isEmpty ? nil : args.notes
        )
        try await writing.create(draft)
        return "Created \"\(args.title)\"."
    }
}

struct UpdateEventTool: CoachTool {
    let reading: any CalendarReading
    let writing: any CalendarWriting
    let name = "update_event"
    let description = "Change an existing event's title, time, or details. Requires user confirmation."
    let requiresConfirmation = true
    var parameters: GenerationSchema { UpdateArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Updated an event" }

    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] {
        guard let args = try? UpdateArguments(arguments),
              let id = UUID(uuidString: args.id),
              let current = try? await reading.snapshot(id: id)
        else { return ["Update an event"] }
        return [
            "Now: \(eventLine(current))",
            "Becomes: \(args.title), \(args.start) to \(args.end)",
        ]
    }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try UpdateArguments(arguments)
        guard let id = UUID(uuidString: args.id),
              let current = try await reading.snapshot(id: id) else {
            return "No event with that id. Use ids exactly as get_events reported them."
        }
        if current.isRecurring {
            return "That event is part of a recurring series, which I can't edit. Ask the user to change the series in their calendar app."
        }
        let draft = CalendarEventDraft(
            title: args.title,
            startDate: try ToolDates.parse(args.start),
            endDate: try ToolDates.parse(args.end),
            isAllDay: args.isAllDay,
            location: args.location.isEmpty ? nil : args.location,
            notes: args.notes.isEmpty ? nil : args.notes
        )
        try await writing.update(id: id, with: draft)
        return "Updated \"\(args.title)\"."
    }
}

struct DeleteEventTool: CoachTool {
    let reading: any CalendarReading
    let writing: any CalendarWriting
    let name = "delete_event"
    let description = "Delete an event. Requires user confirmation."
    let requiresConfirmation = true
    var parameters: GenerationSchema { DeleteArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Deleted an event" }

    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] {
        guard let args = try? DeleteArguments(arguments),
              let id = UUID(uuidString: args.id),
              let current = try? await reading.snapshot(id: id)
        else { return ["Delete an event"] }
        return ["Delete: \(eventLine(current))"]
    }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try DeleteArguments(arguments)
        guard let id = UUID(uuidString: args.id),
              let current = try await reading.snapshot(id: id) else {
            return "No event with that id. Use ids exactly as get_events reported them."
        }
        if current.isRecurring {
            return "That event is part of a recurring series, which I can't delete. Ask the user to remove the series in their calendar app."
        }
        try await writing.delete(id: id)
        return "Deleted \"\(current.title)\"."
    }
}
```

```swift
// LifeOSKit/Sources/Assistant/AssistantContext.swift
import Foundation
import Insights
import Persistence

public enum CalendarAssistant {
    /// The six tools, or none: with no authorized source the model gets no
    /// calendar tools and the instructions say so, so it explains what to
    /// connect rather than calling something that would fail.
    public static func tools(
        reading: any CalendarReading,
        writing: any CalendarWriting
    ) -> [any CoachTool] {
        [
            GetEventsTool(reading: reading),
            FindFreeTimeTool(reading: reading),
            AnalyzeScheduleTool(reading: reading),
            CreateEventTool(writing: writing),
            UpdateEventTool(reading: reading, writing: writing),
            DeleteEventTool(reading: reading, writing: writing),
        ]
    }

    public static func instructions(authorized: Bool) -> String {
        let base = """
        You are a calendar assistant. Resolve relative dates against the
        stated current time. Never invent an event id; use ids exactly as
        get_events reports them. State times in the user's timezone. Keep
        replies to a sentence or two. Ask before assuming a duration.
        """
        guard authorized else {
            return base + """


            There are no calendar tools available because no calendar is
            connected. Tell the user to connect their calendar from this
            screen before you can read or change events.
            """
        }
        return base
    }

    /// Today and tomorrow inline, so "what's on today?" needs no tool call:
    /// the cheapest path and the most reliable one on a small model.
    public static func contextPrefix(
        now: Date,
        timeZone: TimeZone,
        today: [CalendarEventSnapshot],
        tomorrow: [CalendarEventSnapshot]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let todayLines = today.isEmpty
            ? "Today: nothing scheduled"
            : "Today:\n" + today.map { eventLine($0, timeZone: timeZone) }.joined(separator: "\n")
        let tomorrowLines = tomorrow.isEmpty
            ? "Tomorrow: nothing scheduled"
            : "Tomorrow:\n" + tomorrow.map { eventLine($0, timeZone: timeZone) }.joined(separator: "\n")
        return """
        Current time: \(formatter.string(from: now)) (\(timeZone.identifier))
        \(todayLines)
        \(tomorrowLines)
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter CalendarToolsTests && swift test --filter AssistantContextTests`
Expected: PASS (9 + 2 tests).

- [ ] **Step 5: Run the whole kit suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS everything.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/Assistant LifeOSKit/Tests/AssistantTests
git commit -m "feat(assistant): add the Assistant target with six calendar tools"
```

---

### Task 6: The assistant sheet and app wiring

**Files:**
- Create: `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift`
- Create: `LIfeOS/Features/Assistant/View/AssistantSheet.swift`
- Modify: `LIfeOS/App/RootView.swift` (present the sheet; add its trigger next to the existing coach trigger)
- Modify: the Xcode project builds these automatically (folder references); verify rather than editing the pbxproj by hand.

**Interfaces:**
- Consumes: everything Tasks 1-5 produced, plus Phase A's `CalendarStore`, `CalendarSync`, `EventKitSource`, and the app's existing `ModelContainer` environment.
- Produces: UI only; nothing downstream.

Design notes binding this task:
- `extension CalendarSync: CalendarWriting {}` is an empty conformance — the three method signatures already match. Put it at the top of `AssistantViewModel.swift`.
- The EventKit permission prompt fires only from the sheet's connect button, never at launch or on sheet open.
- The sheet syncs on open when already authorized, so the assistant reads fresh data.
- The model-availability guard reuses `ModelAvailability`/`SystemLanguageModel` the way `CoachViewModel` does; when unavailable the sheet shows one sentence and no composer.
- Find the trigger site by running `grep -rn "showCoach = true" LIfeOS/` and place a `sparkles` button beside that control, presenting `.sheet(isPresented: $showAssistant)` from `RootView` alongside the existing covers. Match the surrounding button styling exactly (same shape, same materials).
- Styling follows the app's design system (`LifeOSTokens`, `SoftCard`, capsule composer like `LifoCoachScreen`'s typing field).

- [ ] **Step 1: Write the view model**

```swift
// LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift
import Foundation
import FoundationModels
import SwiftData
import SwiftUI
import Assistant
import Insights
import Integrations
import Persistence

extension CalendarSync: CalendarWriting {}

/// Owns one conversation with the calendar assistant. The sheet is a pure
/// function of this state.
@Observable @MainActor
final class AssistantViewModel {
    private(set) var messages: [ChatMessageSnapshot] = []
    private(set) var pending: [PendingWrite] = []
    private(set) var isThinking = false
    private(set) var isAuthorized = false
    var draft = ""

    private let chat: ChatStore
    private let store: CalendarStore
    private let sync: CalendarSync
    private let eventKit: EventKitSource
    private var conversationID = UUID()
    private var broker = ConfirmationBroker()

    init(context: ModelContext) {
        self.chat = ChatStore(context: context)
        self.store = CalendarStore(context: context)
        self.eventKit = EventKitSource()
        self.sync = CalendarSync(sources: [eventKit], store: store)
    }

    var modelAvailable: Bool {
        ModelAvailability.from(SystemLanguageModel.default.availability) == .available
    }

    func appear() async {
        conversationID = (try? chat.latestConversationID()) ?? UUID()
        reloadMessages()
        isAuthorized = await eventKit.isAuthorized
        if isAuthorized { await sync.sync() }
    }

    func connectCalendar() async {
        let granted = (try? await eventKit.requestAccess()) ?? false
        isAuthorized = granted
        if granted { await sync.sync() }
    }

    func confirm(_ id: UUID) { let broker = broker; Task { await broker.confirm(id) } }
    func cancel(_ id: UUID) { let broker = broker; Task { await broker.cancel(id) } }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        draft = ""
        isThinking = true
        defer { isThinking = false; pending = [] }

        try? chat.append(conversationID: conversationID, role: .user, text: text)
        reloadMessages()

        let broker = ConfirmationBroker { [weak self] write in
            Task { @MainActor in self?.pending.append(write) }
        }
        self.broker = broker

        let tools: [any CoachTool] = isAuthorized
            ? CalendarAssistant.tools(reading: store, writing: sync)
            : []

        do {
            let reply = try await AssistantTurn.run(
                instructions: CalendarAssistant.instructions(authorized: isAuthorized),
                prompt: prompt(for: text),
                tools: tools,
                broker: broker
            )
            try? chat.append(
                conversationID: conversationID, role: .assistant,
                text: reply.text, toolSummaries: reply.toolSummaries
            )
        } catch {
            try? chat.append(
                conversationID: conversationID, role: .assistant,
                text: "I couldn't answer that. Try again."
            )
        }
        reloadMessages()
    }

    private func prompt(for text: String) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let today = (try? store.events(from: dayStart, to: tomorrowStart)) ?? []
        let tomorrow = (try? store.events(from: tomorrowStart, to: dayAfterTomorrow)) ?? []

        let history = ((try? chat.recent(conversationID: conversationID)) ?? [])
            .dropLast()  // the just-appended user message; it goes in as the question
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")

        return """
        \(CalendarAssistant.contextPrefix(now: .now, timeZone: .current, today: today, tomorrow: tomorrow))

        \(history)

        User: \(text)
        """
    }

    private func reloadMessages() {
        messages = (try? chat.recent(conversationID: conversationID)) ?? []
    }
}
```

- [ ] **Step 2: Write the sheet**

```swift
// LIfeOS/Features/Assistant/View/AssistantSheet.swift
import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The calendar assistant: message list, activity chips, inline confirmation
/// cards, composer. A pure function of the view model's state.
struct AssistantSheet: View {
    @State var model: AssistantViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    if !model.modelAvailable {
                        Spacer()
                        Text("The assistant needs Apple Intelligence, which isn't available on this device.")
                            .font(.system(size: 15))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    } else {
                        conversation
                        composer
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.appear() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        emptyState.padding(.top, 48)
                    }
                    ForEach(model.messages) { message in
                        bubble(message).id(message.id)
                    }
                    ForEach(model.pending) { write in
                        confirmationCard(write)
                    }
                    if model.isThinking && model.pending.isEmpty {
                        Text("Thinking…")
                            .font(.system(size: 13))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(model.isAuthorized
                 ? "Ask about your schedule, or tell me to move something."
                 : "Connect your calendar so I can see your schedule.")
                .font(.system(size: 15))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .multilineTextAlignment(.center)
            if !model.isAuthorized {
                Button("Connect calendar") {
                    Task { await model.connectCalendar() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(_ message: ChatMessageSnapshot) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user
                              ? AnyShapeStyle(LifeOSTokens.fabFill.resolve(scheme).opacity(0.15))
                              : AnyShapeStyle(.ultraThinMaterial))
                )
            if !message.toolSummaries.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.toolSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func confirmationCard(_ write: PendingWrite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(write.preview, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            HStack(spacing: 12) {
                Button("Confirm") { model.confirm(write.id) }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { model.cancel(write.id) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about your calendar…", text: Bindable(model).draft, axis: .vertical)
                .font(.system(size: 16))
                .focused($composing)
                .lineLimit(1...4)
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LifeOSTokens.fabFill.resolve(scheme))
            }
            .disabled(model.isThinking || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
```

Adjust token names to what `DesignSystem` actually exposes (`LifeOSTokens.canvas`, `.primaryText`, `.secondaryText`, `.fabFill` all exist — verify by grepping before assuming any other).

- [ ] **Step 3: Wire the entry point**

In `LIfeOS/App/RootView.swift`: add `@State private var showAssistant = false`, present `.sheet(isPresented: $showAssistant) { AssistantSheet(model: assistantModel) }` alongside the existing covers, holding `@State private var assistantModel: AssistantViewModel` created with the same `ModelContext` the other view models use (find how `RootView` obtains its context — grep `modelContext` or the container — and follow that exact pattern). Then find the coach trigger (`grep -rn "showCoach = true" LIfeOS/`) and add a `sparkles` button beside it with the same styling, setting `showAssistant = true`. Accessibility label "Calendar assistant".

- [ ] **Step 4: Build and test**

Run: `cd LifeOSKit && swift test` — expect all green.
Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Assistant LIfeOS/App/RootView.swift
git commit -m "feat(assistant): present the calendar assistant sheet from Today"
```

---

## Out of scope for this plan

- The remote engine, the `coach` Edge Function and its tool-calling request shape, budget interaction, and the S14 escalation disclosure — all land with the coach's Plan 2.
- Phase C: `AgendaCard`, `EventSheet`, `TodaySnapshot.agenda`, scenePhase sync wiring.
- Phase D: Google Calendar.
- Undo affordance on created events (needs `create` to return the new id).
- Voice input and streaming (spec S17).
