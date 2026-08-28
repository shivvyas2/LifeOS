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

    /// `preference` is the user's choice of tier, honoured here the way
    /// `CoachRouter.run` honours it for one-shot tasks. The calendar
    /// assistant obeys the same switch: it had no tier control of its own,
    /// and event titles and times now leave the device.
    ///
    /// `instructions` carries the user's own data, and it is carried per
    /// tier: whichever engine answers is handed the render meant for it.
    /// Both engines get one, which is the whole difference from the shape
    /// this used to have, where the parameter reached only the device and
    /// every cloud answer was produced with none of the user's data.
    public static func run(
        instructions: ChatInstructions = .none,
        thread: [ChatTurnMessage],
        tools: [any CoachTool],
        broker: ConfirmationBroker,
        remote: (any ChatEngine)?,
        onDevice: (any ChatEngine)? = nil,
        availability: @Sendable () -> ModelAvailability = {
            ModelAvailability.from(SystemLanguageModel.default.availability)
        },
        preference: @Sendable () -> TierPreference = { .current }
    ) async throws -> Reply {
        let device = onDevice ?? OnDeviceChatEngine()

        // One invoker per turn: the cap and the activity chips are turn
        // state, and a shared one would carry a previous turn's count.
        let invoker = ToolInvoker(tools: tools, broker: broker)

        guard let remote else {
            return try await device.reply(
                to: thread, instructions: instructions.onDevice,
                tools: tools, invoker: invoker
            )
        }

        // Read now rather than captured, the way `CoachRouter` reads it: the
        // switch can be flipped in Settings while this screen is still open.
        switch preference() {
        case .onDevice:
            // The device and nothing else. Someone whose Settings say
            // "nothing you ask ever leaves it" is owed exactly that, and a
            // cloud call made on their behalf is the promise broken rather
            // than a fallback.
            return try await device.reply(
                to: thread, instructions: instructions.onDevice,
                tools: tools, invoker: invoker
            )
        case .cloud:
            // No fallback, on purpose and identically to `CoachRouter`.
            // Someone who chose the stronger model wants to be told when it
            // did not answer, not quietly handed a weaker answer.
            return try await remote.reply(
                to: thread, instructions: instructions.cloud,
                tools: tools, invoker: invoker
            )
        case .automatic:
            break
        }

        do {
            return try await remote.reply(
                to: thread, instructions: instructions.cloud,
                tools: tools, invoker: invoker
            )
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
            return try await device.reply(
                to: thread, instructions: instructions.onDevice,
                tools: tools, invoker: retry
            )
        }
    }
}
