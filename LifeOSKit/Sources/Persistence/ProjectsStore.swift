import Foundation
import SwiftData

/// Reads and writes for projects on this phone. Every write stamps
/// `updatedAt`, which is what makes a row pending for the next push.
@MainActor
public struct ProjectsStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: Reads

    public func projects(includeArchived: Bool = false) throws -> [ProjectSnapshot] {
        let rows = try context.fetch(FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { $0.deletedAt == nil && (includeArchived || $0.archivedAt == nil) }
        let tasks = try liveTasks()
        let milestones = try liveMilestones()
        return rows.map { row in
            let mine = tasks.filter { $0.projectID == row.id }
            let progress = ProjectProgress.of(mine.map { ProjectStatus(rawValue: $0.status) ?? .todo })
            let next = milestones.filter { $0.projectID == row.id }
                .sorted { $0.position < $1.position }
                .first { milestone in
                    let theirs = mine.filter { $0.milestoneID == milestone.id }
                    return theirs.isEmpty || theirs.contains { $0.status != ProjectStatus.done.rawValue }
                }?.title
            return ProjectSnapshot(id: row.id, name: row.name, scope: row.scope, startsOn: row.startsOn,
                                   endsOn: row.endsOn, colour: row.colour, ownerID: row.ownerID, repo: row.repo,
                                   isArchived: row.archivedAt != nil, done: progress.done, total: progress.total,
                                   nextMilestone: next)
        }
    }

    public func project(id: UUID) throws -> ProjectSnapshot? {
        try projects(includeArchived: true).first { $0.id == id }
    }

    public func tasks(projectID: UUID) throws -> [ProjectTaskSnapshot] {
        let projects = try projectIndex()
        return try liveTasks().filter { $0.projectID == projectID }
            .sorted { (ProjectStatus(rawValue: $0.status) ?? .todo, $0.position)
                    < (ProjectStatus(rawValue: $1.status) ?? .todo, $1.position) }
            .compactMap { snapshot($0, projects: projects) }
    }

    public func milestones(projectID: UUID) throws -> [MilestoneSnapshot] {
        let tasks = try liveTasks().filter { $0.projectID == projectID }
        return try liveMilestones().filter { $0.projectID == projectID }
            .sorted { $0.position < $1.position }
            .map { row in
                let theirs = tasks.filter { $0.milestoneID == row.id }
                let progress = ProjectProgress.of(theirs.map { ProjectStatus(rawValue: $0.status) ?? .todo })
                return MilestoneSnapshot(id: row.id, projectID: row.projectID, title: row.title, dueOn: row.dueOn,
                                         position: row.position, done: progress.done, total: progress.total)
            }
    }

    public func features(projectID: UUID) throws -> [FeatureSnapshot] {
        let tasks = try liveTasks().filter { $0.projectID == projectID }
        return try liveFeatures().filter { $0.projectID == projectID }
            .sorted { $0.position < $1.position }
            .map { snapshot($0, tasks: tasks) }
    }

    public func feature(id: UUID) throws -> FeatureSnapshot? {
        guard let row = try liveFeatures().first(where: { $0.id == id }) else { return nil }
        return snapshot(row, tasks: try liveTasks().filter { $0.projectID == row.projectID })
    }

    public func featureProgress(projectID: UUID) throws -> FeatureProgress {
        FeatureProgress.of(try liveFeatures().filter { $0.projectID == projectID }
            .map { FeatureStage(rawValue: $0.stage) ?? .planned })
    }

    public func members(projectID: UUID) throws -> [ProjectMemberSnapshot] {
        try context.fetch(FetchDescriptor<ProjectMemberRecord>(sortBy: [SortDescriptor(\.addedAt)]))
            .filter { $0.projectID == projectID && $0.deletedAt == nil }
            .map { ProjectMemberSnapshot(rowID: $0.id, userID: $0.userID, role: $0.role) }
    }

    /// Open tasks owned by `userID`, due that day or with a time block that
    /// starts that day, across every live project.
    public func myTasks(userID: UUID, on day: Date) throws -> [ProjectTaskSnapshot] {
        let projects = try projectIndex()
        return try liveTasks()
            .filter { task in
                guard task.ownerID == userID, task.status != ProjectStatus.done.rawValue,
                      projects[task.projectID] != nil else { return false }
                if let due = task.dueOn, calendar.isDate(due, inSameDayAs: day) { return true }
                if let start = task.startsAt, calendar.isDate(start, inSameDayAs: day) { return true }
                return false
            }
            .sorted { ($0.startsAt ?? $0.dueOn ?? .distantFuture) < ($1.startsAt ?? $1.dueOn ?? .distantFuture) }
            .compactMap { snapshot($0, projects: projects) }
    }

    /// Tasks done per day over the last year, for the contribution grid
    /// when GitHub is not connected.
    public func completedPerDay(endingOn day: Date, days: Int = 371) throws -> [Int] {
        let end = calendar.startOfDay(for: day)
        var counts = Array(repeating: 0, count: days)
        for task in try liveTasks() {
            guard let done = task.doneAt else { continue }
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: done), to: end).day ?? -1
            if offset >= 0 && offset < days { counts[days - 1 - offset] += 1 }
        }
        return counts
    }

    // MARK: Writes

    @discardableResult
    public func createProject(name: String, scope: String, colour: String, ownerID: UUID,
                              startsOn: Date? = nil, endsOn: Date? = nil, repo: String? = nil) throws -> UUID {
        let project = ProjectRecord(name: Self.limit(name, 60), scope: Self.limit(scope, 240),
                                    colour: colour, ownerID: ownerID)
        project.startsOn = startsOn
        project.endsOn = endsOn
        project.repo = repo
        context.insert(project)
        context.insert(ProjectMemberRecord(projectID: project.id, userID: ownerID, role: "owner"))
        try context.save()
        return project.id
    }

    public func updateProject(id: UUID, name: String? = nil, scope: String? = nil, colour: String? = nil,
                              startsOn: Date?? = nil, endsOn: Date?? = nil, repo: String?? = nil,
                              archived: Bool? = nil) throws {
        guard let row = try projectRecord(id) else { return }
        if let name { row.name = Self.limit(name, 60) }
        if let scope { row.scope = Self.limit(scope, 240) }
        if let colour { row.colour = colour }
        if let startsOn { row.startsOn = startsOn }
        if let endsOn { row.endsOn = endsOn }
        if let repo { row.repo = repo }
        if let archived { row.archivedAt = archived ? .now : nil }
        row.updatedAt = .now
        try context.save()
    }

    @discardableResult
    public func createTask(projectID: UUID, title: String, status: ProjectStatus = .todo) throws -> UUID {
        let position = try liveTasks().filter { $0.projectID == projectID && $0.status == status.rawValue }.count
        let task = ProjectTaskRecord(projectID: projectID, title: Self.limit(title, 120), position: position)
        task.status = status.rawValue
        if status == .done { task.doneAt = .now }
        context.insert(task)
        try context.save()
        return task.id
    }

    public func updateTask(id: UUID, title: String? = nil, notes: String? = nil, ownerID: UUID?? = nil,
                           milestoneID: UUID?? = nil, featureID: UUID?? = nil, dueOn: Date?? = nil,
                           startsAt: Date?? = nil, endsAt: Date?? = nil) throws {
        guard let row = try taskRecord(id) else { return }
        if let title { row.title = Self.limit(title, 120) }
        if let notes { row.notes = Self.limit(notes, 2000) }
        if let ownerID { row.ownerID = ownerID }
        if let milestoneID { row.milestoneID = milestoneID }
        if let featureID { row.featureID = featureID }
        if let dueOn { row.dueOn = dueOn }
        if let startsAt { row.startsAt = startsAt }
        if let endsAt { row.endsAt = endsAt }
        // The server requires an end after the start.
        if let start = row.startsAt, let end = row.endsAt, end <= start {
            row.endsAt = start.addingTimeInterval(30 * 60)
        }
        row.updatedAt = .now
        try context.save()
    }

    /// Through `BoardMove`, so both columns renumber and `doneAt` follows.
    public func moveTask(id: UUID, to status: ProjectStatus, at index: Int) throws {
        guard let moving = try taskRecord(id) else { return }
        let rows = try liveTasks().filter { $0.projectID == moving.projectID }
        let cards = rows.map { BoardCard(id: $0.id, status: ProjectStatus(rawValue: $0.status) ?? .todo,
                                         position: $0.position, doneAt: $0.doneAt) }
        let moved = BoardMove.move(id, to: status, at: index, in: cards, now: .now)
        for card in moved {
            guard let row = rows.first(where: { $0.id == card.id }) else { continue }
            let changed = row.status != card.status.rawValue || row.position != card.position || row.doneAt != card.doneAt
            guard changed else { continue }
            row.status = card.status.rawValue
            row.position = card.position
            row.doneAt = card.doneAt
            row.updatedAt = .now
        }
        try context.save()
    }

    public func deleteTask(id: UUID) throws {
        guard let row = try taskRecord(id) else { return }
        row.deletedAt = .now
        row.updatedAt = .now
        try context.save()
    }

    @discardableResult
    public func createMilestone(projectID: UUID, title: String, dueOn: Date? = nil) throws -> UUID {
        let position = try liveMilestones().filter { $0.projectID == projectID }.count
        let row = MilestoneRecord(projectID: projectID, title: Self.limit(title, 80), position: position)
        row.dueOn = dueOn
        context.insert(row)
        try context.save()
        return row.id
    }

    public func moveMilestone(id: UUID, to index: Int) throws {
        guard let moving = try context.fetch(FetchDescriptor<MilestoneRecord>()).first(where: { $0.id == id }) else { return }
        var list = try liveMilestones().filter { $0.projectID == moving.projectID && $0.id != id }
            .sorted { $0.position < $1.position }
        list.insert(moving, at: min(max(index, 0), list.count))
        for (position, row) in list.enumerated() where row.position != position {
            row.position = position
            row.updatedAt = .now
        }
        try context.save()
    }

    @discardableResult
    public func createFeature(projectID: UUID, title: String, note: String = "", branch: String? = nil,
                              milestoneID: UUID? = nil) throws -> UUID {
        let position = try liveFeatures().filter { $0.projectID == projectID }.count
        let row = FeatureRecord(projectID: projectID, title: Self.limit(title, 80), position: position)
        row.note = Self.limit(note, 280)
        row.branch = branch.map { Self.limit($0, 255) }.flatMap { $0.isEmpty ? nil : $0 }
        row.milestoneID = milestoneID
        context.insert(row)
        try context.save()
        return row.id
    }

    public func updateFeature(id: UUID, title: String? = nil, note: String? = nil,
                              milestoneID: UUID?? = nil, branch: String?? = nil) throws {
        guard let row = try featureRecord(id) else { return }
        if let title { row.title = Self.limit(title, 80) }
        if let note { row.note = Self.limit(note, 280) }
        if let milestoneID { row.milestoneID = milestoneID }
        if let branch { row.branch = branch.map { Self.limit($0, 255) }.flatMap { $0.isEmpty ? nil : $0 } }
        row.updatedAt = .now
        try context.save()
    }

    public func moveFeature(id: UUID, to index: Int) throws {
        guard let moving = try featureRecord(id) else { return }
        var list = try liveFeatures().filter { $0.projectID == moving.projectID && $0.id != id }
            .sorted { $0.position < $1.position }
        list.insert(moving, at: min(max(index, 0), list.count))
        for (position, row) in list.enumerated() where row.position != position {
            row.position = position
            row.updatedAt = .now
        }
        try context.save()
    }

    /// Tombstones the feature and unlinks its tasks, as the server's
    /// `on delete set null` would.
    public func deleteFeature(id: UUID) throws {
        guard let row = try featureRecord(id) else { return }
        row.deletedAt = .now
        row.updatedAt = .now
        for task in try liveTasks() where task.featureID == id {
            task.featureID = nil
            task.updatedAt = .now
        }
        try context.save()
    }

    /// Writes a stage worked out from GitHub. Only a change is an edit: an
    /// unchanged stage would otherwise be pushed by every member who opens
    /// the project. The check time is kept here either way, for "as of".
    @discardableResult
    public func applyStage(featureID: UUID, stage: FeatureStage, detail: String, prNumber: Int?,
                           checkedAt: Date) throws -> Bool {
        guard let row = try featureRecord(featureID) else { return false }
        let detail = Self.limit(detail, 80)
        let changed = row.stage != stage.rawValue || row.stageDetail != detail || row.prNumber != prNumber
        row.stageCheckedAt = checkedAt
        if changed {
            row.stage = stage.rawValue
            row.stageDetail = detail
            row.prNumber = prNumber
            row.updatedAt = .now
        }
        try context.save()
        return changed
    }

    public func addMember(projectID: UUID, userID: UUID) throws {
        guard try !members(projectID: projectID).contains(where: { $0.userID == userID }) else { return }
        context.insert(ProjectMemberRecord(projectID: projectID, userID: userID, role: "member"))
        try context.save()
    }

    public func removeMember(projectID: UUID, userID: UUID) throws {
        for row in try context.fetch(FetchDescriptor<ProjectMemberRecord>())
        where row.projectID == projectID && row.userID == userID && row.role != "owner" {
            row.deletedAt = .now
            row.updatedAt = .now
        }
        try context.save()
    }

    // MARK: Sync

    // Pending: add the field and include it in isEmpty
    public struct Pending {
        public let projects: [ProjectRecord]
        public let members: [ProjectMemberRecord]
        public let milestones: [MilestoneRecord]
        public let features: [FeatureRecord]
        public let tasks: [ProjectTaskRecord]
        public var isEmpty: Bool {
            projects.isEmpty && members.isEmpty && milestones.isEmpty && features.isEmpty && tasks.isEmpty
        }
    }

    public func pending() throws -> Pending {
        func dirty(_ updated: Date, _ synced: Date?) -> Bool { synced.map { updated > $0 } ?? true }
        return Pending(
            projects: try context.fetch(FetchDescriptor<ProjectRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) },
            members: try context.fetch(FetchDescriptor<ProjectMemberRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) },
            milestones: try context.fetch(FetchDescriptor<MilestoneRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) },
            features: try context.fetch(FetchDescriptor<FeatureRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) },
            tasks: try context.fetch(FetchDescriptor<ProjectTaskRecord>()).filter { dirty($0.updatedAt, $0.syncedAt) }
        )
    }

    /// What a push took: each row's id and the edit it carried, so marking
    /// it synced afterwards cannot swallow an edit made while it was out.
    public struct PushedSnapshot: Sendable {
        public var stamps: [UUID: Date]
        public init(_ pending: Pending) {
            var stamps: [UUID: Date] = [:]
            pending.projects.forEach { stamps[$0.id] = $0.updatedAt }
            pending.members.forEach { stamps[$0.id] = $0.updatedAt }
            pending.milestones.forEach { stamps[$0.id] = $0.updatedAt }
            pending.features.forEach { stamps[$0.id] = $0.updatedAt }
            pending.tasks.forEach { stamps[$0.id] = $0.updatedAt }
            self.stamps = stamps
        }
    }

    /// Marks synced only the rows the push carried and that have not changed
    /// since; a removed member's row goes.
    public func markSynced(_ pushed: PushedSnapshot) throws {
        func unchanged(_ id: UUID, _ updated: Date) -> Bool { pushed.stamps[id] == updated }
        for row in try context.fetch(FetchDescriptor<ProjectRecord>()) where unchanged(row.id, row.updatedAt) { row.syncedAt = row.updatedAt }
        for row in try context.fetch(FetchDescriptor<MilestoneRecord>()) where unchanged(row.id, row.updatedAt) { row.syncedAt = row.updatedAt }
        for row in try context.fetch(FetchDescriptor<FeatureRecord>()) where unchanged(row.id, row.updatedAt) { row.syncedAt = row.updatedAt }
        for row in try context.fetch(FetchDescriptor<ProjectTaskRecord>()) where unchanged(row.id, row.updatedAt) { row.syncedAt = row.updatedAt }
        for row in try context.fetch(FetchDescriptor<ProjectMemberRecord>()) where unchanged(row.id, row.updatedAt) {
            if row.deletedAt != nil { context.delete(row) } else { row.syncedAt = row.updatedAt }
        }
        try context.save()
    }

    /// Everything pending is now on the server (tests and previews).
    public func markSynced(at date: Date) throws { try markSynced(PushedSnapshot(try pending())) }

    /// Projects this phone holds that have already been on the server.
    public func syncedProjectIDs() throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<ProjectRecord>()).filter { $0.syncedAt != nil }.map(\.id))
    }

    /// Drops a project and everything under it from this phone: the server
    /// no longer shows it to this person (they left or were removed).
    public func forgetProject(_ id: UUID) throws {
        for row in try context.fetch(FetchDescriptor<ProjectTaskRecord>()) where row.projectID == id { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<FeatureRecord>()) where row.projectID == id { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<MilestoneRecord>()) where row.projectID == id { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<ProjectMemberRecord>()) where row.projectID == id { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<ProjectRecord>()) where row.id == id { context.delete(row) }
        try context.save()
    }

    public func applyRemoteProject(id: UUID, name: String, scope: String, startsOn: Date?, endsOn: Date?,
                                   colour: String, ownerID: UUID?, repo: String?, archivedAt: Date?,
                                   updatedAt: Date, deletedAt: Date?) throws {
        let existing = try projectRecord(id)
        if let existing, ProjectMerge.keepLocal(localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt,
                                                remoteUpdatedAt: updatedAt) { return }
        let row = existing ?? {
            let made = ProjectRecord(id: id, name: name, scope: scope, colour: colour, ownerID: ownerID)
            context.insert(made)
            return made
        }()
        row.name = name; row.scope = scope; row.startsOn = startsOn; row.endsOn = endsOn
        row.colour = colour; row.ownerID = ownerID; row.repo = repo; row.archivedAt = archivedAt
        row.deletedAt = deletedAt; row.updatedAt = updatedAt; row.syncedAt = updatedAt
        try context.save()
    }

    public func applyRemoteMilestone(id: UUID, projectID: UUID, title: String, dueOn: Date?, position: Int,
                                     updatedAt: Date, deletedAt: Date?) throws {
        let existing = try context.fetch(FetchDescriptor<MilestoneRecord>()).first { $0.id == id }
        if let existing, ProjectMerge.keepLocal(localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt,
                                                remoteUpdatedAt: updatedAt) { return }
        let row = existing ?? {
            let made = MilestoneRecord(id: id, projectID: projectID, title: title, position: position)
            context.insert(made)
            return made
        }()
        row.title = title; row.dueOn = dueOn; row.position = position
        row.deletedAt = deletedAt; row.updatedAt = updatedAt; row.syncedAt = updatedAt
        try context.save()
    }

    public func applyRemoteFeature(id: UUID, projectID: UUID, milestoneID: UUID?, title: String, note: String,
                                   position: Int, branch: String?, stage: String, stageDetail: String,
                                   prNumber: Int?, stageCheckedAt: Date?, updatedAt: Date, deletedAt: Date?) throws {
        let existing = try featureRecord(id)
        if let existing, ProjectMerge.keepLocal(localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt,
                                                remoteUpdatedAt: updatedAt) { return }
        let row = existing ?? {
            let made = FeatureRecord(id: id, projectID: projectID, title: title, position: position)
            context.insert(made)
            return made
        }()
        row.milestoneID = milestoneID; row.title = title; row.note = note; row.position = position
        row.branch = branch; row.stage = stage; row.stageDetail = stageDetail; row.prNumber = prNumber
        row.stageCheckedAt = stageCheckedAt
        row.deletedAt = deletedAt; row.updatedAt = updatedAt; row.syncedAt = updatedAt
        try context.save()
    }

    public func applyRemoteTask(id: UUID, projectID: UUID, milestoneID: UUID?, featureID: UUID? = nil, title: String,
                                notes: String, status: String, ownerID: UUID?, dueOn: Date?, startsAt: Date?,
                                endsAt: Date?, position: Int, doneAt: Date?, updatedAt: Date, deletedAt: Date?) throws {
        let existing = try taskRecord(id)
        if let existing, ProjectMerge.keepLocal(localUpdatedAt: existing.updatedAt, localSyncedAt: existing.syncedAt,
                                                remoteUpdatedAt: updatedAt) { return }
        let row = existing ?? {
            let made = ProjectTaskRecord(id: id, projectID: projectID, title: title, position: position)
            context.insert(made)
            return made
        }()
        row.milestoneID = milestoneID; row.featureID = featureID; row.title = title; row.notes = notes; row.status = status
        row.ownerID = ownerID; row.dueOn = dueOn; row.startsAt = startsAt; row.endsAt = endsAt
        row.position = position; row.doneAt = doneAt
        row.deletedAt = deletedAt; row.updatedAt = updatedAt; row.syncedAt = updatedAt
        try context.save()
    }

    /// Members are refreshed whole: the server's set replaces the synced ones
    /// here, leaving local additions and removals not yet pushed alone.
    public func replaceMembers(_ rows: [(id: UUID, projectID: UUID, userID: UUID, role: String, addedAt: Date)]) throws {
        let local = try context.fetch(FetchDescriptor<ProjectMemberRecord>())
        let incoming = Set(rows.map(\.id))
        for row in local where row.syncedAt != nil && row.updatedAt <= (row.syncedAt ?? .distantPast)
            && !incoming.contains(row.id) {
            context.delete(row)
        }
        for remote in rows where !local.contains(where: { $0.id == remote.id }) {
            let made = ProjectMemberRecord(id: remote.id, projectID: remote.projectID, userID: remote.userID, role: remote.role)
            made.addedAt = remote.addedAt
            made.updatedAt = remote.addedAt
            made.syncedAt = remote.addedAt
            context.insert(made)
        }
        try context.save()
    }

    // MARK: Helpers

    /// Cut to `count` Unicode scalars, which is what Postgres's `char_length`
    /// counts: a title the server would reject never leaves the phone.
    static func limit(_ text: String, _ count: Int) -> String {
        guard text.unicodeScalars.count > count else { return text }
        var result = ""
        for character in text {
            guard result.unicodeScalars.count + character.unicodeScalars.count <= count else { break }
            result.append(character)
        }
        return result
    }

    private func projectRecord(_ id: UUID) throws -> ProjectRecord? {
        try context.fetch(FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func taskRecord(_ id: UUID) throws -> ProjectTaskRecord? {
        try context.fetch(FetchDescriptor<ProjectTaskRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func liveTasks() throws -> [ProjectTaskRecord] {
        try context.fetch(FetchDescriptor<ProjectTaskRecord>()).filter { $0.deletedAt == nil }
    }

    private func liveMilestones() throws -> [MilestoneRecord] {
        try context.fetch(FetchDescriptor<MilestoneRecord>()).filter { $0.deletedAt == nil }
    }

    private func featureRecord(_ id: UUID) throws -> FeatureRecord? {
        try context.fetch(FetchDescriptor<FeatureRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func liveFeatures() throws -> [FeatureRecord] {
        try context.fetch(FetchDescriptor<FeatureRecord>()).filter { $0.deletedAt == nil }
    }

    private func snapshot(_ row: FeatureRecord, tasks: [ProjectTaskRecord]) -> FeatureSnapshot {
        let theirs = tasks.filter { $0.featureID == row.id }
        let done = theirs.filter { $0.status == ProjectStatus.done.rawValue }.count
        return FeatureSnapshot(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID, title: row.title,
                               note: row.note, position: row.position, branch: row.branch,
                               stage: FeatureStage(rawValue: row.stage) ?? .planned, stageDetail: row.stageDetail,
                               prNumber: row.prNumber, stageCheckedAt: row.stageCheckedAt,
                               openTasks: theirs.count - done, doneTasks: done)
    }

    private func projectIndex() throws -> [UUID: ProjectRecord] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProjectRecord>())
            .filter { $0.deletedAt == nil && $0.archivedAt == nil }
            .map { ($0.id, $0) })
    }

    private func snapshot(_ row: ProjectTaskRecord, projects: [UUID: ProjectRecord]) -> ProjectTaskSnapshot? {
        guard let project = projects[row.projectID] else { return nil }
        return ProjectTaskSnapshot(id: row.id, projectID: row.projectID, projectName: project.name,
                                   colour: project.colour, milestoneID: row.milestoneID, featureID: row.featureID, title: row.title,
                                   notes: row.notes, status: ProjectStatus(rawValue: row.status) ?? .todo,
                                   ownerID: row.ownerID, dueOn: row.dueOn, startsAt: row.startsAt,
                                   endsAt: row.endsAt, position: row.position, doneAt: row.doneAt)
    }
}

private extension ProjectStatus {
    var order: Int { switch self { case .todo: 0; case .doing: 1; case .done: 2 } }
}

extension ProjectStatus: Comparable {
    public static func < (lhs: ProjectStatus, rhs: ProjectStatus) -> Bool { lhs.order < rhs.order }
}
