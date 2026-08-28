import FoundationModels

/// Apple's on-device model, driving the rounds itself.
///
/// The body came from `AssistantTurn.run`, but not unchanged: the input is a
/// thread rather than a single prompt, and the style appended is
/// `ResponseStyle.conversation` rather than `ResponseStyle.instruction`, so
/// the model may refer back to what was said earlier instead of answering and
/// stopping. Both are deliberate and both are the point of the move; the
/// note matters because prompt drift is this file's entire risk surface.
///
/// A session is created per turn because the conversation's memory lives in
/// the thread we render, not in the session.
public struct OnDeviceChatEngine: ChatEngine {

    public init() {}

    public func reply(
        to thread: [ChatTurnMessage],
        instructions: String,
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
