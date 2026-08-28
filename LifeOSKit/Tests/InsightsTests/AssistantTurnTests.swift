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
