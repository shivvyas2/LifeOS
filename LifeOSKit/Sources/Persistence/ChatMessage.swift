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
    /// The calendar events this reply was about, by id.
    ///
    /// Ids rather than the events themselves, on purpose. An event is a live
    /// thing that can be moved, shortened or deleted after the sentence about
    /// it was written, and a card showing what was true last Tuesday is worse
    /// than no card. These are re-resolved against the calendar when the
    /// conversation is reopened, so one that has since been deleted simply
    /// stops appearing.
    public let eventIDs: [UUID]
    public let createdAt: Date

    public init(
        id: UUID, conversationID: UUID, role: ChatRole,
        text: String, toolSummaries: [String],
        eventIDs: [UUID] = [], createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.toolSummaries = toolSummaries
        self.eventIDs = eventIDs
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
    /// Optional so an existing store migrates without a plan: a conversation
    /// that predates cards simply has none.
    public var eventIDsData: Data?
    public var createdAt: Date

    /// The ids, decoded. Stored as JSON rather than as a relationship because
    /// a chat message does not own an event and must not keep one alive.
    public var eventIDs: [UUID] {
        get {
            guard let eventIDsData, !eventIDsData.isEmpty,
                  let decoded = try? JSONDecoder().decode([UUID].self, from: eventIDsData)
            else { return [] }
            return decoded
        }
        set {
            eventIDsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

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
            text: text, toolSummaries: toolSummaries,
            eventIDs: eventIDs, createdAt: createdAt
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
        toolSummaries: [String] = [], eventIDs: [UUID] = [], at date: Date = .now
    ) throws -> ChatMessageSnapshot {
        let message = ChatMessage(
            conversationID: conversationID, role: role,
            text: text, toolSummaries: toolSummaries, createdAt: date
        )
        message.eventIDs = eventIDs
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

    /// Forgets one conversation; the others in the store stay.
    public func deleteConversation(_ id: UUID) throws {
        try context.delete(model: ChatMessage.self, where: #Predicate { $0.conversationID == id })
        try context.save()
    }

    public func latestConversationID() throws -> UUID? {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.conversationID
    }
}
