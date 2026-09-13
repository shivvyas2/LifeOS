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
        invoker: ToolInvoker,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> AssistantTurn.Reply {
        let session = LanguageModelSession(
            tools: tools.map { SessionTool($0, invoker: invoker) },
            instructions: instructions + "\n\n" + (CoachPresentation.isStructured(instructions) ? CoachPresentation.instruction : ResponseStyle.conversation)
        )
        // Streamed rather than awaited whole, so the device tier reaches the
        // screen the same way the cloud one does. FoundationModels yields
        // snapshots of the whole answer so far, which is exactly the shape
        // `onPartial` is defined in; there is nothing to accumulate here.
        var latest = ""
        let stream = session.streamResponse(to: Self.prompt(from: thread))
        for try await snapshot in stream {
            latest = snapshot.content
            // Cleaned on the way past, not only at the end: the model emits
            // markdown mid-sentence and a screen showing raw asterisks for a
            // second before they vanish reads as a rendering bug.
            onPartial(CoachPresentation.clean(latest, instructions: instructions))
        }
        return AssistantTurn.Reply(
            text: CoachPresentation.clean(latest, instructions: instructions),
            toolSummaries: await invoker.toolSummaries(),
            tier: .onDevice
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
