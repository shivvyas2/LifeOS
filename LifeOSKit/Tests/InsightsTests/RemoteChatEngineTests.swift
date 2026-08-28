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
