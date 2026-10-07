import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// A small in-memory stand-in for the four project tables.
final class FakeProjectServer: ProjectRemote, @unchecked Sendable {
    var tables: [String: [String: [String: Any]]] = [:]   // table → id → row
    var rejectIDs: Set<String> = []
    var calls: [String] = []
    var onUpsert: (@MainActor (String) -> Void)?
    /// Server time: an hour behind now, ticking a second per write, as a real
    /// server's rows would be older than an edit made on the phone just now.
    private var clock = Date.now.addingTimeInterval(-3_600)

    func tick() -> String { clock = clock.addingTimeInterval(1); return SupabaseREST.timestamp(clock) }

    func seed(_ table: String, _ row: [String: Any], at date: Date) {
        var row = row
        row["updated_at"] = SupabaseREST.timestamp(date)
        tables[table, default: [:]][row["id"] as! String] = row
    }

    func upsert(table: String, body: Data, accessToken: String) async throws {
        let rows = SupabaseREST.decode(body)
        calls.append("upsert \(table) \(rows.count)")
        if let onUpsert { await onUpsert(table) }
        if rows.contains(where: { rejectIDs.contains($0["id"] as? String ?? "") }) {
            throw SupabaseREST.RESTError.server(status: 400, message: "rejected")
        }
        for var row in rows {
            let isNew = tables[table, default: [:]][row["id"] as! String] == nil
            row["updated_at"] = tick()
            tables[table, default: [:]][row["id"] as! String] = row
            // As the server's trigger does: the creator becomes the owner member.
            if table == "projects", isNew, let owner = row["owner_id"] as? String {
                let member = UUID().uuidString.lowercased()
                tables["project_members", default: [:]][member] = ["id": member, "project_id": row["id"]!, "user_id": owner,
                                                                    "role": "owner", "updated_at": tick()]
            }
        }
    }

    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws {
        let rows = SupabaseREST.decode(body)
        calls.append("insert \(table) \(rows.count)")
        for var row in rows {
            let exists = tables[table, default: [:]].values.contains {
                $0["project_id"] as? String == row["project_id"] as? String && $0["user_id"] as? String == row["user_id"] as? String
            }
            if exists { continue }
            row["updated_at"] = tick()
            tables[table, default: [:]][row["id"] as! String] = row
        }
    }

    func delete(table: String, column: String, equals value: String, accessToken: String) async throws {
        calls.append("delete \(table)")
        tables[table] = tables[table, default: [:]].filter { $0.value[column] as? String != value }
    }

    func fetch(table: String, since: Date?, accessToken: String, limit: Int) async throws -> Data {
        let rows = tables[table, default: [:]].values
            .filter { row in since.map { (SupabaseREST.date(row["updated_at"] as! String) ?? .distantPast) >= $0 } ?? true }
            .sorted { (SupabaseREST.date($0["updated_at"] as! String)!) < (SupabaseREST.date($1["updated_at"] as! String)!) }
        return try SupabaseREST.encode(Array(rows.prefix(limit)))
    }

    func fetch(table: String, column: String, equals value: String, accessToken: String, limit: Int) async throws -> Data {
        let rows = tables[table, default: [:]].values.filter { $0[column] as? String == value }
        return try SupabaseREST.encode(Array(rows.prefix(limit)))
    }
}

@Suite @MainActor struct ProjectSyncTests {
    private let me = UUID(), friend = UUID()
    private func setUp() throws -> (ModelContext, ProjectsStore, FakeProjectServer, ProjectSync) {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let server = FakeProjectServer()
        let defaults = UserDefaults(suiteName: "project.sync.\(UUID().uuidString)")!
        let me = self.me
        let sync = ProjectSync(context: context, remote: server, defaults: defaults,
                               me: { me }, accessToken: { "token" })
        return (context, ProjectsStore(context: context), server, sync)
    }
    private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    @Test func anEditMadeDuringAPushStaysPending() async throws {
        let (_, store, server, sync) = try setUp()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        let a = try store.createTask(projectID: project, title: "A")
        let b = try store.createTask(projectID: project, title: "B")
        await sync.sync()
        try store.updateTask(id: a, title: "A2")
        server.onUpsert = { table in
            if table == "project_tasks" { try? store.updateTask(id: b, title: "B edited mid-push") }
        }
        await sync.sync()
        server.onUpsert = nil
        #expect(try store.pending().tasks.map(\.id).contains(b), "an edit made during the push was marked synced")
        #expect(try store.tasks(projectID: project).first { $0.id == b }?.title == "B edited mid-push")
    }

    @Test func aRejectedRowDoesNotStopTheRest() async throws {
        let (_, store, server, sync) = try setUp()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        let bad = try store.createTask(projectID: project, title: "Bad")
        let good = try store.createTask(projectID: project, title: "Good")
        server.rejectIDs = [id(bad)]
        await sync.sync()
        #expect(server.tables["project_tasks"]?[id(good)] != nil, "the good row never went up")
        #expect(try store.pending().tasks.isEmpty, "the rejected row is retried forever")
        #expect(sync.lastError != nil)
        #expect(server.calls.contains { $0.hasPrefix("upsert project_tasks") })
    }

    @Test func aFriendAddedLaterReceivesTheWholeProject() async throws {
        let (_, store, server, sync) = try setUp()
        await sync.sync()   // the cursor moves past everything below
        let p = UUID(), task = UUID()
        let long = Date(timeIntervalSince1970: 1_000_000_000)
        server.seed("projects", ["id": id(p), "name": "Old project", "scope": "", "colour": "iris", "owner_id": id(friend)], at: long)
        server.seed("project_tasks", ["id": id(task), "project_id": id(p), "title": "Old task", "notes": "", "status": "todo", "position": 0], at: long)
        server.seed("project_members", ["id": id(UUID()), "project_id": id(p), "user_id": id(me), "role": "member"],
                    at: Date(timeIntervalSince1970: 1_900_000_000))
        await sync.sync()
        #expect(try store.projects().map(\.name) == ["Old project"])
        #expect(try store.tasks(projectID: p).map(\.title) == ["Old task"])
    }

    @Test func aRemovedMemberForgetsTheProject() async throws {
        let (_, store, server, sync) = try setUp()
        let p = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        server.seed("projects", ["id": id(p), "name": "Shared", "scope": "", "colour": "iris", "owner_id": id(friend)], at: at)
        server.seed("project_members", ["id": "m1", "project_id": id(p), "user_id": id(me), "role": "member"], at: at)
        server.seed("project_members", ["id": "m0", "project_id": id(p), "user_id": id(friend), "role": "owner"], at: at)
        await sync.sync()
        #expect(try store.projects().count == 1)
        server.tables["project_members"]?["m1"] = nil
        server.tables["projects"] = [:]   // RLS hides it now
        await sync.sync()
        #expect(try store.projects().isEmpty)
    }

    @Test func aFirstSyncPagesPastFiveHundredRows() async throws {
        let (_, store, server, sync) = try setUp()
        let p = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        server.seed("projects", ["id": id(p), "name": "Big", "scope": "", "colour": "rose", "owner_id": id(me)], at: at)
        server.seed("project_members", ["id": "m", "project_id": id(p), "user_id": id(me), "role": "owner"], at: at)
        for n in 0..<503 {
            server.seed("project_tasks", ["id": id(UUID()), "project_id": id(p), "title": "T\(n)", "notes": "",
                                          "status": "todo", "position": n], at: at.addingTimeInterval(Double(n)))
        }
        await sync.sync()
        #expect(try store.tasks(projectID: p).count == 503)
    }

    @Test func aMemberRemovedAndReAddedIsDeletedBeforeItIsAdded() async throws {
        let (_, store, server, sync) = try setUp()
        let project = try store.createProject(name: "P", scope: "", colour: "moss", ownerID: me)
        try store.addMember(projectID: project, userID: friend)
        await sync.sync()
        try store.removeMember(projectID: project, userID: friend)
        try store.addMember(projectID: project, userID: friend)
        await sync.sync()
        #expect(sync.lastError == nil)
        let rows = server.tables["project_members"]?.values.filter { $0["user_id"] as? String == id(friend) } ?? []
        #expect(rows.count == 1)
        let order = server.calls.filter { $0.contains("project_members") }
        if let delete = order.lastIndex(where: { $0.hasPrefix("delete") }), let insert = order.lastIndex(where: { $0.hasPrefix("insert") }) {
            #expect(delete < insert)
        }
    }
}
