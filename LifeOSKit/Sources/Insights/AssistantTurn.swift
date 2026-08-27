import FoundationModels

/// One user turn of the tool-calling assistant, on-device.
///
/// A session is created per turn: the conversation's memory lives in the
/// prompt (rendered from the capped history), not in the session, so a turn
/// is stateless here the way `OnDeviceEngine` is for one-shot tasks. When a
/// remote engine exists this type grows a provider-neutral loop against
/// `Engine`; today FoundationModels drives the rounds itself.
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
        instructions: String,
        prompt: String,
        tools: [any CoachTool],
        broker: ConfirmationBroker
    ) async throws -> Reply {
        let invoker = ToolInvoker(tools: tools, broker: broker)
        let session = LanguageModelSession(
            tools: tools.map { SessionTool($0, invoker: invoker) },
            instructions: instructions + "\n\n" + ResponseStyle.instruction
        )
        let response = try await session.respond(to: prompt)
        return Reply(
            // Cleaned here rather than in the view, so every caller gets the
            // same text and a second surface cannot render the raw markdown
            // the instruction was supposed to prevent.
            text: ResponseStyle.clean(response.content),
            toolSummaries: await invoker.toolSummaries()
        )
    }
}
