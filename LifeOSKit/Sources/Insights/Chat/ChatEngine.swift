import Foundation

/// One turn of a conversation, as the thread sees it.
///
/// Deliberately smaller than `ChatWire.Message`: a caller assembling a
/// thread has no business knowing about tool call ids, which exist only
/// inside one engine's round loop.
public struct ChatTurnMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// What both chat tiers look like from the router's side.
///
/// The counterpart to `Engine`, which serves one-shot tasks. Kept separate
/// rather than overloaded onto it because the two have genuinely different
/// shapes: a task renders one prompt and decodes one typed output, while a
/// turn carries a thread and may run several rounds of tools before there
/// is any text at all.
public protocol ChatEngine: Sendable {
    func reply(
        to thread: [ChatTurnMessage],
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply
}
