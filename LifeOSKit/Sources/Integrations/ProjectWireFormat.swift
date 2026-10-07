import Foundation

/// Rows of the four project tables as the server stores them.
enum WireDate {
    /// `date` columns travel as `yyyy-MM-dd` in the phone's own timezone and
    /// come back as local midnight, as journal dates do, so a day never moves.
    static func day(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return SupabaseREST.day(date)
    }

    static func readDay(_ value: Any?) -> Date? { (value as? String).flatMap { SupabaseREST.day(from: $0) } }

    static func instant(_ date: Date?) -> Any { date.map(SupabaseREST.timestamp) ?? NSNull() }
    static func read(_ value: Any?) -> Date? { (value as? String).flatMap(SupabaseREST.date) }
    static func uuid(_ value: Any?) -> UUID? { (value as? String).flatMap(UUID.init(uuidString:)) }
    static func string(_ id: UUID?) -> Any { id?.uuidString.lowercased() ?? NSNull() }
}

public struct ProjectRow: Equatable, Sendable {
    public var id: UUID, name: String, scope: String, startsOn: Date?, endsOn: Date?, colour: String
    public var ownerID: UUID?, repo: String?, archivedAt: Date?, updatedAt: Date, deletedAt: Date?

    public init(id: UUID, name: String, scope: String, startsOn: Date?, endsOn: Date?, colour: String,
                ownerID: UUID?, repo: String?, archivedAt: Date?, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.name = name; self.scope = scope; self.startsOn = startsOn; self.endsOn = endsOn
        self.colour = colour; self.ownerID = ownerID; self.repo = repo; self.archivedAt = archivedAt
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public init?(json: [String: Any]) {
        guard let id = WireDate.uuid(json["id"]), let name = json["name"] as? String,
              let updated = WireDate.read(json["updated_at"]) else { return nil }
        self.init(id: id, name: name, scope: json["scope"] as? String ?? "", startsOn: WireDate.readDay(json["starts_on"]),
                  endsOn: WireDate.readDay(json["ends_on"]), colour: json["colour"] as? String ?? "tomato",
                  ownerID: WireDate.uuid(json["owner_id"]), repo: json["repo"] as? String,
                  archivedAt: WireDate.read(json["archived_at"]), updatedAt: updated, deletedAt: WireDate.read(json["deleted_at"]))
    }

    /// `updated_at` is the server's to set; the row carries the rest.
    public func payload() -> [String: Any] {
        ["id": WireDate.string(id), "name": name, "scope": scope, "starts_on": WireDate.day(startsOn),
         "ends_on": WireDate.day(endsOn), "colour": colour, "owner_id": WireDate.string(ownerID),
         "repo": repo ?? NSNull(), "archived_at": WireDate.instant(archivedAt),
         "updated_at": WireDate.instant(updatedAt), "deleted_at": WireDate.instant(deletedAt)]
    }
}

public struct ProjectMemberRow: Equatable, Sendable {
    public var id: UUID, projectID: UUID, userID: UUID, role: String, addedAt: Date

    public init(id: UUID, projectID: UUID, userID: UUID, role: String, addedAt: Date) {
        self.id = id; self.projectID = projectID; self.userID = userID; self.role = role; self.addedAt = addedAt
    }

    public init?(json: [String: Any]) {
        guard let id = WireDate.uuid(json["id"]), let project = WireDate.uuid(json["project_id"]),
              let user = WireDate.uuid(json["user_id"]) else { return nil }
        self.init(id: id, projectID: project, userID: user, role: json["role"] as? String ?? "member",
                  addedAt: WireDate.read(json["added_at"]) ?? .distantPast)
    }

    public func payload() -> [String: Any] {
        ["id": WireDate.string(id), "project_id": WireDate.string(projectID), "user_id": WireDate.string(userID),
         "role": role, "added_at": WireDate.instant(addedAt)]
    }
}

public struct MilestoneRow: Equatable, Sendable {
    public var id: UUID, projectID: UUID, title: String, dueOn: Date?, position: Int, updatedAt: Date, deletedAt: Date?

    public init(id: UUID, projectID: UUID, title: String, dueOn: Date?, position: Int, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.projectID = projectID; self.title = title; self.dueOn = dueOn; self.position = position
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public init?(json: [String: Any]) {
        guard let id = WireDate.uuid(json["id"]), let project = WireDate.uuid(json["project_id"]),
              let updated = WireDate.read(json["updated_at"]) else { return nil }
        self.init(id: id, projectID: project, title: json["title"] as? String ?? "", dueOn: WireDate.readDay(json["due_on"]),
                  position: json["position"] as? Int ?? 0, updatedAt: updated, deletedAt: WireDate.read(json["deleted_at"]))
    }

    public func payload() -> [String: Any] {
        ["id": WireDate.string(id), "project_id": WireDate.string(projectID), "title": title,
         "due_on": WireDate.day(dueOn), "position": position, "updated_at": WireDate.instant(updatedAt),
         "deleted_at": WireDate.instant(deletedAt)]
    }
}

public struct ProjectTaskRow: Equatable, Sendable {
    public var id: UUID, projectID: UUID, milestoneID: UUID?, title: String, notes: String, status: String
    public var ownerID: UUID?, dueOn: Date?, startsAt: Date?, endsAt: Date?, position: Int, doneAt: Date?
    public var updatedAt: Date, deletedAt: Date?

    public init(id: UUID, projectID: UUID, milestoneID: UUID?, title: String, notes: String, status: String,
                ownerID: UUID?, dueOn: Date?, startsAt: Date?, endsAt: Date?, position: Int, doneAt: Date?,
                updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.projectID = projectID; self.milestoneID = milestoneID; self.title = title; self.notes = notes
        self.status = status; self.ownerID = ownerID; self.dueOn = dueOn; self.startsAt = startsAt; self.endsAt = endsAt
        self.position = position; self.doneAt = doneAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public init?(json: [String: Any]) {
        guard let id = WireDate.uuid(json["id"]), let project = WireDate.uuid(json["project_id"]),
              let updated = WireDate.read(json["updated_at"]) else { return nil }
        self.init(id: id, projectID: project, milestoneID: WireDate.uuid(json["milestone_id"]),
                  title: json["title"] as? String ?? "", notes: json["notes"] as? String ?? "",
                  status: json["status"] as? String ?? "todo", ownerID: WireDate.uuid(json["owner_id"]),
                  dueOn: WireDate.readDay(json["due_on"]), startsAt: WireDate.read(json["starts_at"]),
                  endsAt: WireDate.read(json["ends_at"]), position: json["position"] as? Int ?? 0,
                  doneAt: WireDate.read(json["done_at"]), updatedAt: updated, deletedAt: WireDate.read(json["deleted_at"]))
    }

    public func payload() -> [String: Any] {
        ["id": WireDate.string(id), "project_id": WireDate.string(projectID), "milestone_id": WireDate.string(milestoneID),
         "title": title, "notes": notes, "status": status, "owner_id": WireDate.string(ownerID),
         "due_on": WireDate.day(dueOn), "starts_at": WireDate.instant(startsAt), "ends_at": WireDate.instant(endsAt),
         "position": position, "done_at": WireDate.instant(doneAt), "updated_at": WireDate.instant(updatedAt),
         "deleted_at": WireDate.instant(deletedAt)]
    }
}
