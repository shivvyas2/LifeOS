import Foundation
import SwiftData

/// What a note is for, which decides how it is listed rather than how it is
/// edited. Every kind is the same block document underneath.
public enum NoteKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A page someone wrote on purpose.
    case note
    /// A dated entry. Titled by its day and sorted by it.
    case journal
    /// A page that exists to hold to-dos: what the old plan tab called a goal
    /// or a habit.
    case task

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .note:    "Notes"
        case .journal: "Journal"
        case .task:    "Tasks"
        }
    }

    public var systemImage: String {
        switch self {
        case .note:    "doc.text"
        case .journal: "book.closed"
        case .task:    "checklist"
        }
    }
}

/// A folder on one of the PARA shelves.
///
/// Folders nest one level in practice and arbitrarily in the model, because the
/// sidebar in the reference this was drawn from shows sub-folders and the
/// alternative is a second model that means almost the same thing.
@Model
public final class NoteFolder {
    public var id: UUID = UUID()
    public var name: String = ""
    /// An emoji, or empty for the coloured dot.
    public var icon: String = ""
    public var bucketRaw: String = NoteBucket.projects.rawValue
    public var accentRaw: String = NoteAccent.sage.rawValue
    /// Nil for a folder that sits directly on its shelf.
    public var parentID: UUID?
    public var sortOrder: Int = 0
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// Last time the server confirmed this row. Nil means it has never been
    /// pushed. `updatedAt > syncedAt` is the whole dirty test.
    public var syncedAt: Date?
    /// A tombstone rather than a delete, so a folder removed on one device
    /// disappears on the other instead of coming back on the next pull.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "",
        bucket: NoteBucket,
        accent: NoteAccent = .sage,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bucketRaw = bucket.rawValue
        self.accentRaw = accent.rawValue
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var bucket: NoteBucket {
        get { NoteBucket(rawValue: bucketRaw) ?? .projects }
        set { bucketRaw = newValue.rawValue }
    }

    public var accent: NoteAccent {
        get { NoteAccent(rawValue: accentRaw) ?? .sage }
        set { accentRaw = newValue.rawValue }
    }

    public var needsPush: Bool {
        guard let syncedAt else { return true }
        return updatedAt > syncedAt
    }
}

/// One page: a note, a journal entry, or a list of to-dos.
///
/// Every field carries a default because SwiftData needs one to add a property
/// to an existing store without a migration plan, and this model will grow.
@Model
public final class NoteDocument {
    public var id: UUID = UUID()
    public var title: String = ""
    /// An emoji shown before the title, Notion style. Empty means none.
    public var icon: String = ""
    public var kindRaw: String = NoteKind.note.rawValue
    public var bucketRaw: String = NoteBucket.projects.rawValue
    public var accentRaw: String = NoteAccent.sage.rawValue
    /// Nil for a page filed on the shelf itself rather than in a folder.
    public var folderID: UUID?

    /// The blocks, JSON encoded. See `NoteBlock` for why this is not a
    /// relationship.
    public var blocksData: Data = Data()

    /// A `PKDrawing`, when someone has inked on the page. Nil is the common
    /// case and costs nothing; a page that has been drawn on carries its ink
    /// here and syncs it base64 encoded.
    public var drawingData: Data?

    /// Journal entries and dated project pages. Nil for an undated note.
    public var entryDate: Date?
    /// When the page is meant to be finished. Projects have one; areas, by
    /// definition, do not.
    public var dueDate: Date?
    /// A page property, in the Notion sense, and the same four states the plan
    /// tab used. Reusing `PlanStatus` rather than declaring a parallel enum is
    /// what lets the monthly close read goal progress off notes without
    /// learning a second vocabulary.
    public var statusRaw: String = PlanStatus.todo.rawValue
    public var sortOrder: Int = 0
    public var isFavorite: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// Drives the Recent list. Written on open, not on edit, because "what I
    /// was last looking at" is the question that list answers.
    public var openedAt: Date?
    /// Set when the page is archived. The Archive shelf is this flag, not a
    /// bucket, so a restored page returns to the shelf it came from instead of
    /// needing to be refiled.
    public var archivedAt: Date?
    /// When someone decided where this page belongs. Nil means it is still in
    /// the Inbox.
    ///
    /// The whole Inbox is this one field. A bucket cannot answer the question,
    /// because every page has a bucket from the moment it is created, whether
    /// or not anyone chose it. Stamped by filing, never by editing, so a page
    /// you keep writing in stays in the Inbox until you decide otherwise.
    public var filedAt: Date?
    public var syncedAt: Date?
    public var deletedAt: Date?

    /// The plan entry this page was migrated from, so the one-time migration
    /// is idempotent and a peer device does not produce a second copy.
    public var originPlanEntryID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "",
        icon: String = "",
        kind: NoteKind = .note,
        bucket: NoteBucket = .projects,
        accent: NoteAccent = .sage,
        folderID: UUID? = nil,
        blocks: [NoteBlock] = NoteBlock.blank,
        entryDate: Date? = nil,
        dueDate: Date? = nil,
        status: PlanStatus = .todo,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        originPlanEntryID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.kindRaw = kind.rawValue
        self.bucketRaw = bucket.rawValue
        self.accentRaw = accent.rawValue
        self.folderID = folderID
        self.blocksData = (try? JSONEncoder().encode(blocks)) ?? Data()
        self.entryDate = entryDate
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.originPlanEntryID = originPlanEntryID
    }

    public var kind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    public var bucket: NoteBucket {
        get { NoteBucket(rawValue: bucketRaw) ?? .projects }
        set { bucketRaw = newValue.rawValue }
    }

    public var accent: NoteAccent {
        get { NoteAccent(rawValue: accentRaw) ?? .sage }
        set { accentRaw = newValue.rawValue }
    }

    public var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    /// Decoding failure returns a blank page rather than throwing. A note whose
    /// JSON cannot be read is already lost; handing the editor an empty
    /// document at least leaves the person somewhere they can type, and the
    /// original bytes stay on disk until they save over them.
    public var blocks: [NoteBlock] {
        get {
            guard !blocksData.isEmpty,
                  let decoded = try? JSONDecoder().decode([NoteBlock].self, from: blocksData)
            else { return NoteBlock.blank }
            return decoded.isEmpty ? NoteBlock.blank : decoded
        }
        set {
            blocksData = (try? JSONEncoder().encode(newValue)) ?? blocksData
        }
    }

    public var isArchived: Bool { archivedAt != nil }

    public var isInInbox: Bool { filedAt == nil && archivedAt == nil }

    public var needsPush: Bool {
        guard let syncedAt else { return true }
        return updatedAt > syncedAt
    }

    /// What to show when the title was never filled in. A note is created the
    /// moment someone taps new, before they have decided what it is, and
    /// "Untitled" everywhere is worse than the first line they typed.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = blocks.first { $0.kind.isTextual && !$0.isEmpty }?.text
        if let firstLine, !firstLine.isEmpty {
            return firstLine.count <= 60 ? firstLine : String(firstLine.prefix(60)) + "..."
        }
        return "Untitled"
    }
}
