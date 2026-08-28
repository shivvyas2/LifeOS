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
            instructions: "", tools: [], invoker: invoker([])
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
            instructions: "", tools: [tool], invoker: invoker([tool])
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
            instructions: "", tools: [tool], invoker: invoker([tool])
        )

        let body = try JSONSerialization.jsonObject(
            with: #require(transport.requests[1].httpBody)
        ) as? [String: Any]
        let messages = try #require(body?["messages"] as? [[String: Any]])
        #expect(messages.count == 3)

        // The assistant turn that asked for the tool must precede its
        // result, or the thread we resend is a `tool` message with no
        // preceding assistant message carrying that call id, which OpenAI
        // rejects outright.
        let askingMessage = messages[1]
        #expect(askingMessage["role"] as? String == "assistant")
        let toolCalls = try #require(askingMessage["tool_calls"] as? [[String: Any]])
        #expect(toolCalls.contains { $0["id"] as? String == "call_1" })

        let toolMessage = try #require(messages.last)
        #expect(toolMessage["role"] as? String == "tool")
        #expect(toolMessage["tool_call_id"] as? String == "call_1")
        #expect(toolMessage["content"] as? String == "3 events")
    }

    /// The subtlest branch in the file: arguments that will not parse must
    /// still be answered, or the provider is left waiting on a result that
    /// never arrives and simply asks again, burning the remaining rounds.
    @Test func unparseableArgumentsAreStillAnsweredRatherThanStranded() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let transport = ScriptedTransport([
            #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"not json"}]}"#,
            #"{"output":{"text":"Sorted."}}"#,
        ])

        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "what is on today?")],
            instructions: "", tools: [tool], invoker: invoker([tool])
        )

        let body = try JSONSerialization.jsonObject(
            with: #require(transport.requests[1].httpBody)
        ) as? [String: Any]
        let messages = try #require(body?["messages"] as? [[String: Any]])
        let toolMessage = try #require(messages.last)
        #expect(toolMessage["role"] as? String == "tool")
        #expect(toolMessage["tool_call_id"] as? String == "call_1")
        let content = try #require(toolMessage["content"] as? String)
        #expect(!content.isEmpty)
    }

    /// A model that will not stop calling tools must not be able to spend an
    /// unbounded number of rounds. The cap is ToolInvoker's, already six.
    @Test func aLoopThatWillNotConvergeIsBounded() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let call = #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"{\"start\":\"2026-08-28\"}"}]}"#
        let transport = ScriptedTransport(Array(repeating: call, count: 20))

        let reply = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "loop")],
            instructions: "", tools: [tool], invoker: invoker([tool])
        )

        // Exactly the cap plus one is guaranteed when the script never
        // converges: any fewer means the loop gave up early, any more means
        // it is unbounded.
        #expect(transport.requests.count == ToolInvoker.invocationLimit + 1)

        // The fall-through exists precisely to avoid an empty bubble when
        // the model will not stop; pin the text it is supposed to produce.
        #expect(reply.text == "That turned into more steps than I can take in one go. Try asking for one thing at a time.")
    }

    /// C1 on this side of the seam: the instructions the caller hands the
    /// engine are the user's own data, and they must reach the request.
    /// Before this, `reply` mapped the thread and sent nothing else, so
    /// every cloud answer was produced with none of it.
    @Test func theInstructionsTravelAsTheRequestContext() async throws {
        let transport = ScriptedTransport([#"{"output":{"text":"Six hours."}}"#])
        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "how did I sleep?")],
            instructions: "14-day baseline: sleep 6h20m",
            tools: [], invoker: invoker([])
        )
        let body = try JSONSerialization.jsonObject(
            with: #require(transport.requests[0].httpBody)
        ) as? [String: Any]
        #expect(body?["context"] as? String == "14-day baseline: sleep 6h20m")
    }

    /// The context has to survive the rounds too. A tool-calling turn that
    /// dropped it after the first request would answer the actual question,
    /// the one that comes after the tools, with no data at all.
    @Test func theContextIsRepeatedOnEveryRound() async throws {
        let log = ToolLog()
        let tool = RecordingTool(log: log)
        let transport = ScriptedTransport([
            #"{"tool_calls":[{"id":"call_1","name":"get_events","arguments":"{\"start\":\"2026-08-28\"}"}]}"#,
            #"{"output":{"text":"Three."}}"#,
        ])
        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "what is on today?")],
            instructions: "Today is Friday 28 August 2026.",
            tools: [tool], invoker: invoker([tool])
        )
        for request in transport.requests {
            let body = try JSONSerialization.jsonObject(
                with: #require(request.httpBody)
            ) as? [String: Any]
            #expect(body?["context"] as? String == "Today is Friday 28 August 2026.")
        }
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
                instructions: "", tools: [], invoker: self.invoker([])
            )
        }
    }

    /// The other half of the same guard. A session that exists but carries
    /// an empty token is a signed-out state wearing a signed-in shape, and
    /// sending it would spend a round trip to be told 401.
    @Test func anEmptyTokenIsNotSignedInEither() async {
        let transport = ScriptedTransport([])
        let engine = RemoteChatEngine(
            baseURL: base, anonKey: "k", accessToken: { "" },
            transport: { try await transport.send($0) }
        )
        await #expect(throws: RemoteEngineError.notSignedIn) {
            try await engine.reply(
                to: [ChatTurnMessage(role: .user, text: "hi")],
                instructions: "", tools: [], invoker: self.invoker([])
            )
        }
        #expect(transport.requests.isEmpty)
    }
}
