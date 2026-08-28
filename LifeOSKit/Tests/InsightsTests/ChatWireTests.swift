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

    /// The whole of C1 on the wire. The instructions are the user's data,
    /// and if they do not appear in the body the cloud model is answering
    /// with none of it while being told to cite only what it was given.
    @Test func theContextTravelsInItsOwnField() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [ChatWire.Message(role: "user", content: "how did I sleep?")],
            tools: [], context: "14-day baseline: sleep 6h20m"
        )
        let body = try body(request)
        #expect(body["context"] as? String == "14-day baseline: sleep 6h20m")

        // And never as a message the client wrote. A client-authored system
        // message would land behind the server's guardrail, which is the
        // injection this field exists to make unnecessary.
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(!messages.contains { $0["role"] as? String == "system" })
    }

    @Test func noContextMeansTheKeyIsAbsentRatherThanEmpty() throws {
        let request = try ChatWire.request(
            baseURL: base, anonKey: "k", accessToken: "t",
            messages: [ChatWire.Message(role: "user", content: "hi")], tools: []
        )
        #expect(try body(request)["context"] == nil)
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
