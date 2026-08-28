// LifeOSKit/Tests/InsightsTests/AssistantTurnTests.swift
import Testing
import Foundation
@testable import Insights

private struct StubChatEngine: ChatEngine {
    let outcome: @Sendable () throws -> AssistantTurn.Reply

    func reply(
        to thread: [ChatTurnMessage], instructions: String,
        tools: [any CoachTool], invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        try outcome()
    }
}

/// Answers with whatever instructions it was handed, so a test can assert
/// which render reached which tier rather than only that one arrived.
private struct EchoingChatEngine: ChatEngine {
    let prefix: String

    func reply(
        to thread: [ChatTurnMessage], instructions: String,
        tools: [any CoachTool], invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        AssistantTurn.Reply(text: prefix + instructions, toolSummaries: [])
    }
}

@Suite struct AssistantTurnTests {

    private let thread = [ChatTurnMessage(role: .user, text: "how did I sleep?")]

    /// Every case states its preference rather than letting the default read
    /// this machine's own Settings, which would make the suite depend on
    /// whatever `UserDefaults.standard` happens to hold.
    private func run(
        remote: (any ChatEngine)?,
        onDevice: any ChatEngine,
        availability: ModelAvailability = .available,
        preference: TierPreference = .automatic
    ) async throws -> AssistantTurn.Reply {
        try await AssistantTurn.run(
            thread: thread, tools: [], broker: ConfirmationBroker(),
            remote: remote, onDevice: onDevice, availability: { availability },
            preference: { preference }
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

    /// C1. The cloud tier used to receive no instructions at all: the whole
    /// data bundle was built, handed to `run`, and used only to construct
    /// the on-device engine. On the default path for a signed-in user that
    /// meant every remote answer was produced with none of the user's data,
    /// while the server prompt told the model to cite only numbers it was
    /// given.
    @Test func theCloudTierIsHandedTheInstructions() async throws {
        let result = try await AssistantTurn.run(
            instructions: ChatInstructions(onDevice: "DEVICE", cloud: "CLOUD"),
            thread: thread, tools: [], broker: ConfirmationBroker(),
            remote: EchoingChatEngine(prefix: "cloud: "),
            onDevice: EchoingChatEngine(prefix: "device: "),
            availability: { .available }, preference: { .automatic }
        )
        #expect(result.text == "cloud: CLOUD")
    }

    /// C3. The two audiences do not carry the same fields, so each tier gets
    /// the render meant for it: the device sees the HRV series that never
    /// leaves the phone, the cloud sees the one built for travelling.
    @Test func eachTierIsHandedItsOwnRender() async throws {
        let result = try await AssistantTurn.run(
            instructions: ChatInstructions(onDevice: "DEVICE", cloud: "CLOUD"),
            thread: thread, tools: [], broker: ConfirmationBroker(),
            remote: StubChatEngine { throw RemoteEngineError.unavailable },
            onDevice: EchoingChatEngine(prefix: "device: "),
            availability: { .available }, preference: { .automatic }
        )
        #expect(result.text == "device: DEVICE")
    }

    @Test func withNoCloudConfiguredTheDeviceIsTheOnlyTier() async throws {
        let result = try await run(
            remote: nil,
            onDevice: StubChatEngine { self.reply("device") }
        )
        #expect(result.text == "device")
    }

    // C2. The preference was read by `CoachRouter` and by nothing on this
    // path, so a conversation ignored it entirely. These are `CoachRouter`'s
    // own semantics, restated for the chat tier.

    /// The promise in Settings is "nothing you ask ever leaves it". A cloud
    /// call made on this person's behalf breaks it, and the remote engine
    /// here fails the test outright rather than merely being unused.
    @Test func onDeviceMeansTheDeviceAndNothingElse() async throws {
        let result = try await run(
            remote: StubChatEngine {
                Issue.record("the cloud was asked despite the on-device preference")
                return self.reply("cloud")
            },
            onDevice: StubChatEngine { self.reply("device") },
            preference: .onDevice
        )
        #expect(result.text == "device")
    }

    /// Documented as having no fallback by design: someone who chose the
    /// stronger model wants to be told when it did not answer rather than
    /// quietly handed a weaker answer that looks the same.
    @Test func cloudNeverFallsBackToTheDevice() async {
        await #expect(throws: RemoteEngineError.unavailable) {
            try await self.run(
                remote: StubChatEngine { throw RemoteEngineError.unavailable },
                onDevice: StubChatEngine {
                    Issue.record("the device answered a cloud-only preference")
                    return self.reply("device")
                },
                preference: .cloud
            )
        }
    }

    @Test func automaticIsStillCloudFirstThenDevice() async throws {
        let cloud = try await run(
            remote: StubChatEngine { self.reply("cloud") },
            onDevice: StubChatEngine { self.reply("device") },
            preference: .automatic
        )
        #expect(cloud.text == "cloud")

        let device = try await run(
            remote: StubChatEngine { throw RemoteEngineError.unavailable },
            onDevice: StubChatEngine { self.reply("device") },
            preference: .automatic
        )
        #expect(device.text == "device")
    }

    /// The floor still wins over the preference, as it does in
    /// `CoachRouter`: with no cloud configured there is no second tier for
    /// `.cloud` to name, and the device answers rather than the turn failing.
    @Test func withNoCloudConfiguredThePreferenceCannotConjureOne() async throws {
        let result = try await run(
            remote: nil,
            onDevice: StubChatEngine { self.reply("device") },
            preference: .cloud
        )
        #expect(result.text == "device")
    }
}
