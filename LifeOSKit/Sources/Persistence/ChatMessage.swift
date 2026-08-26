import Foundation
import SwiftData

public enum ChatRole: String, Codable, Sendable {
    case user, assistant
}

/// Detached value form, safe to hand to a view.
public struct ChatMessageSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let role: ChatRole
    public let text: String
    /// Rendered as activity chips. Empty for plain replies.
    public let toolSummaries: [String]
    public let createdAt: Date

    public init(
        id: UUID, conversationID: UUID, role: ChatRole,
        text: String, toolSummaries: [String], createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.toolSummaries = toolSummaries
        self.createdAt = createdAt
    }
}

@Model
public final class ChatMessage {
    public var id: UUID
    public var conversationID: UUID
    /// Stored raw so the enum can gain cases without a migration.
    public var roleRaw: String
    public var text: String
    public var toolSummaries: [String]
    public var createdAt: Date

    public init(conversationID: UUID, role: ChatRole, text: String,
                toolSummaries: [String] = [], createdAt: Date = .now) {
        self.id = UUID()
        self.conversationID = conversationID
        self.roleRaw = role.rawValue
        self.text = text
        self.toolSummaries = toolSummaries
        self.createdAt = createdAt
    }

    public var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    public func snapshot() -> ChatMessageSnapshot {
        ChatMessageSnapshot(
            id: id, conversationID: conversationID, role: role,
            text: text, toolSummaries: toolSummaries, createdAt: createdAt
        )
    }
}

/// Conversation persistence. Local only: chat history never leaves the device.
@MainActor
public struct ChatStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// `at` exists for tests: appends in a tight loop can share a wall-clock
    /// timestamp, and the recency ordering must not be flaky over ties.
    @discardableResult
    public func append(
        conversationID: UUID, role: ChatRole, text: String,
        toolSummaries: [String] = [], at date: Date = .now
    ) throws -> ChatMessageSnapshot {
        let message = ChatMessage(
            conversationID: conversationID, role: role,
            text: text, toolSummaries: toolSummaries, createdAt: date
        )
        context.insert(message)
        try context.save()
        return message.snapshot()
    }

    /// The last `limit` messages of one conversation, oldest first, which is
    /// the order both a transcript render and a prompt want.
    public func recent(conversationID: UUID, limit: Int = 20) throws -> [ChatMessageSnapshot] {
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).reversed().map { $0.snapshot() }
    }

    public func latestConversationID() throws -> UUID? {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.conversationID
    }
}
