# LIFO Conversational Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give LIFO a memory and a provider-neutral tool-calling loop, so the
coach remembers the conversation and OpenAI, not Apple's on-device model, is
the model that answers.

**Architecture:** A `ChatEngine` protocol sits beside the existing `Engine`
with two conformers: today's FoundationModels path, unchanged, and a new
remote path that runs OpenAI function calling through the `lifo-agent` Edge
Function. `AssistantTurn` becomes the router across them, remote first. The
loop is client-driven: the device owns the rounds and executes every tool
locally, so the Edge Function stays transport and never needs to call back
into the phone.

**Tech Stack:** Swift 6, swift-testing, FoundationModels, SwiftData,
Deno/TypeScript Edge Functions, OpenAI chat completions.

**Spec:** `docs/superpowers/specs/2026-08-28-proactive-lifo-design.md`
(this plan implements Slice 1, section 4, only)

## Global Constraints

- **Run Swift tests with:** `swift test --package-path LifeOSKit` (add
  `--filter <SuiteName>` to narrow).
- **Build the app with:** `xcodebuild -project ./LIfeOS.xcodeproj -scheme
  LIfeOS -destination 'generic/platform=iOS Simulator' build`
- **Run Deno tests with:** `deno test supabase/functions/_shared/lifo_test.ts`
- **There is no test target for the `LIfeOS` app.** Only `LifeOSKit` has
  tests. Anything under `LIfeOS/Features/...` is verified by `xcodebuild`
  plus a manual pass. Do not invent an app test target to satisfy a step.
- **Every path is relative to the worktree root.** Never edit, build, or
  test the primary checkout at `/Users/shivvyas/LIfeOS` from inside a
  worktree.
- **Commits carry no AI attribution.** No `Co-Authored-By`, no "Generated
  with". Conventional format, `type(scope): imperative summary`, and no em
  dashes or en dashes anywhere in the message.
- **`ResponseStyle.instruction` is not modified.** It keeps serving one-shot
  tasks exactly as it does today. Conversation gets a second constant.
- **The existing `{task, prompt}` wire shape keeps working.** `AnswerTask`,
  `BriefTask` and `SectorNoteTask` must not change behaviour. There is a
  regression test for this in Task 3 and it is load-bearing.
- **Chat history never leaves the device.** The Edge Function writes no
  message text to any table and logs none. Existing comments in
  `lifo-agent/index.ts` state this; they stay true.
- **Tool execution never leaves the device.** The server may only ever
  return a request to call a tool, never a result.
- **Round cap:** the loop is bounded by the existing
  `ToolInvoker.invocationLimit` (6). Do not add a second, different cap.

---

## File Structure

**Server**

- `supabase/functions/_shared/lifo.ts` (modify) — gains the `chat` task
  config, `chatBody`, `parseChatReply`, and `parseRequest`. Stays pure: no
  network, no Deno.serve. Every decision in this file is unit tested.
- `supabase/functions/_shared/lifo_test.ts` (modify) — tests for the above,
  plus the back-compat regression test.
- `supabase/functions/lifo-agent/index.ts` (modify) — the door only. Parses
  the request through `parseRequest`, branches, meters, sends.

**LifeOSKit / Insights**

- `LifeOSKit/Sources/Insights/Chat/ToolSchema.swift` (create) — one pure
  function turning a `CoachTool` into OpenAI's function JSON.
- `LifeOSKit/Sources/Insights/Chat/ChatWire.swift` (create) — request
  building and reply parsing for the chat path. Pure, mirrors `RemoteWire`.
- `LifeOSKit/Sources/Insights/Chat/ChatEngine.swift` (create) — the protocol
  and `ChatTurnMessage`.
- `LifeOSKit/Sources/Insights/Chat/OnDeviceChatEngine.swift` (create) —
  today's `AssistantTurn.run` body, moved with no behaviour change.
- `LifeOSKit/Sources/Insights/Chat/RemoteChatEngine.swift` (create) — the
  OpenAI round loop.
- `LifeOSKit/Sources/Insights/AssistantTurn.swift` (modify) — becomes the
  router across the two engines.
- `LifeOSKit/Sources/Insights/Engines/RemoteEngine.swift` (modify) — the
  status-to-error mapping is factored out so `ChatWire` shares it rather
  than duplicating it.
- `LifeOSKit/Sources/Insights/ResponseStyle.swift` (modify) — gains
  `conversation`. `instruction` and `clean(_:)` are untouched.

**LifeOSKit / Tests**

- `LifeOSKit/Tests/InsightsTests/ToolSchemaTests.swift` (create)
- `LifeOSKit/Tests/InsightsTests/ChatWireTests.swift` (create)
- `LifeOSKit/Tests/InsightsTests/RemoteChatEngineTests.swift` (create)
- `LifeOSKit/Tests/InsightsTests/AssistantTurnTests.swift` (create)
- `LifeOSKit/Tests/InsightsTests/ResponseStyleTests.swift` (modify)

**App**

- `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift` (modify) — moves
  off `AnswerTask` onto `AssistantTurn`, gaining a conversation id and
  `ChatStore`.

---

### Task 1: Tool schema in OpenAI's shape

**Files:**
- Create: `LifeOSKit/Sources/Insights/Chat/ToolSchema.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ToolSchemaTests.swift`

**Interfaces:**
- Consumes: `CoachTool` (`name`, `description`, `parameters: GenerationSchema`).
- Produces: `ToolSchema.function(for:) throws -> [String: Any]`, used by
  `ChatWire.request` in Task 2.

**Background you need:** `GenerationSchema` is `Codable`, and
`SchemaEncodingTests.swift` already proves it encodes to a JSON object with
`"type": "object"` and a `properties` dictionary carrying our own property
names. That is close enough to JSON Schema to hand to OpenAI directly. You
are adding `additionalProperties: false` and nothing else.

**Ruling, so you do not have to decide it:** the function is declared
`"strict": false`. OpenAI's strict mode requires every declared property to
appear in `required`, which would silently turn optional tool arguments into
mandatory ones. Non-strict function calling is standard and preserves the
schema's own meaning. Do not set `strict: true`.

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/InsightsTests/ToolSchemaTests.swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable private struct RangeArgs {
    @Guide(description: "ISO-8601 start") var start: String
    @Guide(description: "ISO-8601 end") var end: String
}

private struct StubTool: CoachTool {
    let name = "get_events"
    let description = "Reads calendar events in a range."
    var parameters: GenerationSchema { RangeArgs.generationSchema }
    func call(_ arguments: GeneratedContent) async throws -> String { "ok" }
}

@Suite struct ToolSchemaTests {

    private func function(_ tool: any CoachTool) throws -> [String: Any] {
        let json = try ToolSchema.function(for: tool)
        return try #require(json["function"] as? [String: Any])
    }

    @Test func aToolBecomesAnOpenAIFunctionDeclaration() throws {
        let json = try ToolSchema.function(for: StubTool())
        #expect(json["type"] as? String == "function")

        let function = try #require(json["function"] as? [String: Any])
        #expect(function["name"] as? String == "get_events")
        #expect(function["description"] as? String == "Reads calendar events in a range.")
    }

    @Test func theGenerationSchemaSurvivesAsTheParameterObject() throws {
        let function = try function(StubTool())
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")

        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(properties.keys.contains("start"))
        #expect(properties.keys.contains("end"))
    }

    /// A model that invents an argument we never declared is a model whose
    /// call we cannot decode. Refusing extras at the schema is cheaper than
    /// discovering it at `GeneratedContent(json:)`.
    @Test func extraArgumentsAreForbidden() throws {
        let function = try function(StubTool())
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    /// Strict mode would list every property as required, quietly making an
    /// optional tool argument mandatory. See the ruling in the plan.
    @Test func theDeclarationIsNotStrict() throws {
        let function = try function(StubTool())
        #expect(function["strict"] as? Bool == false)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --package-path LifeOSKit --filter ToolSchemaTests`
Expected: FAIL, `cannot find 'ToolSchema' in scope`.

- [ ] **Step 3: Implement**

```swift
// LifeOSKit/Sources/Insights/Chat/ToolSchema.swift
import Foundation
import FoundationModels

/// Renders a `CoachTool` into the shape OpenAI's function calling expects.
///
/// This is the whole reason `CoachTool.parameters` was declared as a
/// `GenerationSchema` rather than as an on-device-only type: the schema is
/// Codable, and what it encodes to is already JSON Schema in all but name.
/// `SchemaEncodingTests` pins that assumption; this file depends on it.
public enum ToolSchema {

    public static func function(for tool: any CoachTool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(tool.parameters)
        var parameters = (try JSONSerialization.jsonObject(with: data)
            as? [String: Any]) ?? [:]

        // Not a stylistic addition. An argument we never declared cannot be
        // decoded by `GeneratedContent(json:)` on the way back in, so the
        // cheapest place to refuse it is before the model emits it.
        parameters["additionalProperties"] = false

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": parameters,
                // Deliberately false. Strict mode requires every property to
                // be listed as required, which would turn an optional tool
                // argument into a mandatory one without anyone deciding to.
                "strict": false,
            ] as [String: Any],
        ]
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --package-path LifeOSKit --filter ToolSchemaTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/Chat/ToolSchema.swift LifeOSKit/Tests/InsightsTests/ToolSchemaTests.swift
git commit -m "feat(chat): render a coach tool as an OpenAI function"
```

---

### Task 2: The chat wire

**Files:**
- Create: `LifeOSKit/Sources/Insights/Chat/ChatWire.swift`
- Modify: `LifeOSKit/Sources/Insights/Engines/RemoteEngine.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ChatWireTests.swift`

**Interfaces:**
- Consumes: `ToolSchema.function(for:)` from Task 1; `RemoteEngineError`.
- Produces:
  - `ChatWire.Message(role:content:toolCallID:toolCalls:)`
  - `ChatWire.ToolCall(id:name:argumentsJSON:)`
  - `ChatWire.Reply` with cases `.text(String)` and `.toolCalls([ToolCall])`
  - `ChatWire.request(baseURL:anonKey:accessToken:messages:tools:) throws -> URLRequest`
  - `ChatWire.reply(data:status:) throws -> Reply`
  - `RemoteWire.failure(data:status:) -> RemoteEngineError?`

**Why `RemoteWire` is being modified:** the status-to-error mapping in
`RemoteWire.result` (429 and `"exhausted"` mean exhausted, 403 and
`"refused"` mean refused, everything else is unavailable) is exactly the
mapping the chat path needs. Factor it into `RemoteWire.failure(data:status:)`
returning an optional error, and have `RemoteWire.result` call it. Do not
copy the switch into `ChatWire`. `RemoteEngineTests` must still pass
unchanged after this refactor; if it does not, the refactor changed
behaviour and is wrong.

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/InsightsTests/ChatWireTests.swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable private struct RangeArgs {
    @Guide(description: "ISO-8601 start") var start: String
}

private struct StubTool: CoachTool {
    let name = "get_events"
    let description = "Reads calendar events in a range."
    var parameters: GenerationSchema { RangeArgs.generationSchema }
    func call(_ arguments: GeneratedContent) async throws -> String { "ok" }
}

@Suite struct ChatWireTests {

    private let base = URL(string: "https://example.supabase.co")!

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let raw = try JSONSerialization.jsonObject(with: #require(request.httpBody))
        return try #require(raw as? [String: Any])
    }

    @Test func theRequestGoesToLifoAgentWithBothCredentials() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "anon-key", accessToken: "jwt-token",
            messages: [ChatWire.Message(role: "user", content: "how did I sleep?")],
            tools: []
        )
        #expect(request.url?.path.hasSuffix("/functions/v1/lifo-agent") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")
    }

    /// The task name is what selects the server-side system prompt, so a
    /// chat request that forgot it would be answered by the one-shot
    /// configuration and lose the conversational instruction entirely.
    @Test func theRequestNamesTheChatTask() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [ChatWire.Message(role: "user", content: "hi")], tools: []
        )
        #expect(try body(request)["task"] as? String == "chat")
    }

    @Test func everyTurnOfTheThreadTravels() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [
                ChatWire.Message(role: "user", content: "how did I sleep?"),
                ChatWire.Message(role: "assistant", content: "Six hours."),
                ChatWire.Message(role: "user", content: "is that bad?"),
            ],
            tools: []
        )
        let messages = try #require(try body(request)["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[2]["content"] as? String == "is that bad?")
    }

    @Test func toolsTravelAsFunctionDeclarations() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [ChatWire.Message(role: "user", content: "what is on today?")],
            tools: [StubTool()]
        )
        let tools = try #require(try body(request)["tools"] as? [[String: Any]])
        let function = try #require(tools.first?["function"] as? [String: Any])
        #expect(function["name"] as? String == "get_events")
    }

    /// A tool result is a message with a role of its own and the id of the
    /// call it answers. Dropping the id makes the provider unable to pair a
    /// result with its request, which surfaces as the model repeating the
    /// same call forever.
    @Test func aToolResultCarriesTheIdOfTheCallItAnswers() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [ChatWire.Message(
                role: "tool", content: "3 events", toolCallID: "call_42"
            )],
            tools: []
        )
        let messages = try #require(try body(request)["messages"] as? [[String: Any]])
        #expect(messages[0]["role"] as? String == "tool")
        #expect(messages[0]["tool_call_id"] as? String == "call_42")
    }

    @Test func aTextReplyParses() throws {
        let data = Data(#"{"output":{"text":"Six hours, which is short for you."}}"#.utf8)
        #expect(try ChatWire.reply(data: data, status: 200)
            == .text("Six hours, which is short for you."))
    }

    @Test func aToolCallReplyParses() throws {
        let data = Data("""
        {"tool_calls":[{"id":"call_42","name":"get_events","arguments":"{\\"start\\":\\"2026-08-28\\"}"}]}
        """.utf8)
        let reply = try ChatWire.reply(data: data, status: 200)
        guard case .toolCalls(let calls) = reply else {
            Issue.record("expected tool calls, got \(reply)")
            return
        }
        #expect(calls.count == 1)
        #expect(calls[0].id == "call_42")
        #expect(calls[0].name == "get_events")
        #expect(calls[0].argumentsJSON == #"{"start":"2026-08-28"}"#)
    }

    /// The same three failures the one-shot path already distinguishes, and
    /// for the same reasons: a spent budget must not offer a retry, and a
    /// refusal is not a fault to route around.
    @Test func aSpentBudgetIsItsOwnError() {
        let data = Data(#"{"error":"exhausted"}"#.utf8)
        #expect(throws: RemoteEngineError.exhausted) {
            _ = try ChatWire.reply(data: data, status: 429)
        }
    }

    @Test func aRefusalKeepsItsMessage() {
        let data = Data(#"{"error":"refused","message":"That is outside what I cover."}"#.utf8)
        #expect(throws: RemoteEngineError.refused("That is outside what I cover.")) {
            _ = try ChatWire.reply(data: data, status: 403)
        }
    }

    @Test func aBodyThatFitsNoShapeIsTheServerBeingWrong() {
        let data = Data(#"{"unexpected":true}"#.utf8)
        #expect(throws: RemoteEngineError.unavailable) {
            _ = try ChatWire.reply(data: data, status: 200)
        }
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --package-path LifeOSKit --filter ChatWireTests`
Expected: FAIL, `cannot find 'ChatWire' in scope`.

- [ ] **Step 3: Factor the failure mapping out of `RemoteWire`**

In `LifeOSKit/Sources/Insights/Engines/RemoteEngine.swift`, add to
`RemoteWire`:

```swift
    /// The error a response describes, or nil when it describes success.
    ///
    /// Shared with the chat path rather than copied into it. Two mappings
    /// that are meant to agree and are written twice do not stay agreeing:
    /// the day someone adds a status here, the other one is silently a
    /// version behind.
    public static func failure(data: Data, status: Int) -> RemoteEngineError? {
        guard !(200..<300).contains(status) else { return nil }
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        switch (status, failure?.error) {
        case (429, _), (_, "exhausted"):
            return .exhausted
        case (403, _), (_, "refused"):
            return .refused(failure?.message ?? "LIFO declined that one.")
        default:
            return .unavailable
        }
    }
```

Then rewrite the guard at the top of `RemoteWire.result` to use it:

```swift
        if let error = failure(data: data, status: status) { throw error }
```

`Failure` must become non-private for this (it is already nested inside
`RemoteWire`, so `fileprivate` is enough). Leave everything else in
`result` alone.

- [ ] **Step 4: Confirm the refactor changed nothing**

Run: `swift test --package-path LifeOSKit --filter RemoteWireTests`
Expected: PASS, unchanged. If any test in that suite fails, the refactor
altered behaviour: revert and redo it.

- [ ] **Step 5: Implement `ChatWire`**

```swift
// LifeOSKit/Sources/Insights/Chat/ChatWire.swift
import Foundation

/// The chat wire format, kept out of the engine so every decision it makes
/// is testable without a network. The same division `RemoteWire` uses, for
/// the same reason.
public enum ChatWire {

    /// One tool call the model asked for.
    ///
    /// `argumentsJSON` stays a string rather than being decoded here: the
    /// only consumer is `GeneratedContent(json:)`, which takes a string, and
    /// decoding it twice would be work done only to undo it.
    public struct ToolCall: Sendable, Equatable {
        public let id: String
        public let name: String
        public let argumentsJSON: String

        public init(id: String, name: String, argumentsJSON: String) {
            self.id = id
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }

    public struct Message: Sendable, Equatable {
        public let role: String
        public let content: String
        /// Set only on a tool result, naming the call it answers.
        public let toolCallID: String?
        /// Set only on an assistant turn that asked for tools, so the thread
        /// we resend reads back to the provider the way it produced it.
        public let toolCalls: [ToolCall]?

        public init(role: String, content: String,
                    toolCallID: String? = nil, toolCalls: [ToolCall]? = nil) {
            self.role = role
            self.content = content
            self.toolCallID = toolCallID
            self.toolCalls = toolCalls
        }

        var payload: [String: Any] {
            var json: [String: Any] = ["role": role, "content": content]
            if let toolCallID { json["tool_call_id"] = toolCallID }
            if let toolCalls, !toolCalls.isEmpty {
                json["tool_calls"] = toolCalls.map {
                    ["id": $0.id, "name": $0.name, "arguments": $0.argumentsJSON]
                }
            }
            return json
        }
    }

    public enum Reply: Sendable, Equatable {
        case text(String)
        case toolCalls([ToolCall])
    }

    public static func request(
        baseURL: URL, anonKey: String, accessToken: String,
        messages: [Message], tools: [any CoachTool]
    ) throws -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("functions/v1/lifo-agent")
        )
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "task": "chat",
            "messages": messages.map(\.payload),
            "tools": try tools.map { try ToolSchema.function(for: $0) },
        ])
        return request
    }

    private struct TextReply: Decodable {
        struct Output: Decodable { let text: String }
        let output: Output
    }

    private struct ToolCallsReply: Decodable {
        struct Call: Decodable {
            let id: String
            let name: String
            let arguments: String
        }
        let tool_calls: [Call]
    }

    public static func reply(data: Data, status: Int) throws -> Reply {
        if let error = RemoteWire.failure(data: data, status: status) { throw error }

        // Tool calls first. A reply carrying both is the provider telling us
        // it wants a tool run before it will commit to prose, and answering
        // with the prose would strand the call.
        if let calls = try? JSONDecoder().decode(ToolCallsReply.self, from: data),
           !calls.tool_calls.isEmpty {
            return .toolCalls(calls.tool_calls.map {
                ToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.arguments)
            })
        }
        if let text = try? JSONDecoder().decode(TextReply.self, from: data) {
            return .text(text.output.text)
        }
        // A 200 whose body fits neither shape is the server being wrong,
        // which the user cannot fix and a retry might. Never a refusal.
        throw RemoteEngineError.unavailable
    }
}
```

- [ ] **Step 6: Run both suites**

Run: `swift test --package-path LifeOSKit --filter ChatWireTests`
Expected: PASS, 9 tests.

Run: `swift test --package-path LifeOSKit --filter RemoteWireTests`
Expected: PASS, unchanged.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Insights/Chat/ChatWire.swift LifeOSKit/Sources/Insights/Engines/RemoteEngine.swift LifeOSKit/Tests/InsightsTests/ChatWireTests.swift
git commit -m "feat(chat): carry a thread and its tools over the wire"
```

---

### Task 3: The server's chat task

**Files:**
- Modify: `supabase/functions/_shared/lifo.ts`
- Test: `supabase/functions/_shared/lifo_test.ts`

**Interfaces:**
- Produces, for Task 4:
  - `parseRequest(body: unknown)` returning
    `{ kind: "prompt", task: string, prompt: string }` or
    `{ kind: "chat", messages: unknown[], tools: unknown[] }` or `null`
  - `chatBody(messages: unknown[], tools: unknown[]): Record<string, unknown>`
  - `parseChatReply(body: unknown)` returning
    `{ kind: "text", text: string, tokens: number }` or
    `{ kind: "tool_calls", toolCalls: unknown[], tokens: number }`,
    throwing `LifoRefusal` on a refusal.

**The guardrail matters most here.** `SCOPE` is the reason the system prompt
lives server-side: a modified client cannot strip what it never carries. The
chat system prompt is `SCOPE` plus conversational permissions, never a
replacement for it. There is a test that pins this and it is not optional.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/functions/_shared/lifo_test.ts`, and add
`chatBody`, `parseChatReply`, `parseRequest` to its import list:

```ts
Deno.test("the chat task still carries the scope guardrail", () => {
  const system = taskConfig("chat")!.system;
  for (const anchor of ["their own", "decline", "diagnos", "invest"]) {
    assertEquals(system.toLowerCase().includes(anchor), true, `missing: ${anchor}`);
  }
});

// The whole point of the slice. If this drifts back to the one-shot
// instruction, LIFO goes back to being a box that answers and stops.
Deno.test("the chat task is allowed to be conversational", () => {
  const system = taskConfig("chat")!.system.toLowerCase();
  assertEquals(system.includes("earlier"), true);
  assertEquals(system.includes("one question"), true);
});

Deno.test("the chat body sends the thread behind the system prompt", () => {
  const body = chatBody(
    [{ role: "user", content: "how did I sleep?" }],
    [],
  ) as { model: string; messages: { role: string }[]; tools?: unknown[] };
  assertEquals(body.model, "gpt-5-mini");
  assertEquals(body.messages[0].role, "system");
  assertEquals(body.messages[1].role, "user");
});

// An empty tools array and an absent one mean different things to the
// provider, and sending `tools: []` is rejected by some versions outright.
Deno.test("no tools means the key is absent, not empty", () => {
  const body = chatBody([{ role: "user", content: "hi" }], []) as Record<string, unknown>;
  assertEquals("tools" in body, false);
});

Deno.test("tools are passed through with an auto choice", () => {
  const tool = { type: "function", function: { name: "get_events" } };
  const body = chatBody([{ role: "user", content: "hi" }], [tool]) as Record<string, unknown>;
  assertEquals(body.tools, [tool]);
  assertEquals(body.tool_choice, "auto");
});

Deno.test("a text completion parses as text", () => {
  const parsed = parseChatReply({
    choices: [{ message: { content: "Six hours." } }],
    usage: { total_tokens: 120 },
  });
  assertEquals(parsed, { kind: "text", text: "Six hours.", tokens: 120 });
});

Deno.test("a tool call completion parses as tool calls", () => {
  const parsed = parseChatReply({
    choices: [{
      message: {
        tool_calls: [{
          id: "call_42",
          function: { name: "get_events", arguments: '{"start":"2026-08-28"}' },
        }],
      },
    }],
    usage: { total_tokens: 90 },
  }) as { kind: string; toolCalls: { id: string; name: string; arguments: string }[] };
  assertEquals(parsed.kind, "tool_calls");
  assertEquals(parsed.toolCalls[0].id, "call_42");
  assertEquals(parsed.toolCalls[0].name, "get_events");
  assertEquals(parsed.toolCalls[0].arguments, '{"start":"2026-08-28"}');
});

Deno.test("a refusal is a refusal on the chat path too", () => {
  assertThrows(
    () => parseChatReply({ choices: [{ message: { refusal: "Not something I cover." } }] }),
    LifoRefusal,
  );
});

// Load-bearing regression guard. Slice 1 must not change how the one-shot
// tasks are served, and this is the test that notices if it did.
Deno.test("the old prompt shape still parses as a prompt request", () => {
  const parsed = parseRequest({ task: "answer", prompt: "Question: how did I sleep?" });
  assertEquals(parsed, {
    kind: "prompt",
    task: "answer",
    prompt: "Question: how did I sleep?",
  });
});

Deno.test("a chat request parses as a chat request", () => {
  const parsed = parseRequest({
    task: "chat",
    messages: [{ role: "user", content: "hi" }],
    tools: [],
  }) as { kind: string; messages: unknown[] };
  assertEquals(parsed.kind, "chat");
  assertEquals(parsed.messages.length, 1);
});

Deno.test("a request naming no known task is refused before any spend", () => {
  assertEquals(parseRequest({ task: "exfiltrate", prompt: "hi" }), null);
  assertEquals(parseRequest({ task: "answer" }), null);
  assertEquals(parseRequest({ task: "chat", messages: [] }), null);
  assertEquals(parseRequest("not an object"), null);
});
```

- [ ] **Step 2: Run and watch it fail**

Run: `deno test supabase/functions/_shared/lifo_test.ts`
Expected: FAIL, `chatBody` is not exported.

- [ ] **Step 3: Implement in `lifo.ts`**

Add a `chat` entry to `TASKS` (its `schema` is unused on this path; give it
the same `coach_answer` object so the record's type is unchanged), and the
three functions:

```ts
const CONVERSATION = `Write in plain sentences, the way a person speaks.
Never use markdown: no asterisks, underscores, backticks, hash headings,
bullet characters or numbered lists. Never use em dashes or en dashes; use
a comma or start a new sentence. Give figures as figures with their units,
and never invent one.

You are in a conversation, not answering a form. You may refer back to what
was said earlier in this thread, and you may acknowledge what the person
told you before answering. When you genuinely need something to answer well,
ask one question back. One, not a list, and not out of habit.`;

// The chat task. SCOPE first and always: the guardrail is the reason this
// prompt lives on the server, and the conversational permissions are added
// behind it rather than in place of it.
TASKS.chat = {
  model: "gpt-5-mini",
  system: `${SCOPE}\n\n${CONVERSATION}`,
  schema: TASKS.answer.schema,
};

export function chatBody(
  messages: unknown[],
  tools: unknown[],
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: TASKS.chat.model,
    messages: [{ role: "system", content: TASKS.chat.system }, ...messages],
  };
  // Absent rather than empty. The two are not the same to the provider, and
  // an empty array is rejected outright by some versions.
  if (tools.length > 0) {
    body.tools = tools;
    body.tool_choice = "auto";
  }
  return body;
}

export function parseChatReply(body: unknown) {
  const reply = body as {
    choices?: {
      message?: {
        content?: string;
        refusal?: string;
        tool_calls?: { id: string; function: { name: string; arguments: string } }[];
      };
    }[];
    usage?: { total_tokens?: number };
  };
  const message = reply.choices?.[0]?.message;
  if (!message) throw new Error("no choices in reply");
  if (message.refusal) throw new LifoRefusal(message.refusal);

  const tokens = reply.usage?.total_tokens ?? 0;

  // Tool calls before content. A completion carrying both wants the tool run
  // before it commits to prose, and answering with the prose strands it.
  if (message.tool_calls && message.tool_calls.length > 0) {
    return {
      kind: "tool_calls" as const,
      toolCalls: message.tool_calls.map((call) => ({
        id: call.id,
        name: call.function.name,
        arguments: call.function.arguments,
      })),
      tokens,
    };
  }
  if (!message.content) throw new Error("empty content");
  return { kind: "text" as const, text: message.content, tokens };
}

// The door's whole validation, hoisted here so it is tested rather than
// living inside Deno.serve where it is not.
export function parseRequest(body: unknown) {
  if (typeof body !== "object" || body === null) return null;
  const raw = body as Record<string, unknown>;
  const task = String(raw.task ?? "");
  if (!taskConfig(task)) return null;

  if (task === "chat") {
    const messages = Array.isArray(raw.messages) ? raw.messages : [];
    const tools = Array.isArray(raw.tools) ? raw.tools : [];
    if (messages.length === 0) return null;
    return { kind: "chat" as const, messages, tools };
  }

  const prompt = String(raw.prompt ?? "");
  if (!prompt) return null;
  return { kind: "prompt" as const, task, prompt };
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `deno test supabase/functions/_shared/lifo_test.ts`
Expected: PASS, all tests including the pre-existing ones.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/lifo.ts supabase/functions/_shared/lifo_test.ts
git commit -m "feat(lifo): teach the server a conversation with tools"
```

---

### Task 4: The door

**Files:**
- Modify: `supabase/functions/lifo-agent/index.ts`

**Interfaces:**
- Consumes: `parseRequest`, `chatBody`, `parseChatReply` from Task 3, plus
  the existing `openAIBody`, `parseOutput`, `DAILY_TOKEN_CAP`, `lifo_debit`.

**What must not change:** the budget check runs before any provider call;
the debit runs on every path that reached the provider, refusals and parse
failures included; and no prompt, message, or tool argument is ever logged
or written to a table. The comment at the top of the file saying so stays
true after this task.

- [ ] **Step 1: Replace the body parsing**

Swap the inline `task`/`prompt` extraction for `parseRequest`:

```ts
  let parsed: ReturnType<typeof parseRequest>;
  try {
    parsed = parseRequest(await req.json());
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!parsed) return json({ error: "unknown_task" }, 400);
```

Add `chatBody`, `parseChatReply`, `parseRequest` to the import from
`../_shared/lifo.ts`, and drop `taskConfig` if nothing else uses it.

- [ ] **Step 2: Branch the provider call**

```ts
  const payload = parsed.kind === "chat"
    ? chatBody(parsed.messages, parsed.tools)
    : openAIBody(parsed.task, parsed.prompt);
```

and use `payload` where `openAIBody(task, prompt)` was.

- [ ] **Step 3: Branch the reply**

Replace the final `try` block. The debit above it is untouched and still
runs first.

```ts
  try {
    if (parsed.kind === "chat") {
      const reply = parseChatReply(body);
      console.log(`lifo task=chat kind=${reply.kind} tokens=${tokens} ms=${Date.now() - started}`);
      return reply.kind === "text"
        ? json({ output: { text: reply.text }, tokens }, 200)
        : json({ tool_calls: reply.toolCalls, tokens }, 200);
    }
    const { output } = parseOutput(parsed.task, body);
    console.log(`lifo task=${parsed.task} tokens=${tokens} ms=${Date.now() - started}`);
    return json({ output, tokens }, 200);
  } catch (failure) {
    if (failure instanceof LifoRefusal) {
      return json({ error: "refused", message: failure.message }, 403);
    }
    console.error(`lifo parse failed`);
    return json({ error: "upstream_failure" }, 502);
  }
```

Note the log line carries the reply kind and token count and nothing else.
No message content, no tool arguments.

- [ ] **Step 4: Type-check and re-run the shared tests**

Run: `deno check supabase/functions/lifo-agent/index.ts`
Expected: no errors.

Run: `deno test supabase/functions/_shared/lifo_test.ts`
Expected: PASS, unchanged from Task 3.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/lifo-agent/index.ts
git commit -m "feat(lifo): serve a chat turn alongside the one-shot tasks"
```

---

### Task 5: The engines

**Files:**
- Create: `LifeOSKit/Sources/Insights/Chat/ChatEngine.swift`
- Create: `LifeOSKit/Sources/Insights/Chat/OnDeviceChatEngine.swift`
- Create: `LifeOSKit/Sources/Insights/Chat/RemoteChatEngine.swift`
- Test: `LifeOSKit/Tests/InsightsTests/RemoteChatEngineTests.swift`

**Interfaces:**
- Consumes: `ChatWire` (Task 2), `ToolInvoker`, `ConfirmationBroker`,
  `AssistantTurn.Reply`.
- Produces:
  - `ChatTurnMessage(role:text:)` with `ChatTurnMessage.Role` of `.user`
    and `.assistant`
  - `protocol ChatEngine` with
    `reply(to:tools:invoker:) async throws -> AssistantTurn.Reply`
  - `OnDeviceChatEngine(instructions:)`
  - `RemoteChatEngine(baseURL:anonKey:accessToken:transport:)`

**The transport seam exists so the loop is testable.** `RemoteChatEngine`
takes a `transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)`
defaulting to `URLSession.shared.data(for:)`. Without it the round loop can
only be exercised against a live network, and the loop is the part most
worth testing.

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/InsightsTests/RemoteChatEngineTests.swift
import Testing
import Foundation
import FoundationModels
@testable import Insights

@Generable private struct RangeArgs {
    @Guide(description: "ISO-8601 start") var start: String
}

/// Records what it was asked, so a test can assert the loop actually ran the
/// tool rather than merely claiming to.
private actor ToolLog {
    private(set) var calls: [String] = []
    func record(_ name: String) { calls.append(name) }
}

private struct RecordingTool: CoachTool {
    let name = "get_events"
    let description = "Reads calendar events in a range."
    var parameters: GenerationSchema { RangeArgs.generationSchema }
    let log: ToolLog

    func summary(_ arguments: GeneratedContent) -> String { "Checked the calendar" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        await log.record(name)
        return "3 events"
    }
}

/// Replies in the order given, one per request, so a multi-round loop can be
/// scripted end to end.
private final class ScriptedTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [String]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            requests.append(request)
            let body = replies.isEmpty ? #"{"output":{"text":"done"}}"# : replies.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response as URLResponse)
        }
    }
}

@Suite struct RemoteChatEngineTests {

    private let base = URL(string: "https://example.supabase.co")!

    private func engine(_ transport: ScriptedTransport) -> RemoteChatEngine {
        RemoteChatEngine(
            baseURL: base, anonKey: "k", accessToken: { "jwt" },
            transport: { try await transport.send($0) }
        )
    }

    private func invoker(_ tools: [any CoachTool]) -> ToolInvoker {
        ToolInvoker(tools: tools, broker: ConfirmationBroker())
    }

    @Test func aPlainReplyComesBackAsText() async throws {
        let transport = ScriptedTransport([#"{"output":{"text":"Six hours."}}"#])
        let reply = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "how did I sleep?")],
            tools: [], invoker: invoker([])
        )
        #expect(reply.text == "Six hours.")
        #expect(reply.toolSummaries.isEmpty)
    }

    /// The round trip that is the whole point: the model asks for a tool, the
    /// device runs it locally, the result goes back, and the model answers.
    @Test func aToolCallIsRunOnTheDeviceAndTheResultIsSentBack() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let transport = ScriptedTransport([
            #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"{\"start\":\"2026-08-28\"}"}]}"#,
            #"{"output":{"text":"You have three today."}}"#,
        ])

        let reply = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "what is on today?")],
            tools: [tool], invoker: invoker([tool])
        )

        let calls = await log.calls
        #expect(reply.text == "You have three today.")
        #expect(calls.count == 1)
        #expect(reply.toolSummaries == ["Checked the calendar"])
        #expect(transport.requests.count == 2)
    }

    /// The tool result must reach the provider, or the model asks again and
    /// the loop burns every round it has.
    @Test func theSecondRequestCarriesTheToolResult() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let transport = ScriptedTransport([
            #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"{\"start\":\"2026-08-28\"}"}]}"#,
            #"{"output":{"text":"Three."}}"#,
        ])
        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "what is on today?")],
            tools: [tool], invoker: invoker([tool])
        )

        let body = try JSONSerialization.jsonObject(
            with: #require(transport.requests[1].httpBody)
        ) as? [String: Any]
        let messages = try #require(body?["messages"] as? [[String: Any]])
        let toolMessage = try #require(messages.last)
        #expect(toolMessage["role"] as? String == "tool")
        #expect(toolMessage["tool_call_id"] as? String == "call_1")
        #expect(toolMessage["content"] as? String == "3 events")
    }

    /// A model that will not stop calling tools must not be able to spend an
    /// unbounded number of rounds. The cap is ToolInvoker's, already six.
    @Test func aLoopThatWillNotConvergeIsBounded() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let call = #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"{\"start\":\"2026-08-28\"}"}]}"#
        let transport = ScriptedTransport(Array(repeating: call, count: 20))

        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "loop")],
            tools: [tool], invoker: invoker([tool])
        )

        #expect(transport.requests.count <= ToolInvoker.invocationLimit + 1)
    }

    @Test func noSessionIsNotSignedIn() async {
        let transport = ScriptedTransport([])
        let engine = RemoteChatEngine(
            baseURL: base, anonKey: "k", accessToken: { nil },
            transport: { try await transport.send($0) }
        )
        await #expect(throws: RemoteEngineError.notSignedIn) {
            try await engine.reply(
                to: [ChatTurnMessage(role: .user, text: "hi")],
                tools: [], invoker: self.invoker([])
            )
        }
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `swift test --package-path LifeOSKit --filter RemoteChatEngineTests`
Expected: FAIL, `cannot find 'RemoteChatEngine' in scope`.

- [ ] **Step 3: Implement the protocol**

```swift
// LifeOSKit/Sources/Insights/Chat/ChatEngine.swift
import Foundation

/// One turn of a conversation, as the thread sees it.
///
/// Deliberately smaller than `ChatWire.Message`: a caller assembling a
/// thread has no business knowing about tool call ids, which exist only
/// inside one engine's round loop.
public struct ChatTurnMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// What both chat tiers look like from the router's side.
///
/// The counterpart to `Engine`, which serves one-shot tasks. Kept separate
/// rather than overloaded onto it because the two have genuinely different
/// shapes: a task renders one prompt and decodes one typed output, while a
/// turn carries a thread and may run several rounds of tools before there
/// is any text at all.
public protocol ChatEngine: Sendable {
    func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply
}
```

- [ ] **Step 4: Move the on-device path**

```swift
// LifeOSKit/Sources/Insights/Chat/OnDeviceChatEngine.swift
import FoundationModels

/// Apple's on-device model, driving the rounds itself.
///
/// This is the body `AssistantTurn.run` used to be, moved without a change
/// in behaviour. A session is created per turn because the conversation's
/// memory lives in the thread we render, not in the session.
public struct OnDeviceChatEngine: ChatEngine {
    private let instructions: String

    public init(instructions: String) {
        self.instructions = instructions
    }

    public func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        let session = LanguageModelSession(
            tools: tools.map { SessionTool($0, invoker: invoker) },
            instructions: instructions + "\n\n" + ResponseStyle.conversation
        )
        let response = try await session.respond(to: Self.prompt(from: thread))
        return AssistantTurn.Reply(
            text: ResponseStyle.clean(response.content),
            toolSummaries: await invoker.toolSummaries()
        )
    }

    /// The thread, flattened. FoundationModels drives one prompt rather than
    /// a message array, so the history is rendered into it, which is what
    /// the calendar assistant already did before this type existed.
    static func prompt(from thread: [ChatTurnMessage]) -> String {
        guard let last = thread.last else { return "" }
        let history = thread.dropLast()
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")
        return history.isEmpty ? last.text : history + "\n\n" + last.text
    }
}
```

- [ ] **Step 5: Implement the round loop**

```swift
// LifeOSKit/Sources/Insights/Chat/RemoteChatEngine.swift
import Foundation
import FoundationModels

/// The cloud tier of the conversation.
///
/// The loop lives here, on the device, and not in the Edge Function. Every
/// tool reads device-local state through EventKit, HealthKit or SwiftData,
/// so a server-driven loop would have to call back into the phone. Keeping
/// the rounds here also means a tool result never travels anywhere except
/// back to the provider that asked for it.
public struct RemoteChatEngine: ChatEngine {
    private let baseURL: URL
    private let anonKey: String
    private let accessToken: @Sendable () -> String?
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// `transport` is injectable so the round loop can be tested without a
    /// network. It defaults to the shared session, which is what ships.
    public init(
        baseURL: URL, anonKey: String,
        accessToken: @escaping @Sendable () -> String?,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
            = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.transport = transport
    }

    public func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        guard let token = accessToken(), !token.isEmpty else {
            throw RemoteEngineError.notSignedIn
        }

        var messages = thread.map {
            ChatWire.Message(role: $0.role.rawValue, content: $0.text)
        }

        // Bounded by the invoker's own cap rather than a second number of
        // this file's invention. One extra round is allowed on top, for the
        // reply that comes after the last permitted tool call.
        for _ in 0...ToolInvoker.invocationLimit {
            let request = try ChatWire.request(
                baseURL: baseURL, anonKey: anonKey, accessToken: token,
                messages: messages, tools: tools
            )

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport(request)
            } catch {
                // Offline, DNS, timeout. Transient by nature.
                throw RemoteEngineError.unavailable
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch try ChatWire.reply(data: data, status: status) {
            case .text(let text):
                return AssistantTurn.Reply(
                    text: ResponseStyle.clean(text),
                    toolSummaries: await invoker.toolSummaries()
                )

            case .toolCalls(let calls):
                // The assistant turn that asked, so the thread we resend
                // reads back the way the provider produced it.
                messages.append(ChatWire.Message(
                    role: "assistant", content: "", toolCalls: calls
                ))
                for call in calls {
                    // Every call must be answered, even one whose arguments
                    // will not parse: a provider left waiting on a result
                    // that never arrives simply asks again, and the loop
                    // spends its remaining rounds on it.
                    let result: String
                    if let arguments = try? GeneratedContent(json: call.argumentsJSON) {
                        result = await invoker.invoke(name: call.name, arguments: arguments)
                    } else {
                        result = "The \(call.name) tool was given arguments that could not be read. Explain what happened rather than retrying."
                    }
                    messages.append(ChatWire.Message(
                        role: "tool", content: result, toolCallID: call.id
                    ))
                }
            }
        }

        // The loop ran out of rounds without the model committing to prose.
        // The invoker has already been returning its cap message for the
        // last few, so this is a model that will not stop; say so rather
        // than returning an empty bubble.
        return AssistantTurn.Reply(
            text: "That turned into more steps than I can take in one go. Try asking for one thing at a time.",
            toolSummaries: await invoker.toolSummaries()
        )
    }
}
```

Note: `GeneratedContent(json:)` is throwing, which is why the unparseable
case is written as its own branch rather than a `??` fallback: the fallback
would itself be throwing and would not compile. The branch still answers the
call, which is what keeps the provider from asking again.

- [ ] **Step 6: Run and watch it pass**

Run: `swift test --package-path LifeOSKit --filter RemoteChatEngineTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Insights/Chat/
git add LifeOSKit/Tests/InsightsTests/RemoteChatEngineTests.swift
git commit -m "feat(chat): run the tool loop against the cloud, on the device"
```

---

### Task 6: `AssistantTurn` becomes the router

**Files:**
- Modify: `LifeOSKit/Sources/Insights/AssistantTurn.swift`
- Test: `LifeOSKit/Tests/InsightsTests/AssistantTurnTests.swift`

**Interfaces:**
- Consumes: `ChatEngine`, `OnDeviceChatEngine`, `RemoteChatEngine`.
- Produces: `AssistantTurn.run(instructions:thread:tools:broker:remote:onDevice:availability:)`
  returning `AssistantTurn.Reply`. `AssistantTurn.Reply` keeps its current
  shape and initialiser exactly.

**The routing rules are `CoachRouter`'s, and they are not negotiable:**

1. Remote first when one is configured.
2. A refusal is never retried on the other tier. Re-routing a refused
   request to a second model to get the answer anyway is guardrail
   laundering, and `CoachRouter` already refuses to do it.
3. `.exhausted`, `.unavailable` and a thrown transport error fall back to
   the device, but only when `ModelAvailability` says the device can answer.
4. `.notSignedIn` falls back to the device too. A guest has no cloud tier
   and that is a normal state, not an error.

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/InsightsTests/AssistantTurnTests.swift
import Testing
import Foundation
@testable import Insights

private struct StubChatEngine: ChatEngine {
    let outcome: @Sendable () throws -> AssistantTurn.Reply

    func reply(
        to thread: [ChatTurnMessage], tools: [any CoachTool], invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        try outcome()
    }
}

@Suite struct AssistantTurnTests {

    private let thread = [ChatTurnMessage(role: .user, text: "how did I sleep?")]

    private func run(
        remote: (any ChatEngine)?,
        onDevice: any ChatEngine,
        availability: ModelAvailability = .available
    ) async throws -> AssistantTurn.Reply {
        try await AssistantTurn.run(
            thread: thread, tools: [], broker: ConfirmationBroker(),
            remote: remote, onDevice: onDevice, availability: { availability }
        )
    }

    private func reply(_ text: String) -> AssistantTurn.Reply {
        AssistantTurn.Reply(text: text, toolSummaries: [])
    }

    @Test func theCloudAnswersWhenItCan() async throws {
        let result = try await run(
            remote: StubChatEngine { self.reply("cloud") },
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "cloud")
    }

    @Test func theDeviceAnswersWhenTheCloudCannotBeReached() async throws {
        let result = try await run(
            remote: StubChatEngine { throw RemoteEngineError.unavailable },
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "device")
    }

    @Test func aSpentBudgetFallsBackRatherThanFailing() async throws {
        let result = try await run(
            remote: StubChatEngine { throw RemoteEngineError.exhausted },
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "device")
    }

    /// A guest has no cloud tier. That is a normal state, not a failure.
    @Test func aSignedOutUserIsServedByTheDevice() async throws {
        let result = try await run(
            remote: StubChatEngine { throw RemoteEngineError.notSignedIn },
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "device")
    }

    /// The rule CoachRouter already enforces for one-shot tasks: a second
    /// model is not a second opinion on a refusal, it is a way around one.
    @Test func aRefusalIsNeverRetriedOnTheOtherTier() async {
        await #expect(throws: RemoteEngineError.refused("Outside what I cover.")) {
            try await self.run(
                remote: StubChatEngine { throw RemoteEngineError.refused("Outside what I cover.") },
                onDevice: StubChatEngine { self.reply("device") }
            )
        }
    }

    @Test func withNoDeviceModelTheCloudFailureStands() async {
        await #expect(throws: RemoteEngineError.unavailable) {
            try await self.run(
                remote: StubChatEngine { throw RemoteEngineError.unavailable },
                onDevice: StubChatEngine { self.reply("device") },
                availability: .unavailablePermanently
            )
        }
    }

    @Test func withNoCloudConfiguredTheDeviceIsTheOnlyTier() async throws {
        let result = try await run(
            remote: nil,
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "device")
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `swift test --package-path LifeOSKit --filter AssistantTurnTests`
Expected: FAIL, no `run(thread:tools:broker:remote:onDevice:availability:)`.

- [ ] **Step 3: Rewrite `AssistantTurn`**

Replace the body of `LifeOSKit/Sources/Insights/AssistantTurn.swift`,
keeping `Reply` byte-identical:

```swift
import Foundation
import FoundationModels

/// One user turn of the tool-calling assistant, routed to whichever tier can
/// answer it.
///
/// This used to be a FoundationModels call and nothing else. The routing
/// rules below are `CoachRouter`'s, restated for the chat path rather than
/// reinvented: the cloud answers first because it is markedly better at the
/// questions this app gets asked, the device is what still works when the
/// cloud will not, and a refusal is never re-asked of a second model.
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
        instructions: String = "",
        thread: [ChatTurnMessage],
        tools: [any CoachTool],
        broker: ConfirmationBroker,
        remote: (any ChatEngine)?,
        onDevice: any ChatEngine? = nil,
        availability: @Sendable () -> ModelAvailability = {
            ModelAvailability.from(SystemLanguageModel.default.availability)
        }
    ) async throws -> Reply {
        let device = onDevice ?? OnDeviceChatEngine(instructions: instructions)

        // One invoker per turn: the cap and the activity chips are turn
        // state, and a shared one would carry a previous turn's count.
        let invoker = ToolInvoker(tools: tools, broker: broker)

        guard let remote else {
            return try await device.reply(to: thread, tools: tools, invoker: invoker)
        }

        do {
            return try await remote.reply(to: thread, tools: tools, invoker: invoker)
        } catch RemoteEngineError.refused(let reason) {
            // Never falls back. The model answered and declined; asking a
            // second model is not a second opinion, it is a way around one.
            throw RemoteEngineError.refused(reason)
        } catch {
            guard availability() == .available else { throw error }
            // A fresh invoker for the second attempt: the first one may have
            // spent rounds and collected chips for work whose reply never
            // arrived, and those must not be attributed to this answer.
            let retry = ToolInvoker(tools: tools, broker: broker)
            return try await device.reply(to: thread, tools: tools, invoker: retry)
        }
    }
}
```

- [ ] **Step 4: Run and watch it pass**

Run: `swift test --package-path LifeOSKit --filter AssistantTurnTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Run the whole package**

Run: `swift test --package-path LifeOSKit`
Expected: PASS. `AssistantViewModel` is in the app target and will not
compile against the new signature yet; that is Task 8 and does not affect
this run.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Insights/AssistantTurn.swift LifeOSKit/Tests/InsightsTests/AssistantTurnTests.swift
git commit -m "feat(chat): route a turn to the cloud first, the device after"
```

---

### Task 7: A style that can hold a conversation

**Files:**
- Modify: `LifeOSKit/Sources/Insights/ResponseStyle.swift`
- Test: `LifeOSKit/Tests/InsightsTests/ResponseStyleTests.swift`

**Interfaces:**
- Produces: `ResponseStyle.conversation: String`, consumed by
  `OnDeviceChatEngine` (Task 5).

**`ResponseStyle.instruction` and `clean(_:)` are not modified.** The
existing tests for both must still pass untouched. The one-shot tasks keep
the terse instruction; only chat gets the new one.

- [ ] **Step 1: Write the failing test**

Append to `ResponseStyleTests.swift`:

```swift
    /// The typography rules are the half that must not relax. A conversation
    /// is allowed to be warmer; it is not allowed to start emitting markdown.
    @Test func conversationKeepsEveryTypographyProhibition() {
        let text = ResponseStyle.conversation.lowercased()
        #expect(text.contains("markdown"))
        #expect(text.contains("em dash"))
        #expect(text.contains("figures"))
    }

    /// The three permissions this whole slice exists to grant. If these
    /// disappear, LIFO is a box that answers and stops again.
    @Test func conversationGrantsTheThreeThingsTheOneShotStyleForbids() {
        let text = ResponseStyle.conversation.lowercased()
        #expect(text.contains("earlier"))
        #expect(text.contains("one question"))
    }

    /// The instruction that serves cards has not been relaxed by accident.
    @Test func theOneShotInstructionStillSaysToStop() {
        #expect(ResponseStyle.instruction.contains("Answer, then stop."))
    }

    /// The cleaner is shared, so conversational output is held to the same
    /// output guarantees as everything else.
    @Test func conversationalOutputIsStillCleaned() {
        let dirty = "**Six hours.** That is short for you - worth a look."
        let clean = ResponseStyle.clean(dirty)
        #expect(!clean.contains("*"))
        #expect(!clean.contains(" - "))
    }
```

- [ ] **Step 2: Run and watch it fail**

Run: `swift test --package-path LifeOSKit --filter ResponseStyleTests`
Expected: FAIL, `type 'ResponseStyle' has no member 'conversation'`.

- [ ] **Step 3: Implement**

Add to `ResponseStyle`, leaving `instruction` and `clean(_:)` alone:

```swift
    /// How the assistant writes inside a conversation.
    ///
    /// Every typography prohibition from `instruction` is repeated verbatim,
    /// because those are about output the reader sees and they do not relax
    /// just because the exchange is longer. What is dropped is the sentence
    /// telling the model to answer and stop, which is the one that made the
    /// coach feel like a box rather than a person: it forbade referring to
    /// anything said earlier, which meant a follow-up could not be written
    /// even once the thread was there to write it from.
    ///
    /// The permissions are three, and deliberately counted. An assistant
    /// allowed to ask questions freely asks one after every answer, which
    /// reads as evasion rather than interest.
    public static let conversation = """
        Write in plain sentences, the way a person speaks.

        Never use markdown. No asterisks, no underscores, no backticks, no \
        hash headings, no bullet characters, no numbered lists. If you need to \
        list things, write them as a sentence separated by commas, or as \
        separate short sentences.

        Never use em dashes or en dashes. Use a comma, or start a new sentence.

        Never wrap words in quotation marks for emphasis. Apostrophes in \
        contractions are fine.

        Give figures as figures with their units. Never invent one, and never \
        round a number you were given into a different number.

        You are in a conversation, not filling in a form. You may refer back \
        to what was said earlier in this thread, and you may acknowledge what \
        the person told you before you answer.

        When you genuinely need something in order to answer well, ask one \
        question back. One, not a list, and not out of habit. If you can \
        answer without asking, answer.
        """
```

- [ ] **Step 4: Run and watch it pass**

Run: `swift test --package-path LifeOSKit --filter ResponseStyleTests`
Expected: PASS, including every pre-existing test in the suite.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/ResponseStyle.swift LifeOSKit/Tests/InsightsTests/ResponseStyleTests.swift
git commit -m "feat(chat): let LIFO write like it is in a conversation"
```

---

### Task 8: The coach gets a memory

**Files:**
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift`
- Modify: `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift:134`

**Interfaces:**
- Consumes: `AssistantTurn.run(instructions:thread:tools:broker:remote:onDevice:availability:)`,
  `RemoteChatEngine`, `ChatTurnMessage`, `ChatStore`.

**There is no test target for the app.** This task is verified by
`xcodebuild` and by the manual pass in Step 5. Do not create one.

**Two things to get right:**

1. The coach's conversation is its own. Give `CoachViewModel` a
   `conversationID` that it does not share with the calendar assistant, or
   the two threads interleave in one `ChatStore` and each sees the other's
   turns. `ChatStore.latestConversationID()` is global and is therefore the
   wrong thing to call here; generate and keep an id instead.
2. `AssistantViewModel` calls the old `AssistantTurn.run(instructions:prompt:tools:broker:)`
   signature at line 134. Update it to pass a thread and a remote engine.
   Its existing `prompt(for:)` already renders history into a string; keep
   that context prefix as the `instructions` and pass the conversation's
   turns as the thread rather than flattening them a second time.

- [ ] **Step 1: Give the coach a thread**

In `CoachViewModel`, add beside the existing stored properties:

```swift
    /// This screen's own conversation. Not `ChatStore.latestConversationID()`,
    /// which is global: the coach and the calendar assistant share one store,
    /// and reusing whichever id was written last would let each of them read
    /// the other's turns as its own history.
    private let conversationID = UUID()

    /// The cloud tier of the conversation, or nil when the project is not
    /// configured. Same shape and same reasoning as `router` above: the token
    /// is read per call because the session refreshes while the app runs.
    private let chatRemote: (any ChatEngine)? = {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey
        else { return nil }
        return RemoteChatEngine(baseURL: url, anonKey: key, accessToken: {
            KeychainAuthSessionStore().load()?.accessToken
        })
    }()
```

- [ ] **Step 2: Replace the one-shot call with a turn**

In `send(_:)`, replace the `router.run(AnswerTask(...))` call and its
`switch` with the block below. The context loading above it stays exactly
as it is: the bundle still becomes the instructions, so LIFO still sees the
metrics, and it now also sees the thread.

```swift
            let store = ChatStore(context: context)
            try? store.append(conversationID: conversationID, role: .user, text: question)

            let thread = ((try? store.recent(conversationID: conversationID)) ?? [])
                .map { ChatTurnMessage(role: $0.role == .user ? .user : .assistant,
                                       text: $0.text) }

            do {
                let reply = try await AssistantTurn.run(
                    instructions: """
                    You answer questions about one person's life: their health \
                    metrics, money, and life-sector scores.

                    Here is what their data shows:

                    \(bundle.promptLines(for: .offDevice))
                    """,
                    thread: thread,
                    tools: [],
                    broker: ConfirmationBroker(),
                    remote: chatRemote
                )
                try? store.append(conversationID: conversationID, role: .assistant,
                                  text: reply.text)
                answer = reply.text
                history.append(LifoTurn(question: question, answer: reply.text))
                phase = .answered
                status = "LIFO"
                speak(reply.text)
            } catch RemoteEngineError.refused(let reason) {
                fail(reason)
            } catch RemoteEngineError.exhausted {
                fail("That is today's thinking budget used up. It resets tomorrow.")
            } catch {
                if isSignedIn {
                    fail("LIFO could not reach the cloud just now. Try again in a moment.")
                } else {
                    fail("LIFO thinks on this device with Apple Intelligence. Turn it on in Settings, or sign in to think in the cloud.")
                    needsAppleIntelligence = true
                }
            }
```

`AnswerTask` and the `router` property stay in the file, still used by
nothing on this screen. Do not delete them in this task: `AnswerTask` is
covered by `CoachTaskTests` and by the server's back-compat test, and
removing it belongs to a cleanup commit rather than this one.

- [ ] **Step 3: Update the calendar assistant's call site**

In `AssistantViewModel.send()`, replace the `AssistantTurn.run` call:

```swift
            let thread = ((try? chat.recent(conversationID: conversationID)) ?? [])
                .map { ChatTurnMessage(role: $0.role == .user ? .user : .assistant,
                                       text: $0.text) }

            let remote: (any ChatEngine)? = {
                guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey
                else { return nil }
                return RemoteChatEngine(baseURL: url, anonKey: key, accessToken: {
                    KeychainAuthSessionStore().load()?.accessToken
                })
            }()

            let reply = try await AssistantTurn.run(
                instructions: CalendarAssistant.instructions(authorized: isAuthorized)
                    + "\n\n" + calendarContext(),
                thread: thread,
                tools: tools,
                broker: broker,
                remote: remote
            )
```

Rename the existing `prompt(for:)` to `calendarContext()`, drop its `text`
parameter and its trailing history rendering (the thread carries that now),
and have it return only the `CalendarAssistant.contextPrefix(...)` block.
The user's message is already the last turn of `thread`, because
`chat.append` runs above this.

- [ ] **Step 4: Build**

Run: `xcodebuild -project ./LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

Run: `swift test --package-path LifeOSKit`
Expected: PASS, full suite.

Run: `./scripts/check-typography.sh`
Expected: exit 0.

- [ ] **Step 5: Manual pass on the simulator**

Nothing below is covered by a test, and every one of them is a way this
slice can be shipped broken.

1. Open LIFO. Ask "how did I sleep last week?". Confirm an answer arrives.
2. Ask a follow-up that only makes sense with memory: "is that bad?".
   Confirm the reply is about sleep and not a request for clarification.
   **This is the acceptance test for the whole slice.**
3. Ask something off-scope, for example "write me a poem". Confirm LIFO
   declines and that the refusal is shown rather than silently answered by
   the on-device model.
4. Turn on Airplane Mode and ask a question. Confirm the on-device model
   answers, or that the Apple Intelligence message appears if the device
   cannot.
5. Open the calendar assistant. Ask "what is on today?". Confirm the
   activity chip still appears under the reply and the event cards still
   render.
6. In the calendar assistant, ask it to create an event. Confirm the
   confirmation card still appears and that declining it still works.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift
git commit -m "feat(coach): let LIFO remember the conversation it is in"
```

---

## Verification

After Task 8, all of the following must hold:

- `swift test --package-path LifeOSKit` passes in full.
- `deno test supabase/functions/_shared/lifo_test.ts` passes in full.
- `deno check supabase/functions/lifo-agent/index.ts` reports no errors.
- `xcodebuild ... build` reports BUILD SUCCEEDED.
- `./scripts/check-typography.sh` exits 0.
- The manual pass in Task 8 Step 5 has actually been run on a simulator,
  and step 2 of it, the follow-up question, actually worked.
