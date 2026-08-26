import Foundation

/// A note, flattened for display. Views never hold a `NoteDocument`: the app's
/// rule is that nothing below the composition root touches SwiftData, and a
/// managed object handed to a card is exactly how that rule dies.
public struct NoteCardSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let icon: String
    public let excerpt: String
    public let accent: NoteAccent
    public let kind: NoteKind
    public let bucket: NoteBucket
    public let folderID: UUID?
    public let folderName: String?
    public let entryDate: Date?
    public let dueDate: Date?
    public let status: PlanStatus
    public let updatedAt: Date
    public let isFavorite: Bool
    public let isArchived: Bool
    public let doneCount: Int
    public let taskCount: Int
    public let hasInk: Bool
    public let linkCount: Int

    public init(
        id: UUID, title: String, icon: String, excerpt: String, accent: NoteAccent,
        kind: NoteKind, bucket: NoteBucket, folderID: UUID?, folderName: String?,
        entryDate: Date?, dueDate: Date?, status: PlanStatus,
        updatedAt: Date, isFavorite: Bool, isArchived: Bool,
        doneCount: Int, taskCount: Int, hasInk: Bool, linkCount: Int
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.excerpt = excerpt
        self.accent = accent
        self.kind = kind
        self.bucket = bucket
        self.folderID = folderID
        self.folderName = folderName
        self.entryDate = entryDate
        self.dueDate = dueDate
        self.status = status
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.doneCount = doneCount
        self.taskCount = taskCount
        self.hasInk = hasInk
        self.linkCount = linkCount
    }

    public var progress: Double? {
        guard taskCount > 0 else { return nil }
        return Double(doneCount) / Double(taskCount)
    }
}

/// A folder row in the sidebar, with its own children already attached. The
/// tree is built once in the store rather than by the view walking a flat list
/// on every render.
public struct NoteFolderSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String
    public let accent: NoteAccent
    public let bucket: NoteBucket
    public let parentID: UUID?
    /// Pages filed in this folder and in every folder beneath it, which is the
    /// number the reference sidebar shows next to a parent row.
    public let count: Int
    public let children: [NoteFolderSnapshot]

    public init(
        id: UUID, name: String, icon: String, accent: NoteAccent, bucket: NoteBucket,
        parentID: UUID?, count: Int, children: [NoteFolderSnapshot]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.accent = accent
        self.bucket = bucket
        self.parentID = parentID
        self.count = count
        self.children = children
    }
}

/// Everything the sidebar needs, in one read.
public struct NotesSnapshot: Equatable, Sendable {
    public let folders: [NoteBucket: [NoteFolderSnapshot]]
    public let counts: [NoteBucket: Int]
    public let recent: [NoteCardSnapshot]
    public let favorites: [NoteCardSnapshot]
    public let totalCount: Int

    public init(
        folders: [NoteBucket: [NoteFolderSnapshot]] = [:],
        counts: [NoteBucket: Int] = [:],
        recent: [NoteCardSnapshot] = [],
        favorites: [NoteCardSnapshot] = [],
        totalCount: Int = 0
    ) {
        self.folders = folders
        self.counts = counts
        self.recent = recent
        self.favorites = favorites
        self.totalCount = totalCount
    }

    public static let empty = NotesSnapshot()

    public func folders(in bucket: NoteBucket) -> [NoteFolderSnapshot] {
        folders[bucket] ?? []
    }

    public func count(in bucket: NoteBucket) -> Int { counts[bucket] ?? 0 }
}

/// A note that links to the note being read. Obsidian's backlinks pane, which
/// is the payoff for supporting `[[...]]` at all.
public struct NoteBacklink: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let accent: NoteAccent
    /// The line the link appears on, so the pane shows context rather than a
    /// bare list of titles.
    public let context: String

    public init(id: UUID, title: String, accent: NoteAccent, context: String) {
        self.id = id
        self.title = title
        self.accent = accent
        self.context = context
    }
}
