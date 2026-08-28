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

/// The instructions a turn is answered with, per tier.
///
/// Two strings rather than one because the two tiers are not owed the same
/// render. `MetricsDigest.Audience` exists precisely to keep the raw Whoop
/// series on the phone: `.onDevice` carries HRV, SpO2, skin temperature and
/// respiratory rate, `.offDevice` does not and carries a transaction list
/// instead. A single string would have to pick one, and whichever it picked
/// would be wrong on the other tier.
///
/// Callers with nothing tier-specific to say use `init(_:)` and both tiers
/// get the same text.
public struct ChatInstructions: Sendable, Equatable {
    /// What the on-device engine is instructed with. May name anything,
    /// including data that must not leave the phone.
    public let onDevice: String
    /// What the cloud engine is instructed with. This one travels.
    public let cloud: String

    public init(onDevice: String, cloud: String) {
        self.onDevice = onDevice
        self.cloud = cloud
    }

    public init(_ shared: String) {
        self.init(onDevice: shared, cloud: shared)
    }

    public static let none = ChatInstructions("")
}

/// What both chat tiers look like from the router's side.
///
/// The counterpart to `Engine`, which serves one-shot tasks. Kept separate
/// rather than overloaded onto it because the two have genuinely different
/// shapes: a task renders one prompt and decodes one typed output, while a
/// turn carries a thread and may run several rounds of tools before there
/// is any text at all.
///
/// `instructions` is a parameter rather than engine state so the router can
/// hand each tier its own render of the same context. An engine built once
/// and reused across turns would otherwise be stuck with whatever the first
/// turn was told.
public protocol ChatEngine: Sendable {
    func reply(
        to thread: [ChatTurnMessage],
        instructions: String,
        tools: [any CoachTool],
        invoker: ToolInvoker
    ) async throws -> AssistantTurn.Reply
}
