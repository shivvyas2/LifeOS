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

        let existingLinks = try context.fetch(
            FetchDescriptor<NoteLink>(predicate: #Predicate { $0.sourceID == documentID })
        )
        for row in existingLinks { context.delete(row) }

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

        // Resolved by folded title, because that is how a person writes a
        // link: by the name of the page, not its id. Titles are not unique,
        // so first match wins and the tie is stable only by fetch order. That
        // is the same tie the backlinks list already lives with.
        let titles = try titleIndex(in: context)
        for target in NoteLinkScanner.links(in: document.blocks) {
            let folded = target.lowercased()
            context.insert(
                NoteLink(
                    sourceID: documentID,
                    targetTitleFolded: folded,
                    targetID: titles[folded]
                )
            )
        }
    }

    /// Live pages by folded title. Built once per reindex rather than fetched
    /// per link, since a page with twenty links would otherwise mean twenty
    /// fetches for one keystroke.
    private static func titleIndex(in context: ModelContext) throws -> [String: UUID] {
        var index: [String: UUID] = [:]
        for document in try context.fetch(FetchDescriptor<NoteDocument>())
        where document.deletedAt == nil {
            let key = document.displayTitle.lowercased()
            if index[key] == nil { index[key] = document.id }
        }
        return index
    }
}
