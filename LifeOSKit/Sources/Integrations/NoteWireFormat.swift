import Foundation
import Persistence

/// The shape a note travels in.
///
/// A value type between the `@Model` and the JSON, for the reason every
/// integration in this package has one: the mapping is where the bugs live, and
/// a mapping expressed against a managed object can only be tested by standing
/// up a store. This one is testable with a literal.
public struct NoteDocumentRow: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String
    public var kind: String
    public var bucket: String
    public var accent: String
    public var folderID: UUID?
    public var blocks: [NoteBlock]
    public var drawing: Data?
    public var entryDate: Date?
    public var dueDate: Date?
    public var status: String
    public var sortOrder: Int
    public var isFavorite: Bool
    public var openedAt: Date?
    public var archivedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    /// Ink above this size is kept on the device and left out of the push.
    ///
    /// A dense PencilKit page is a few hundred kilobytes; a pathological one is
    /// megabytes, and base64 adds a third on top. One runaway page must not be
    /// able to stall every other page's sync behind it, and the drawing is
    /// still safe locally, so the page syncs its text and says so.
    public static let maxDrawingBytes = 1_500_000

    public init(
        id: UUID, title: String, icon: String, kind: String, bucket: String, accent: String,
        folderID: UUID?, blocks: [NoteBlock], drawing: Data?, entryDate: Date?, dueDate: Date?,
        status: String, sortOrder: Int, isFavorite: Bool, openedAt: Date?, archivedAt: Date?,
        createdAt: Date, updatedAt: Date, deletedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.kind = kind
        self.bucket = bucket
        self.accent = accent
        self.folderID = folderID
        self.blocks = blocks
        self.drawing = drawing
        self.entryDate = entryDate
        self.dueDate = dueDate
        self.status = status
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
        self.openedAt = openedAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The JSON body PostgREST receives.
    ///
    /// `user_id` is deliberately absent: the column defaults to `auth.uid()`,
    /// so the server decides ownership from the token. A client that sent its
    /// own id would be asserting something RLS then has to refuse, and the
    /// failure would look like a permissions bug rather than what it is.
    public func payload() -> [String: Any] {
        var row: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "title": title,
            "icon": icon,
            "kind": kind,
            "bucket": bucket,
            "accent": accent,
            "blocks": blocks.map(NoteDocumentRow.blockJSON),
            "status": status,
            "sort_order": sortOrder,
            "is_favorite": isFavorite,
            "created_at": SupabaseREST.timestamp(createdAt),
            "updated_at": SupabaseREST.timestamp(updatedAt),
        ]
        row["folder_id"] = folderID.map { $0.uuidString.lowercased() } ?? NSNull()
        row["entry_date"] = entryDate.map { SupabaseREST.day($0) } ?? NSNull()
        row["due_date"] = dueDate.map { SupabaseREST.timestamp($0) } ?? NSNull()
        row["opened_at"] = openedAt.map { SupabaseREST.timestamp($0) } ?? NSNull()
        row["archived_at"] = archivedAt.map { SupabaseREST.timestamp($0) } ?? NSNull()
        row["deleted_at"] = deletedAt.map { SupabaseREST.timestamp($0) } ?? NSNull()

        if let drawing, !drawing.isEmpty, drawing.count <= NoteDocumentRow.maxDrawingBytes {
            row["drawing"] = drawing.base64EncodedString()
        } else {
            row["drawing"] = NSNull()
        }
        return row
    }

    public init?(json: [String: Any]) {
        guard let idString = json["id"] as? String, let id = UUID(uuidString: idString),
              let updated = (json["updated_at"] as? String).flatMap(SupabaseREST.date)
        else { return nil }

        self.id = id
        self.title = json["title"] as? String ?? ""
        self.icon = json["icon"] as? String ?? ""
        self.kind = json["kind"] as? String ?? NoteKind.note.rawValue
        self.bucket = json["bucket"] as? String ?? NoteBucket.projects.rawValue
        self.accent = json["accent"] as? String ?? NoteAccent.sage.rawValue
        self.folderID = (json["folder_id"] as? String).flatMap(UUID.init(uuidString:))
        self.blocks = NoteDocumentRow.blocks(from: json["blocks"])
        self.drawing = (json["drawing"] as? String).flatMap { Data(base64Encoded: $0) }
        self.entryDate = (json["entry_date"] as? String).flatMap { SupabaseREST.day(from: $0) }
        self.dueDate = (json["due_date"] as? String).flatMap(SupabaseREST.date)
        self.status = json["status"] as? String ?? PlanStatus.todo.rawValue
        self.sortOrder = json["sort_order"] as? Int ?? 0
        self.isFavorite = json["is_favorite"] as? Bool ?? false
        self.openedAt = (json["opened_at"] as? String).flatMap(SupabaseREST.date)
        self.archivedAt = (json["archived_at"] as? String).flatMap(SupabaseREST.date)
        self.createdAt = (json["created_at"] as? String).flatMap(SupabaseREST.date) ?? updated
        self.updatedAt = updated
        self.deletedAt = (json["deleted_at"] as? String).flatMap(SupabaseREST.date)
    }

    /// Blocks go over as real JSON rather than as an encoded string, so the
    /// column is queryable and a malformed document is refused by Postgres at
    /// write time instead of surfacing on another device later.
    static func blockJSON(_ block: NoteBlock) -> [String: Any] {
        var json: [String: Any] = [
            "id": block.id.uuidString.lowercased(),
            "kind": block.kind.rawValue,
            "text": block.text,
            "isChecked": block.isChecked,
            "indent": block.indent,
        ]
        // Only sketches carry these, and only when drawn in. Writing nulls on
        // every text block would inflate a page of prose for nothing.
        if let drawing = block.drawing, !drawing.isEmpty,
           drawing.count <= NoteDocumentRow.maxDrawingBytes {
            json["drawing"] = drawing.base64EncodedString()
        }
        if let height = block.sketchHeight { json["sketchHeight"] = height }
        // Same reasoning for a to-do's own due date and goal: only a to-do
        // carries them, and only when one was set. They are written by hand
        // like every other field rather than as an opaque blob, so the column
        // stays queryable JSON.
        if let dueDate = block.dueDate { json["dueDate"] = SupabaseREST.timestamp(dueDate) }
        if let goalID = block.goalID { json["goalID"] = goalID.uuidString.lowercased() }
        return json
    }

    static func blocks(from raw: Any?) -> [NoteBlock] {
        guard let array = raw as? [[String: Any]] else { return NoteBlock.blank }
        let blocks = array.compactMap { entry -> NoteBlock? in
            guard let kindRaw = entry["kind"] as? String,
                  let kind = NoteBlockKind(rawValue: kindRaw)
            else { return nil }
            return NoteBlock(
                id: (entry["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                kind: kind,
                text: entry["text"] as? String ?? "",
                isChecked: entry["isChecked"] as? Bool ?? false,
                indent: entry["indent"] as? Int ?? 0,
                drawing: (entry["drawing"] as? String).flatMap { Data(base64Encoded: $0) },
                sketchHeight: entry["sketchHeight"] as? Double,
                dueDate: (entry["dueDate"] as? String).flatMap(SupabaseREST.date),
                goalID: (entry["goalID"] as? String).flatMap(UUID.init(uuidString:))
            )
        }
        return blocks.isEmpty ? NoteBlock.blank : blocks
    }
}

public struct NoteFolderRow: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var bucket: String
    public var accent: String
    public var parentID: UUID?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID, name: String, icon: String, bucket: String, accent: String,
        parentID: UUID?, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bucket = bucket
        self.accent = accent
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public func payload() -> [String: Any] {
        var row: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "name": name,
            "icon": icon,
            "bucket": bucket,
            "accent": accent,
            "sort_order": sortOrder,
            "created_at": SupabaseREST.timestamp(createdAt),
            "updated_at": SupabaseREST.timestamp(updatedAt),
        ]
        row["parent_id"] = parentID.map { $0.uuidString.lowercased() } ?? NSNull()
        row["deleted_at"] = deletedAt.map { SupabaseREST.timestamp($0) } ?? NSNull()
        return row
    }

    public init?(json: [String: Any]) {
        guard let idString = json["id"] as? String, let id = UUID(uuidString: idString),
              let updated = (json["updated_at"] as? String).flatMap(SupabaseREST.date)
        else { return nil }

        self.id = id
        self.name = json["name"] as? String ?? ""
        self.icon = json["icon"] as? String ?? ""
        self.bucket = json["bucket"] as? String ?? NoteBucket.projects.rawValue
        self.accent = json["accent"] as? String ?? NoteAccent.sage.rawValue
        self.parentID = (json["parent_id"] as? String).flatMap(UUID.init(uuidString:))
        self.sortOrder = json["sort_order"] as? Int ?? 0
        self.createdAt = (json["created_at"] as? String).flatMap(SupabaseREST.date) ?? updated
        self.updatedAt = updated
        self.deletedAt = (json["deleted_at"] as? String).flatMap(SupabaseREST.date)
    }
}
