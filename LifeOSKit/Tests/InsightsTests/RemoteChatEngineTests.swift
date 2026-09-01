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

/// Plays back a scripted event stream, so the streamed path can be driven
/// without a network exactly as the round loop can.
private final class ScriptedStream: @unchecked Sendable {
    private let lock = NSLock()
    private let lines: [String]
    private let status: Int
    private(set) var requests: [URLRequest] = []

    /// `lines` are whole SSE lines, blank separators included, because that is
    /// what a line-splitting reader is handed and a test that skips them is
    /// not testing the reader that ships.
    init(lines: [String], status: Int = 200) {
        self.lines = lines
        self.status = status
    }

    /// The deltas, wrapped as the server wraps them.
    static func text(_ pieces: [String]) -> ScriptedStream {
        var lines: [String] = []
        for piece in pieces {
            lines.append("data: {\"delta\": \(jsonString(piece))}")
            lines.append("")
        }
        lines.append("data: [DONE]")
        lines.append("")
        return ScriptedStream(lines: lines)
    }

    private static func jsonString(_ value: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: [value]), encoding: .utf8)!
            .dropFirst().dropLast().description
    }

    func send(_ request: URLRequest) async throws
        -> (RemoteChatEngine.LineStream, URLResponse) {
        lock.withLock { requests.append(request) }
        let scripted = lines
        let stream = RemoteChatEngine.LineStream { continuation in
            for line in scripted { continuation.yield(line) }
            continuation.finish()
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (stream, response as URLResponse)
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

    private func engine(_ stream: ScriptedStream) -> RemoteChatEngine {
        RemoteChatEngine(
            baseURL: base, anonKey: "k", accessToken: { "jwt" },
            // Deliberately fatal: a turn with no tools must take the streamed
            // path, and a test that silently fell back to the round loop would
            // pass while the shipping behaviour changed.
            transport: { _ in fatalError("a no-tool turn must stream") },
            streamTransport: { try await stream.send($0) }
        )
    }

    private func invoker(_ tools: [any CoachTool]) -> ToolInvoker {
        ToolInvoker(tools: tools, broker: ConfirmationBroker())
    }

    @Test func aPlainReplyComesBackAsText() async throws {
        let stream = ScriptedStream.text(["Six ", "hours."])
        let reply = try await engine(stream).reply(
            to: [ChatTurnMessage(role: .user, text: "how did I sleep?")],
            instructions: "", tools: [], invoker: invoker([])
        )
        #expect(reply.text == "Six hours.")
        #expect(reply.toolSummaries.isEmpty)
    }

    /// The point of the stream: the caller sees the answer being written,
    /// not only the finished thing.
    @Test func theAnswerArrivesInPiecesAndEachOneIsTheWholeOfItSoFar() async throws {
        let seen = Partials()
        let stream = ScriptedStream.text(["Six ", "hours ", "on average."])
        let reply = try await engine(stream).reply(
            to: [ChatTurnMessage(role: .user, text: "how did I sleep?")],
            instructions: "", tools: [], invoker: invoker([]),
            onPartial: { text in seen.append(text) }
        )
        // Cumulative, never incremental: a screen assigns what it is handed,
        // so each one has to stand alone as the answer so far.
        #expect(seen.values == ["Six", "Six hours", "Six hours on average."])
        #expect(reply.text == "Six hours on average.")
    }

    /// A turn with no tools asks for a stream, and one with tools does not.
    @Test func onlyAToollessTurnAsksForAStream() async throws {
        let stream = ScriptedStream.text(["ok"])
        _ = try await engine(stream).reply(
            to: [ChatTurnMessage(role: .user, text: "hi")],
            instructions: "", tools: [], invoker: invoker([])
        )
        let streamed = try JSONSerialization.jsonObject(
            with: #require(stream.requests[0].httpBody)
        ) as? [String: Any]
        #expect(streamed?["stream"] as? Bool == true)

        let tool = RecordingTool(log: ToolLog())
        let transport = ScriptedTransport([#"{"output":{"text":"done"}}"#])
        _ = try await engine(transport).reply(
            to: [ChatTurnMessage(role: .user, text: "hi")],
            instructions: "", tools: [tool], invoker: invoker([tool])
        )
        let looped = try JSONSerialization.jsonObject(
            with: #require(transport.requests[0].httpBody)
        ) as? [String: Any]
        #expect(looped?["stream"] == nil)
    }

    /// A failure still arrives as an ordinary body with a status on it, and
    /// must be classified the same way whichever path read it.
    @Test func aSpentBudgetIsStillTheBudgetOnTheStreamedPath() async throws {
        let stream = ScriptedStream(lines: [#"{"error":"exhausted"}"#], status: 429)
        await #expect(throws: RemoteEngineError.exhausted) {
            try await engine(stream).reply(
                to: [ChatTurnMessage(role: .user, text: "hi")],
                instructions: "", tools: [], invoker: invoker([])
            )
        }
    }

    /// A refusal travels inside the stream rather than as a status, because
    /// by the time the model declines the response is already a 200.
    @Test func aRefusalInsideTheStreamIsARefusal() async throws {
        let stream = ScriptedStream(lines: [
            #"data: {"error":"refused","message":"That is outside what I can help with."}"#,
            "",
            "data: [DONE]",
            "",
        ])
        await #expect(throws: RemoteEngineError.refused("That is outside what I can help with.")) {
            try await engine(stream).reply(
                to: [ChatTurnMessage(role: .user, text: "write me a poem")],
                instructions: "", tools: [], invoker: invoker([])
            )
        }
    }

    /// An empty bubble is not an answer. A 200 that carried no text is the
    /// server having gone wrong, which is what a retry is for.
    @Test func aStreamThatSaidNothingIsUnavailableRatherThanAnEmptyAnswer() async throws {
        let stream = ScriptedStream(lines: ["data: [DONE]", ""])
        await #expect(throws: RemoteEngineError.unavailable) {
            try await engine(stream).reply(
                to: [ChatTurnMessage(role: .user, text: "hi")],
                instructions: "", tools: [], invoker: invoker([])
            )
        }
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
        let stream = ScriptedStream.text(["Six hours."])
        _ = try await engine(stream).reply(
            to: [ChatTurnMessage(role: .user, text: "how did I sleep?")],
            instructions: "14-day baseline: sleep 6h20m",
            tools: [], invoker: invoker([])
        )
        let body = try JSONSerialization.jsonObject(
            with: #require(stream.requests[0].httpBody)
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


/// Collects what `onPartial` was handed.
///
/// A lock rather than an actor: the callback is synchronous, and hopping onto
/// an actor to record each one would let the assertion run before the last
/// hop landed — which is a race in the test, not in the thing being tested.
private final class Partials: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func append(_ text: String) { lock.withLock { storage.append(text) } }
}
