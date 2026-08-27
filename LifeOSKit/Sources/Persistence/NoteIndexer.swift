import Foundation
import SwiftData

/// Mirrors a document's blocks into the derived rows.
///
/// The only writer of `NoteTask` and `NoteLink`. One writer is what makes the
/// index trustworthy: there is exactly one place that can be wrong, and one
/// function that repairs it.
///
/// Never saves. It runs inside the transaction of whatever is already changing
/// the document, so a page and its index cannot be half written with respect
/// to each other.
@MainActor
public enum NoteIndexer {

    /// Rewrites one document's rows from its blocks.
    ///
    /// Delete and reinsert rather than diff. A document holds tens of blocks,
    /// so the rewrite is cheap, and a diff would need its own correctness
    /// argument for every field. A tombstoned page is left with no rows at
    /// all, since nothing should list the to-dos of a deleted page.
    public static func reindex(_ document: NoteDocument, in context: ModelContext) throws {
        let documentID = document.id
        // Fetch and delete each, NOT `context.delete(model:where:)`. The batch
        // form runs against the persistent store and cannot see rows inserted
        // earlier in this same unsaved transaction, so a second reindex would
        // duplicate rows instead of replacing them. Fetch honours pending
        // changes; the batch delete does not.
        let existing = try context.fetch(
            FetchDescriptor<NoteTask>(predicate: #Predicate { $0.documentID == documentID })
        )
        for row in existing { context.delete(row) }

        guard document.deletedAt == nil else { return }

        for (offset, block) in document.blocks.enumerated() where block.kind == .todo {
            context.insert(
                NoteTask(
                    id: block.id,
                    documentID: documentID,
                    text: block.text,
                    isChecked: block.isChecked,
                    indent: block.indent,
                    dueDate: block.dueDate,
                    goalID: block.goalID,
                    sortOrder: offset
                )
            )
        }
    }
}
