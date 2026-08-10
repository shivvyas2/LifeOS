import Foundation
import SwiftData

/// What a plan entry *is*. One discriminator rather than four near-identical
/// models: a goal, a habit, a note and a content item differ in which fields
/// they use, not in shape. This is what makes the set block-ready — a renderer
/// can lay out any entry without knowing which feature produced it.
public enum PlanKind: String, Codable, Sendable, CaseIterable {
    case goal, habit, note, content, journal
}

public enum PlanStatus: String, Codable, Sendable, CaseIterable {
    case todo, inProgress, done, blocked, scheduled

    public var title: String {
        switch self {
        case .todo:       "To do"
        case .inProgress: "In progress"
        case .done:       "Done"
        case .blocked:    "Blocked"
        case .scheduled:  "Scheduled"
        }
    }
}

/// The one shape every plan surface renders. A future block engine consumes
/// `PlanItemSnapshot` values and needs to know nothing about goals or habits.
public protocol PlanItem: Sendable {
    var id: UUID { get }
    var kind: PlanKind { get }
    var title: String { get }
    var detail: String? { get }
    var status: PlanStatus { get }
    var sortOrder: Int { get }
    var dueDate: Date? { get }
    /// 0...1 when the entry tracks completion, nil when it does not.
    var fraction: Double? { get }
}

/// Detached value form — safe to hand to a view, and the unit a block renderer
/// would lay out.
public struct PlanItemSnapshot: PlanItem, Equatable, Identifiable {
    public let id: UUID
    public let kind: PlanKind
    public let title: String
    public let detail: String?
    public let status: PlanStatus
    public let sortOrder: Int
    public let dueDate: Date?
    public let fraction: Double?
    /// Goal milestones — "3/4 milestones". Nil when the entry has none.
    public let progressValue: Double?
    public let progressTarget: Double?
    /// Recent completion history, most-recent-last. Habits only.
    public let recentTicks: [Bool]

    public init(
        id: UUID, kind: PlanKind, title: String, detail: String? = nil,
        status: PlanStatus = .todo, sortOrder: Int = 0, dueDate: Date? = nil,
        progressValue: Double? = nil, progressTarget: Double? = nil,
        recentTicks: [Bool] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.sortOrder = sortOrder
        self.dueDate = dueDate
        self.progressValue = progressValue
        self.progressTarget = progressTarget
        self.recentTicks = recentTicks
        if let progressValue, let progressTarget, progressTarget > 0 {
            self.fraction = min(max(progressValue / progressTarget, 0), 1)
        } else {
            self.fraction = nil
        }
    }
}

@Model
public final class PlanEntry {
    public var id: UUID
    public var kindRaw: String
    public var title: String
    public var detail: String?
    public var statusRaw: String
    public var sortOrder: Int
    public var dueDate: Date?
    public var progressValue: Double?
    public var progressTarget: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        kind: PlanKind,
        title: String,
        detail: String? = nil,
        status: PlanStatus = .todo,
        sortOrder: Int = 0,
        dueDate: Date? = nil,
        progressValue: Double? = nil,
        progressTarget: Double? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.detail = detail
        self.statusRaw = status.rawValue
        self.sortOrder = sortOrder
        self.dueDate = dueDate
        self.progressValue = progressValue
        self.progressTarget = progressTarget
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Stored raw so the enum can gain cases without a migration.
    public var kind: PlanKind {
        get { PlanKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    public var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    public func snapshot(recentTicks: [Bool] = []) -> PlanItemSnapshot {
        PlanItemSnapshot(
            id: id, kind: kind, title: title, detail: detail, status: status,
            sortOrder: sortOrder, dueDate: dueDate,
            progressValue: progressValue, progressTarget: progressTarget,
            recentTicks: recentTicks
        )
    }
}

/// One completion of a habit on one day. Separate from `PlanEntry` because a
/// habit's history is a set of days, not a field — and it lets the existing dot
/// grid render a habit exactly like the Today grid.
@Model
public final class HabitTick {
    public var entryID: UUID
    /// Always `Calendar.startOfDay`.
    public var date: Date

    public init(entryID: UUID, date: Date) {
        self.entryID = entryID
        self.date = date
    }
}
