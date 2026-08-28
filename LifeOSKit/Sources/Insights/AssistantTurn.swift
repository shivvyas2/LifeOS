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
        onDevice: (any ChatEngine)? = nil,
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
