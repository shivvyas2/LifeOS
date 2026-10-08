import Foundation
import SwiftData
import Persistence

/// Keeps this phone's projects and the server's in step: push what changed
/// here, then pull what changed there.
///
/// - One run at a time; a request that arrives during a run starts one more
///   run after it, so nothing edited mid-run waits for the next trigger.
/// - Only rows a push carried, and that have not changed since, are marked
///   synced.
/// - A batch the server refuses is retried row by row; a row the server still
///   refuses (4xx) is set aside and reported, so one bad row cannot stop the
///   rest. Transport and server faults (5xx) leave everything pending.
/// - Each table pulls from its own cursor, the newest server `updated_at`
///   seen, page by page. A project this person was newly added to arrives
///   whole, whatever its age; one they no longer belong to is forgotten.
@MainActor
public final class ProjectSync {
    private let context: ModelContext
    private let remote: any ProjectRemote
    private let defaults: UserDefaults
    private let me: @MainActor () -> UUID?
    private let accessToken: @MainActor () async -> String?
    private var running = false
    private var again: (pull: Bool, requested: Bool) = (false, false)
    private static let pageSize = 500

    public private(set) var lastError: String?

    public init(context: ModelContext, remote: any ProjectRemote, defaults: UserDefaults = .currentAccount,
                me: @escaping @MainActor () -> UUID?, accessToken: @escaping @MainActor () async -> String?) {
        self.context = context
        self.remote = remote
        self.defaults = defaults
        self.me = me
        self.accessToken = accessToken
    }

    /// Push, then pull.
    public func sync() async { await gate(pull: true) }

    /// Push only, for an edit made outside the Projects tab.
    public func pushPending() async { await gate(pull: false) }

    private func gate(pull: Bool) async {
        if running {
            again = (again.pull || pull, true)
            return
        }
        running = true
        var wantsPull = pull
        repeat {
            again = (false, false)
            await run(pull: wantsPull)
            wantsPull = again.pull
        } while again.requested
        running = false
    }

    private func run(pull: Bool) async {
        guard let token = await accessToken() else { lastError = nil; return }
        do {
            try await push(token: token)
            if pull { try await self.pull(token: token) }
        } catch {
            lastError = "Projects could not sync. They will try again."
        }
    }

    // MARK: Push

    private func push(token: String) async throws {
        let store = ProjectsStore(context: context)
        let pending = try store.pending()
        guard !pending.isEmpty else { return }
        let snapshot = ProjectsStore.PushedSnapshot(pending)
        var refused = 0

        refused += try await send("projects", pending.projects.map(Self.projectRow), token: token)
        // Removals before additions: a friend removed and added again must
        // not meet their old row.
        for member in pending.members where member.deletedAt != nil {
            try await remote.delete(table: "project_members", column: "id",
                                    equals: member.id.uuidString.lowercased(), accessToken: token)
        }
        // The owner's own membership is the server's (a trigger adds it).
        let added = pending.members.filter { $0.deletedAt == nil && $0.role != "owner" }.map {
            ProjectMemberRow(id: $0.id, projectID: $0.projectID, userID: $0.userID, role: $0.role, addedAt: $0.addedAt).payload()
        }
        if !added.isEmpty {
            do {
                try await remote.insertIgnoringDuplicates(table: "project_members", body: SupabaseREST.encode(added),
                                                          accessToken: token)
            } catch let error as SupabaseREST.RESTError where error.isRefusal {
                refused += added.count
            }
        }
        refused += try await send("project_milestones", pending.milestones.map(Self.milestoneRow), token: token)
        // Before tasks, which point at features.
        refused += try await send("project_features", pending.features.map(Self.featureRow), token: token)
        for batch in stride(from: 0, to: pending.tasks.count, by: 100).map({
            Array(pending.tasks[$0..<min($0 + 100, pending.tasks.count)])
        }) {
            refused += try await send("project_tasks", batch.map(Self.taskRow), token: token)
        }
        try store.markSynced(snapshot)
        lastError = refused > 0 ? "\(refused) change\(refused == 1 ? "" : "s") could not be saved to the server." : nil
    }

    /// Upserts `rows`; a refused batch is retried row by row, and the rows
    /// still refused are counted and dropped. Returns how many were refused.
    private func send(_ table: String, _ rows: [[String: Any]], token: String) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        do {
            try await remote.upsert(table: table, body: SupabaseREST.encode(rows), accessToken: token)
            return 0
        } catch let error as SupabaseREST.RESTError where error.isRefusal {
            var refused = 0
            for row in rows {
                do {
                    try await remote.upsert(table: table, body: SupabaseREST.encode([row]), accessToken: token)
                } catch let error as SupabaseREST.RESTError where error.isRefusal {
                    refused += 1
                }
            }
            return refused
        }
    }

    // MARK: Pull

    private func pull(token: String) async throws {
        let store = ProjectsStore(context: context)

        // Membership first: it says which projects this person can see.
        var members: [ProjectMemberRow] = []
        var since: Date?
        for _ in 0..<40 {
            let page = SupabaseREST.decode(try await remote.fetch(table: "project_members", since: since,
                                                                  accessToken: token, limit: Self.pageSize))
                .compactMap(ProjectMemberRow.init(json:))
            members += page
            guard page.count == Self.pageSize, let last = page.last else { break }
            since = last.addedAt
        }
        // Distinct by id: a page boundary can repeat rows.
        var seen = Set<UUID>()
        members = members.filter { seen.insert($0.id).inserted }
        try store.replaceMembers(members.map { ($0.id, $0.projectID, $0.userID, $0.role, $0.addedAt) })

        if let me = me() {
            let mine = Set(members.filter { $0.userID == me }.map(\.projectID))
            // Gone from the server's view: left, removed, or the project went.
            for id in try store.syncedProjectIDs() where !mine.contains(id) {
                try store.forgetProject(id)
            }
            // Newly visible: fetch whole, whatever the cursors say.
            let known = Set(try store.projects(includeArchived: true).map(\.id))
            for id in mine.subtracting(known) {
                try await pullWhole(project: id, token: token, store: store)
            }
        }

        try await pullTable("projects", token: token) { json in
            guard let row = ProjectRow(json: json) else { return nil }
            try store.applyRemoteProject(id: row.id, name: row.name, scope: row.scope, startsOn: row.startsOn,
                                         endsOn: row.endsOn, colour: row.colour, ownerID: row.ownerID, repo: row.repo,
                                         archivedAt: row.archivedAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
            return row.updatedAt
        }
        try await pullTable("project_milestones", token: token) { json in
            guard let row = MilestoneRow(json: json) else { return nil }
            try Self.apply(row, store)
            return row.updatedAt
        }
        try await pullTable("project_features", token: token) { json in
            guard let row = FeatureRow(json: json) else { return nil }
            try Self.apply(row, store)
            return row.updatedAt
        }
        try await pullTable("project_tasks", token: token) { json in
            guard let row = ProjectTaskRow(json: json) else { return nil }
            try Self.apply(row, store)
            return row.updatedAt
        }
    }

    /// Pages through `table` from its own cursor, the newest server time
    /// seen, applying each row; the cursor moves to the newest row applied.
    private func pullTable(_ table: String, token: String, apply: ([String: Any]) throws -> Date?) async throws {
        let key = "projects.sync.cursor.\(table)"
        var cursor = defaults.object(forKey: key) as? Date
        for _ in 0..<40 {
            let page = SupabaseREST.decode(try await remote.fetch(table: table, since: cursor, accessToken: token,
                                                                  limit: Self.pageSize))
            var newest = cursor
            for json in page {
                if let stamp = try apply(json) { newest = max(newest ?? stamp, stamp) }
            }
            cursor = newest
            defaults.set(cursor, forKey: key)
            guard page.count == Self.pageSize else { break }
        }
    }

    private func pullWhole(project id: UUID, token: String, store: ProjectsStore) async throws {
        let key = id.uuidString.lowercased()
        for json in SupabaseREST.decode(try await remote.fetch(table: "projects", column: "id", equals: key,
                                                               accessToken: token, limit: 1)) {
            guard let row = ProjectRow(json: json) else { continue }
            try store.applyRemoteProject(id: row.id, name: row.name, scope: row.scope, startsOn: row.startsOn,
                                         endsOn: row.endsOn, colour: row.colour, ownerID: row.ownerID, repo: row.repo,
                                         archivedAt: row.archivedAt, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
        }
        for json in SupabaseREST.decode(try await remote.fetch(table: "project_milestones", column: "project_id",
                                                               equals: key, accessToken: token, limit: 1_000)) {
            if let row = MilestoneRow(json: json) { try Self.apply(row, store) }
        }
        for json in SupabaseREST.decode(try await remote.fetch(table: "project_features", column: "project_id",
                                                               equals: key, accessToken: token, limit: 1_000)) {
            if let row = FeatureRow(json: json) { try Self.apply(row, store) }
        }
        for json in SupabaseREST.decode(try await remote.fetch(table: "project_tasks", column: "project_id",
                                                               equals: key, accessToken: token, limit: 5_000)) {
            if let row = ProjectTaskRow(json: json) { try Self.apply(row, store) }
        }
    }

    // MARK: Rows

    private static func apply(_ row: MilestoneRow, _ store: ProjectsStore) throws {
        try store.applyRemoteMilestone(id: row.id, projectID: row.projectID, title: row.title, dueOn: row.dueOn,
                                       position: row.position, updatedAt: row.updatedAt, deletedAt: row.deletedAt)
    }

    private static func apply(_ row: FeatureRow, _ store: ProjectsStore) throws {
        try store.applyRemoteFeature(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID,
                                     title: row.title, note: row.note, position: row.position, branch: row.branch,
                                     stage: row.stage, stageDetail: row.stageDetail, prNumber: row.prNumber,
                                     stageCheckedAt: row.stageCheckedAt, autoLink: row.autoLink, updatedAt: row.updatedAt,
                                     deletedAt: row.deletedAt)
    }

    private static func featureRow(_ r: FeatureRecord) -> [String: Any] {
        FeatureRow(id: r.id, projectID: r.projectID, milestoneID: r.milestoneID, title: r.title, note: r.note,
                   position: r.position, branch: r.branch, stage: r.stage, stageDetail: r.stageDetail,
                   prNumber: r.prNumber, stageCheckedAt: r.stageCheckedAt, autoLink: r.autoLink, updatedAt: r.updatedAt,
                   deletedAt: r.deletedAt).payload()
    }

    private static func apply(_ row: ProjectTaskRow, _ store: ProjectsStore) throws {
        try store.applyRemoteTask(id: row.id, projectID: row.projectID, milestoneID: row.milestoneID, featureID: row.featureID,
                                  title: row.title,
                                  notes: row.notes, status: row.status, ownerID: row.ownerID, dueOn: row.dueOn,
                                  startsAt: row.startsAt, endsAt: row.endsAt, position: row.position, doneAt: row.doneAt,
                                  updatedAt: row.updatedAt, deletedAt: row.deletedAt)
    }

    private static func projectRow(_ r: ProjectRecord) -> [String: Any] {
        ProjectRow(id: r.id, name: r.name, scope: r.scope, startsOn: r.startsOn, endsOn: r.endsOn, colour: r.colour,
                   ownerID: r.ownerID, repo: r.repo, archivedAt: r.archivedAt, updatedAt: r.updatedAt,
                   deletedAt: r.deletedAt).payload()
    }

    private static func milestoneRow(_ r: MilestoneRecord) -> [String: Any] {
        MilestoneRow(id: r.id, projectID: r.projectID, title: r.title, dueOn: r.dueOn, position: r.position,
                     updatedAt: r.updatedAt, deletedAt: r.deletedAt).payload()
    }

    private static func taskRow(_ r: ProjectTaskRecord) -> [String: Any] {
        ProjectTaskRow(id: r.id, projectID: r.projectID, milestoneID: r.milestoneID, featureID: r.featureID,
                       title: r.title, notes: r.notes,
                       status: r.status, ownerID: r.ownerID, dueOn: r.dueOn, startsAt: r.startsAt, endsAt: r.endsAt,
                       position: r.position, doneAt: r.doneAt, updatedAt: r.updatedAt, deletedAt: r.deletedAt).payload()
    }
}

extension SupabaseREST.RESTError {
    /// The server understood and said no (4xx): retrying the same row cannot
    /// help. Transport faults and 5xx are worth retrying.
    var isRefusal: Bool {
        // Not 401 (an expired token), 408 or 429 (try later): those say
        // nothing about the row.
        if case .server(let status, _) = self { return (400..<500).contains(status) && ![401, 408, 429].contains(status) }
        return false
    }
}
