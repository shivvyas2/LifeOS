import Foundation
import SwiftData
import Persistence

/// Keeps this phone's projects and the server's in step, the way `NoteSync`
/// does for pages: push what changed here, then pull what changed there since
/// the cursor. Members are small and refreshed whole each time.
@MainActor
public final class ProjectSync {
    private let context: ModelContext
    private let rest: SupabaseREST
    private let defaults: UserDefaults
    private let accessToken: @MainActor () async -> String?
    private static let cursorKey = "projects.sync.cursor"
    private var inFlight: Task<Void, Never>?

    public private(set) var lastError: String?

    public init(context: ModelContext, rest: SupabaseREST, defaults: UserDefaults = .currentAccount,
                accessToken: @escaping @MainActor () async -> String?) {
        self.context = context
        self.rest = rest
        self.defaults = defaults
        self.accessToken = accessToken
    }

    public func sync() async {
        if let inFlight { await inFlight.value; return }
        let task = Task { @MainActor in await self.run() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Pushes local changes only, without a pull: after a tick or an edit
    /// made outside the Projects tab.
    public func pushPending() async {
        guard let token = await accessToken() else { return }
        do { try await push(token: token) } catch { lastError = String(describing: error) }
    }

    private func run() async {
        guard let token = await accessToken() else { lastError = nil; return }
        do {
            try await push(token: token)
            try await pull(token: token)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    private func push(token: String) async throws {
        let store = ProjectsStore(context: context)
        let pending = try store.pending()
        guard !pending.isEmpty else { return }
        // Projects before what hangs off them, so membership checks on the
        // server find the project they guard.
        if !pending.projects.isEmpty {
            let rows = pending.projects.map {
                ProjectRow(id: $0.id, name: $0.name, scope: $0.scope, startsOn: $0.startsOn, endsOn: $0.endsOn,
                           colour: $0.colour, ownerID: $0.ownerID, repo: $0.repo, archivedAt: $0.archivedAt,
                           updatedAt: $0.updatedAt, deletedAt: $0.deletedAt).payload()
            }
            try await rest.upsert(table: "projects", body: SupabaseREST.encode(rows), accessToken: token)
        }
        // The owner's own membership is the server's (a trigger adds it), so
        // only added friends go up; a removal deletes its row.
        let added = pending.members.filter { $0.deletedAt == nil && $0.role != "owner" }
        if !added.isEmpty {
            let rows = added.map {
                ProjectMemberRow(id: $0.id, projectID: $0.projectID, userID: $0.userID, role: $0.role, addedAt: $0.addedAt).payload()
            }
            try await rest.upsert(table: "project_members", body: SupabaseREST.encode(rows), accessToken: token)
        }
        for removed in pending.members where removed.deletedAt != nil {
            try await rest.delete(table: "project_members", column: "id", equals: removed.id.uuidString.lowercased(),
                                  accessToken: token)
        }
        if !pending.milestones.isEmpty {
            let rows = pending.milestones.map {
                MilestoneRow(id: $0.id, projectID: $0.projectID, title: $0.title, dueOn: $0.dueOn, position: $0.position,
                             updatedAt: $0.updatedAt, deletedAt: $0.deletedAt).payload()
            }
            try await rest.upsert(table: "project_milestones", body: SupabaseREST.encode(rows), accessToken: token)
        }
        if !pending.tasks.isEmpty {
            for batch in stride(from: 0, to: pending.tasks.count, by: 100).map({
                Array(pending.tasks[$0..<min($0 + 100, pending.tasks.count)])
            }) {
                let rows = batch.map {
                    ProjectTaskRow(id: $0.id, projectID: $0.projectID, milestoneID: $0.milestoneID, title: $0.title,
                                   notes: $0.notes, status: $0.status, ownerID: $0.ownerID, dueOn: $0.dueOn,
                                   startsAt: $0.startsAt, endsAt: $0.endsAt, position: $0.position, doneAt: $0.doneAt,
                                   updatedAt: $0.updatedAt, deletedAt: $0.deletedAt).payload()
                }
                try await rest.upsert(table: "project_tasks", body: SupabaseREST.encode(rows), accessToken: token)
            }
        }
        try store.markSynced(at: .now)
    }

    private func pull(token: String) async throws {
        let store = ProjectsStore(context: context)
        let cursor = defaults.object(forKey: Self.cursorKey) as? Date
        let since = cursor.map { $0.addingTimeInterval(-1) }
        let started = Date.now

        for row in SupabaseREST.decode(try await rest.fetch(table: "projects", since: since, accessToken: token))
            .compactMap(ProjectRow.init(json:)) {
            try store.applyRemoteProject(id: row.id, name: row.name, scope: row.scope, startsOn: row.startsOn,
                                         endsOn: row.endsOn, colour: row.colour, ownerID: row.ownerID, repo: row.repo,
                                         archivedAt: row.archivedAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
        }
        let members = SupabaseREST.decode(try await rest.fetch(table: "project_members", since: nil, accessToken: token))
            .compactMap(ProjectMemberRow.init(json:))
        try store.replaceMembers(members.map { ($0.id, $0.projectID, $0.userID, $0.role, $0.addedAt) })
        for row in SupabaseREST.decode(try await rest.fetch(table: "project_milestones", since: since, accessToken: token))
            .compactMap(MilestoneRow.init(json:)) {
            try store.applyRemoteMilestone(id: row.id, projectID: row.projectID, title: row.title, dueOn: row.dueOn,
                                           position: row.position, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
        }
        for row in SupabaseREST.decode(try await rest.fetch(table: "project_tasks", since: since, accessToken: token))
            .compactMap(ProjectTaskRow.init(json:)) {
            try store.applyRemoteTask(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID, title: row.title,
                                      notes: row.notes, status: row.status, ownerID: row.ownerID, dueOn: row.dueOn,
                                      startsAt: row.startsAt, endsAt: row.endsAt, position: row.position,
                                      doneAt: row.doneAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
        }
        defaults.set(started, forKey: Self.cursorKey)
    }
}
