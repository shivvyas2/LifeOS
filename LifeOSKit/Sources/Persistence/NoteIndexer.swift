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
    ///
    /// `titles` is the folded title index to resolve links against. Left nil it
    /// is built on demand, which is what a single save wants; `rebuildAll`
    /// passes one it built once, because building it per document is what made
    /// a rebuild quadratic in the size of the library.
    public static func reindex(
        _ document: NoteDocument,
        in context: ModelContext,
        titles: [String: UUID]? = nil
    ) throws {
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
                    sortOrder: offset,
                    documentUpdatedAt: document.updatedAt
                )
            )
        }

        // Scanned once, and the title index is only built when there is
        // something to resolve. Most pages carry no links at all, and the scan
        // is cheap next to a fetch of every document in the library, which the
        // editor would otherwise pay on every debounced keystroke.
        let links = NoteLinkScanner.links(in: document.blocks)
        guard !links.isEmpty else { return }

        // Resolved by folded title, because that is how a person writes a
        // link: by the name of the page, not its id. Titles are not unique,
        // so first match wins, and the fetch is ordered so that tie lands the
        // same way on every launch.
        let resolved = try titles ?? titleIndex(in: context)
        for target in links {
            let folded = target.lowercased()
            context.insert(
                NoteLink(
                    sourceID: documentID,
                    targetTitleFolded: folded,
                    targetID: resolved[folded]
                )
            )
        }
    }

    /// Throws the index away and builds it again from the documents.
    ///
    /// The repair for any inconsistency, and what runs once when the index is
    /// introduced. Starting from empty rather than reindexing page by page is
    /// what clears rows whose page has since been deleted: a per document
    /// pass never visits a page that is not there.
    @discardableResult
    public static func rebuildAll(context: ModelContext) throws -> Int {
        // The batch form is correct HERE, unlike inside `reindex`: this deletes
        // everything before anything is inserted, and the rows it clears are
        // already saved. Do not "fix" this to match reindex's fetch-and-delete.
        try context.delete(model: NoteTask.self)
        try context.delete(model: NoteLink.self)

        // Built once for the whole pass. Letting each `reindex` build its own
        // made a rebuild quadratic: one fetch of every document per document,
        // decoding the blocks of each untitled page every time, on the main
        // actor before the UI is live.
        let titles = try titleIndex(in: context)
        let documents = try context.fetch(FetchDescriptor<NoteDocument>())
        for document in documents {
            try reindex(document, in: context, titles: titles)
        }
        try context.save()
        return documents.count
    }

    /// Live pages by folded title. Built once per reindex rather than fetched
    /// per link, since a page with twenty links would otherwise mean twenty
    /// fetches for one keystroke.
    ///
    /// Ordered by `createdAt` so that when two pages share a title the older
    /// one wins, every launch. Unordered, the tie would be broken by whatever
    /// the store happened to return, and a link could point at one page today
    /// and the other tomorrow.
    private static func titleIndex(in context: ModelContext) throws -> [String: UUID] {
        var index: [String: UUID] = [:]
        let descriptor = FetchDescriptor<NoteDocument>(sortBy: [SortDescriptor(\.createdAt)])
        for document in try context.fetch(descriptor) where document.deletedAt == nil {
            let key = document.displayTitle.lowercased()
            if index[key] == nil { index[key] = document.id }
        }
        return index
    }
}
