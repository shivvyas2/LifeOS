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
    /// Which model actually wrote the answer.
    ///
    /// Reported rather than inferred. The router's choice is not the whole
    /// story: an automatic turn falls back to the device when the cloud will
    /// not answer, so a screen that worked out the tier from the preference
    /// would name the wrong one exactly when it mattered — and this is what
    /// labels the "what was sent" disclosure, where being wrong is a claim
    /// about where somebody's data went.
    public enum Tier: String, Sendable, Equatable {
        case cloud, onDevice
    }

    public struct Reply: Sendable, Equatable {
        public let text: String
        public let toolSummaries: [String]
        public let tier: Tier

        public init(text: String, toolSummaries: [String], tier: Tier = .onDevice) {
            self.text = text
            self.toolSummaries = toolSummaries
            self.tier = tier
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
        preference: @Sendable () -> TierPreference = { .current },
        /// Handed the answer so far, whichever tier is writing it. Cumulative,
        /// so a screen assigns rather than appends and cannot end up holding
        /// half a sentence twice.
        onPartial: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Reply {
        let device = onDevice ?? OnDeviceChatEngine()

        // One invoker per turn: the cap and the activity chips are turn
        // state, and a shared one would carry a previous turn's count.
        let invoker = ToolInvoker(tools: tools, broker: broker)

        guard let remote else {
            return try await device.reply(
                to: thread, instructions: instructions.onDevice,
                tools: tools, invoker: invoker, onPartial: onPartial
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
                tools: tools, invoker: invoker, onPartial: onPartial
            )
        case .cloud:
            // No fallback, on purpose and identically to `CoachRouter`.
            // Someone who chose the stronger model wants to be told when it
            // did not answer, not quietly handed a weaker answer.
            return try await remote.reply(
                to: thread, instructions: instructions.cloud,
                tools: tools, invoker: invoker, onPartial: onPartial
            )
        case .automatic:
            break
        }

        do {
            return try await remote.reply(
                to: thread, instructions: instructions.cloud,
                tools: tools, invoker: invoker, onPartial: onPartial
            )
        } catch RemoteEngineError.refused(let reason) {
            // Never falls back. The model answered and declined; asking a
            // second model is not a second opinion, it is a way around one.
            throw RemoteEngineError.refused(reason)
        } catch {
            // A gated write the user already approved has already happened.
            // Retrying on the device starts a fresh invoker, so the first
            // attempt's tool summaries are gone from the transcript and the
            // device model is free to ask for the same create again. That is
            // a second card, in front of someone with no evidence the first
            // one landed, and two identical events when they say yes.
            // Surfacing the failure honestly beats re-attempting a side
            // effect.
            guard await invoker.didExecuteGatedWrite == false else { throw error }
            guard availability() == .available else { throw error }
            // A fresh invoker for the second attempt: the first one may have
            // spent rounds and collected chips for work whose reply never
            // arrived, and those must not be attributed to this answer.
            let retry = ToolInvoker(tools: tools, broker: broker)
            // Cleared first. The cloud attempt may have streamed a sentence or
            // two onto the screen before it failed, and leaving those there
            // while the device writes its own answer under them shows one
            // question answered twice.
            onPartial("")
            return try await device.reply(
                to: thread, instructions: instructions.onDevice,
                tools: tools, invoker: retry, onPartial: onPartial
            )
        }
    }
}
