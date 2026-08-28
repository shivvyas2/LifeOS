import FoundationModels

/// Apple's on-device model, driving the rounds itself.
///
/// This is the body `AssistantTurn.run` used to be, moved without a change
/// in behaviour. A session is created per turn because the conversation's
/// memory lives in the thread we render, not in the session.
public struct OnDeviceChatEngine: ChatEngine {
    private let instructions: String

    public init(instructions: String) {
        self.instructions = instructions
    }

    public func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply {
        let session = LanguageModelSession(
            tools: tools.map { SessionTool($0, invoker: invoker) },
            instructions: instructions + "\n\n" + ResponseStyle.conversation
        )
        let response = try await session.respond(to: Self.prompt(from: thread))
        return AssistantTurn.Reply(
            text: ResponseStyle.clean(response.content),
            toolSummaries: await invoker.toolSummaries()
        )
    }

    /// The thread, flattened. FoundationModels drives one prompt rather than
    /// a message array, so the history is rendered into it, which is what
    /// the calendar assistant already did before this type existed.
    static func prompt(from thread: [ChatTurnMessage]) -> String {
        guard let last = thread.last else { return "" }
        let history = thread.dropLast()
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")
        return history.isEmpty ? last.text : history + "\n\n" + last.text
    }
}
