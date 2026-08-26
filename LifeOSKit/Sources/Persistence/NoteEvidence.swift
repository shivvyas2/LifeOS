import Foundation
import SwiftData

/// What the monthly close needs to know about notes.
///
/// The close used to read journal entries and goal statuses straight off
/// `PlanEntry`. Those two things now live on note pages, so this is the bridge:
/// it returns both the new pages and the rows the migration deliberately left
/// behind, because a month already closed must keep scoring the way it did.
@MainActor
public enum NoteEvidence {

    /// The dates journal pages were written on, for the journalling streak.
    /// `entryDate` is the day the entry is *about*, which is the one that
    /// matters: writing Tuesday's entry on Wednesday morning still counts for
    /// Tuesday.
    public static func journalDates(context: ModelContext) throws -> [Date] {
        try NotesStore(context: context)
            .documents(includeArchived: true)
            .filter { $0.kind == .journal }
            .map { $0.entryDate ?? $0.createdAt }
    }

    /// Statuses of every project page, which is what a goal became.
    ///
    /// A page with to-do blocks reports what those blocks say rather than its
    /// own property: ticking the last box on a page is a clearer statement that
    /// the thing is done than remembering to flip a menu afterwards.
    public static func projectStatuses(context: ModelContext) throws -> [(status: PlanStatus, updatedAt: Date)] {
        try NotesStore(context: context)
            .documents(includeArchived: true)
            .filter { $0.bucket == .projects || $0.kind == .task }
            .map { document in
                let progress = NoteBlockParser.taskProgress(document.blocks)
                guard progress.total > 0 else { return (document.status, document.updatedAt) }
                if progress.done == progress.total { return (.done, document.updatedAt) }
                if progress.done > 0 { return (.inProgress, document.updatedAt) }
                return (document.status, document.updatedAt)
            }
    }
}
