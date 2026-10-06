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
    public let createdAt: Date
    public let openedAt: Date?
    public let isFavorite: Bool
    public let isArchived: Bool
    public let doneCount: Int
    public let taskCount: Int
    public let hasInk: Bool
    public let linkCount: Int
    /// Unfiled and not archived: the page is still waiting to be put away.
    public let isInInbox: Bool

    public init(
        id: UUID, title: String, icon: String, excerpt: String, accent: NoteAccent,
        kind: NoteKind, bucket: NoteBucket, folderID: UUID?, folderName: String?,
        entryDate: Date?, dueDate: Date?, status: PlanStatus,
        updatedAt: Date, isFavorite: Bool, isArchived: Bool,
        doneCount: Int, taskCount: Int, hasInk: Bool, linkCount: Int,
        createdAt: Date? = nil, openedAt: Date? = nil, isInInbox: Bool = false
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
        self.createdAt = createdAt ?? updatedAt
        self.openedAt = openedAt
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.doneCount = doneCount
        self.taskCount = taskCount
        self.hasInk = hasInk
        self.linkCount = linkCount
        self.isInInbox = isInInbox
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
    public let inboxCount: Int

    public init(
        folders: [NoteBucket: [NoteFolderSnapshot]] = [:],
        counts: [NoteBucket: Int] = [:],
        recent: [NoteCardSnapshot] = [],
        favorites: [NoteCardSnapshot] = [],
        totalCount: Int = 0, inboxCount: Int = 0
    ) {
        self.folders = folders
        self.counts = counts
        self.recent = recent
        self.favorites = favorites
        self.totalCount = totalCount
        self.inboxCount = inboxCount
    }

    public static let empty = NotesSnapshot()

    public func folders(in bucket: NoteBucket) -> [NoteFolderSnapshot] {
        folders[bucket] ?? []
    }

    public func count(in bucket: NoteBucket) -> Int { counts[bucket] ?? 0 }

    /// Everywhere a page can be filed: each shelf in `NoteBucket.filing`
    /// first, then its folders in tree order, each child named after its
    /// parent. One list, so the editor's chip, a swipe and a long-press
    /// cannot offer different places.
    public func moveTargets() -> [NoteMoveTarget] {
        var targets: [NoteMoveTarget] = []
        for bucket in NoteBucket.filing {
            targets.append(NoteMoveTarget(bucket: bucket, folderID: nil, title: bucket.title, depth: 0))
            func walk(_ folders: [NoteFolderSnapshot], prefix: String, depth: Int) {
                for folder in folders {
                    let name = prefix.isEmpty ? folder.name : "\(prefix) / \(folder.name)"
                    targets.append(NoteMoveTarget(bucket: bucket, folderID: folder.id, title: name, depth: depth))
                    walk(folder.children, prefix: name, depth: depth + 1)
                }
            }
            walk(folders(in: bucket), prefix: "", depth: 1)
        }
        return targets
    }
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

/// Somewhere a page can be filed: a shelf, or a folder on one.
public struct NoteMoveTarget: Identifiable, Hashable, Sendable {
    public let bucket: NoteBucket
    /// Nil for the shelf itself, which files the page loose on it.
    public let folderID: UUID?
    /// `Training / Drills` for a nested folder; the shelf's own name at the root.
    public let title: String
    /// 0 for the shelf, 1 for its folders, 2 for theirs.
    public let depth: Int

    public init(bucket: NoteBucket, folderID: UUID?, title: String, depth: Int = 0) {
        self.bucket = bucket; self.folderID = folderID; self.title = title; self.depth = depth
    }

    public var id: String { "\(bucket.rawValue)-\(folderID?.uuidString ?? "root")" }

    /// The last part of the title, for a row that shows its depth by indent.
    public var leafName: String {
        title.components(separatedBy: " / ").last ?? title
    }

    /// Greys out the place the page already is.
    public func isCurrentHome(of card: NoteCardSnapshot) -> Bool {
        card.bucket == bucket && card.folderID == folderID
    }

    public func isCurrentHome(bucket: NoteBucket, folderID: UUID?) -> Bool {
        self.bucket == bucket && self.folderID == folderID
    }
}
