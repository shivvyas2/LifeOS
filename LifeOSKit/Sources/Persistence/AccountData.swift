import Foundation
import SwiftData

/// What a person can clear, and where each kind lives.
public enum DataCategory: String, CaseIterable, Codable, Sendable {
    case notes, habits, health, money, chats, messages

    public var title: String {
        switch self {
        case .notes: "Notes and journal"
        case .habits: "Habits and goals"
        case .health: "Health history"
        case .money: "Money history"
        case .chats: "AI chats"
        case .messages: "Messages"
        }
    }

    /// Whether the server holds rows for it, which must go first.
    public var hasServerRows: Bool { [.notes, .health, .messages].contains(self) }
}

/// Deletes this phone's copy of the chosen categories.
@MainActor
public struct LocalDataEraser {
    private let context: ModelContext
    private let defaults: UserDefaults

    public init(context: ModelContext, defaults: UserDefaults) {
        self.context = context
        self.defaults = defaults
    }

    public func erase(_ categories: Set<DataCategory>) throws {
        for category in DataCategory.allCases where categories.contains(category) {
            switch category {
            case .notes:
                try context.delete(model: NoteDocument.self)
                try context.delete(model: NoteFolder.self)
                try context.delete(model: NoteTask.self)
                try context.delete(model: NoteLink.self)
                // The next pull starts from nothing, not from a cursor past
                // rows that no longer exist.
                defaults.removeObject(forKey: "notes.sync.cursor")
            case .habits:
                try context.delete(model: PlanEntry.self)
                try context.delete(model: HabitTick.self)
            case .health:
                try context.delete(model: DailyMetrics.self)
                try context.delete(model: WorkoutRecord.self)
                try context.delete(model: SleepRecord.self)
                try context.delete(model: WhoopRawRecord.self)
            case .money:
                try context.delete(model: MoneyEntry.self)
                try context.delete(model: SpendBucket.self)
            case .chats:
                try context.delete(model: ChatMessage.self)
                defaults.removeObject(forKey: "coach.conversationID")
            case .messages:
                break   // nothing on the phone
            }
        }
        try context.save()
    }
}

/// Accounts signed out by a deletion request, whose stores stay on this
/// phone until the server confirms the deletion.
public struct PendingAccountWipe {
    private let defaults: UserDefaults
    private static let key = "accounts.pendingWipe"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var ids: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func add(_ id: String) {
        guard !ids.contains(id) else { return }
        defaults.set(ids + [id], forKey: Self.key)
    }

    public func remove(_ id: String) {
        defaults.set(ids.filter { $0 != id }, forKey: Self.key)
    }

    /// Of the accounts the server says are gone, the ones safe to wipe: never
    /// one still signed in on this phone, whose store may be open.
    public func wipeable(confirmedDeleted: [String], signedIn: Set<String>) -> [String] {
        confirmedDeleted.filter { !signedIn.contains($0) }
    }

    /// The account's store folder and defaults suite go; then it leaves the list.
    public func wipe(_ id: String, base: URL) throws {
        let scope = UserScope(id: id)
        let directory = scope.directory(base: base)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        UserDefaults(suiteName: scope.defaultsSuiteName)?.removePersistentDomain(forName: scope.defaultsSuiteName)
        UserDefaults.standard.removePersistentDomain(forName: scope.defaultsSuiteName)
        remove(id)
    }
}
