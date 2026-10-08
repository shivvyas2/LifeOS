import Foundation
import SwiftData

// Shared projects, cached on the phone and synced with the server like notes.
// Every stored property is optional or defaulted: an installed store must
// open after these models are added.

@Model
public final class ProjectRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var scope: String = ""
    public var startsOn: Date?
    public var endsOn: Date?
    public var colour: String = "tomato"
    public var ownerID: UUID?
    public var repo: String?
    public var archivedAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, scope: String, colour: String, ownerID: UUID?) {
        self.id = id; self.name = name; self.scope = scope; self.colour = colour; self.ownerID = ownerID
    }
}

@Model
public final class ProjectMemberRecord {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    public var userID: UUID = UUID()
    public var role: String = "member"
    public var addedAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    /// Set when removed here and not yet pushed; the push deletes the row.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, userID: UUID, role: String) {
        self.id = id; self.projectID = projectID; self.userID = userID; self.role = role
    }
}

@Model
public final class MilestoneRecord {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    public var title: String = ""
    public var dueOn: Date?
    public var position: Int = 0
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, title: String, position: Int) {
        self.id = id; self.projectID = projectID; self.title = title; self.position = position
    }
}

@Model
public final class ProjectTaskRecord {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    public var milestoneID: UUID?
    public var featureID: UUID?
    public var title: String = ""
    public var notes: String = ""
    public var status: String = "todo"
    public var ownerID: UUID?
    public var dueOn: Date?
    public var startsAt: Date?
    public var endsAt: Date?
    public var position: Int = 0
    public var doneAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, title: String, position: Int) {
        self.id = id; self.projectID = projectID; self.title = title; self.position = position
    }
}

@Model
public final class FeatureRecord {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    public var milestoneID: UUID?
    public var title: String = ""
    public var note: String = ""
    public var position: Int = 0
    public var branch: String?
    /// False once someone unlinks the branch by hand; auto-linking then
    /// leaves the feature alone until a branch is linked by hand again.
    public var autoLink: Bool = true
    public var stage: String = "planned"
    public var stageDetail: String = ""
    public var prNumber: Int?
    public var stageCheckedAt: Date?
    public var updatedAt: Date = Date.now
    public var syncedAt: Date?
    public var deletedAt: Date?

    public init(id: UUID = UUID(), projectID: UUID, title: String, position: Int) {
        self.id = id; self.projectID = projectID; self.title = title; self.position = position
    }
}

// MARK: - Snapshots: what screens read

public struct ProjectSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let scope: String
    public let startsOn: Date?
    public let endsOn: Date?
    public let colour: String
    public let ownerID: UUID?
    public let repo: String?
    public let isArchived: Bool
    public let done: Int
    public let total: Int
    public let nextMilestone: String?
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

public struct ProjectTaskSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let projectName: String
    public let colour: String
    public let milestoneID: UUID?
    public let featureID: UUID?
    public let title: String
    public let notes: String
    public let status: ProjectStatus
    public let ownerID: UUID?
    public let dueOn: Date?
    public let startsAt: Date?
    public let endsAt: Date?
    public let position: Int
    public let doneAt: Date?
}

public struct MilestoneSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let title: String
    public let dueOn: Date?
    public let position: Int
    public let done: Int
    public let total: Int
}

public struct FeatureSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let milestoneID: UUID?
    public let title: String
    public let note: String
    public let position: Int
    public let branch: String?
    public let autoLink: Bool
    public let stage: FeatureStage
    public let stageDetail: String
    public let prNumber: Int?
    public let stageCheckedAt: Date?
    public let openTasks: Int
    public let doneTasks: Int
}

public struct ProjectMemberSnapshot: Identifiable, Equatable, Sendable {
    public var id: UUID { userID }
    public let rowID: UUID
    public let userID: UUID
    public let role: String
}
