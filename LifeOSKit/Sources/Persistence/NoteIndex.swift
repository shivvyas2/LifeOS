import Foundation
import SwiftData

/// Derived rows: what the documents already say, in a shape that can be
/// queried.
///
/// Blocks live as JSON inside `NoteDocument.blocksData`, which is right for
/// editing and useless for asking "every open to-do". These models are that
/// JSON mirrored out by `NoteIndexer` on every save.
///
/// Two rules make them safe. They are never pushed, so two devices cannot
/// disagree about them. And every row is reconstructible from the documents,
/// so the repair for any inconsistency is `NoteIndexer.rebuildAll`, and the
/// worst an indexer bug can do is show a stale list.

/// One to-do block, hoisted out of its page.
@Model
public final class NoteTask {
    /// The block's own id, so the row is stable across reindexes rather than
    /// churning a new identity on every keystroke.
    ///
    /// Not unique on its own: a block copied and pasted into a second page
    /// keeps its id. Rows are scoped by `documentID` and rewritten a whole
    /// document at a time, so the pair is what identifies one to-do.
    public var id: UUID = UUID()
    public var documentID: UUID = UUID()
    public var text: String = ""
    public var isChecked: Bool = false
    public var indent: Int = 0
    public var dueDate: Date?
    public var goalID: UUID?
    /// Position in its page, so a cross note list can still show a page's
    /// to-dos in the order they were written.
    public var sortOrder: Int = 0
    /// The owning page's `updatedAt`, copied down at index time.
    ///
    /// A cross page list has to order pages somehow, and `sortOrder` cannot do
    /// it: that is a position within one page. Denormalised rather than joined
    /// because the row is rebuilt on every save anyway, so it cannot drift.
    public var documentUpdatedAt: Date = Date.distantPast

    public init(
        id: UUID = UUID(),
        documentID: UUID,
        text: String = "",
        isChecked: Bool = false,
        indent: Int = 0,
        dueDate: Date? = nil,
        goalID: UUID? = nil,
        sortOrder: Int = 0,
        documentUpdatedAt: Date = .distantPast
    ) {
        self.id = id
        self.documentID = documentID
        self.text = text
        self.isChecked = isChecked
        self.indent = indent
        self.dueDate = dueDate
        self.goalID = goalID
        self.sortOrder = sortOrder
        self.documentUpdatedAt = documentUpdatedAt
    }
}

/// One `[[wiki link]]` edge. The mindmap's edge set, and what the backlinks
/// list will read once it stops rescanning every document.
@Model
public final class NoteLink {
    public var sourceID: UUID = UUID()
    /// Lowercased, so `[[Marathon]]` and `[[marathon]]` are one edge. What was
    /// typed stays in the block; only the lookup key is folded.
    public var targetTitleFolded: String = ""
    /// Nil when the link points at a page that does not exist yet. Obsidian
    /// calls these unresolved, and they are worth keeping: a link written
    /// before its page is a to-do of its own.
    ///
    /// Non-nil is not proof the page is still there. `NoteIndexer.reindex`
    /// only rewrites the edges out of the document being saved, so renaming or
    /// deleting a page leaves every edge that pointed at it holding an id that
    /// now names something else or nothing at all. The next launch's
    /// `rebuildAll` repairs them; until then a consumer must treat the lookup
    /// as a miss it can survive, not as a page it is owed.
    public var targetID: UUID?

    public init(sourceID: UUID, targetTitleFolded: String, targetID: UUID? = nil) {
        self.sourceID = sourceID
        self.targetTitleFolded = targetTitleFolded
        self.targetID = targetID
    }
}
