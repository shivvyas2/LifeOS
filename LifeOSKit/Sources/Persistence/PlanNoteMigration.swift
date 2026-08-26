import Foundation
import SwiftData

/// Moves what the plan tab held into the PARA note tree, once.
///
/// Goals, content items, loose notes and journal entries all become pages.
/// Habits deliberately do not: a habit is a daily tick with a streak behind it,
/// Today toggles those ticks live, and turning one into a document would either
/// break Today or leave two rows claiming to be the same habit. Habits stay in
/// `PlanEntry` and the notes tab renders them from there.
///
/// The original plan rows are left in place. They are what the months already
/// closed were scored against, and rewriting history to match a new filing
/// system is exactly the kind of thing an app should never do behind someone's
/// back.
@MainActor
public enum PlanNoteMigration {

    /// Where each migrated kind lands. PARA's own rule decides this: work with
    /// an end goes to Projects, a standing commitment to Areas, and things kept
    /// but not acted on to Research.
    static func destination(for kind: PlanKind) -> (bucket: NoteBucket, folder: String, noteKind: NoteKind)? {
        switch kind {
        case .goal:    (.projects, "Goals", .task)
        case .content: (.projects, "Content", .task)
        case .note:    (.research, "Notes", .note)
        case .journal: (.areas, "Journal", .journal)
        case .habit:   nil
        }
    }

    /// Runs the migration if it has not run for these rows before.
    ///
    /// Idempotent through `originPlanEntryID` rather than through a flag in
    /// `UserDefaults`: a flag says "this device has migrated", which is the
    /// wrong question once a second device syncs the same pages down. Returns
    /// how many pages were created, for the log line.
    @discardableResult
    public static func run(context: ModelContext, calendar: Calendar = .current) throws -> Int {
        let store = NotesStore(context: context, calendar: calendar)
        let plan = PlanStore(context: context, calendar: calendar)

        let alreadyMigrated = Set(
            try context.fetch(FetchDescriptor<NoteDocument>()).compactMap(\.originPlanEntryID)
        )

        var folderIDs: [String: UUID] = [:]
        for folder in try store.folders() { folderIDs[folder.name] = folder.id }

        var created = 0

        for kind in PlanKind.allCases {
            guard let destination = destination(for: kind) else { continue }

            let entries = try plan.entries(kind: kind).filter { !alreadyMigrated.contains($0.id) }
            guard !entries.isEmpty else { continue }

            // The folder is made only when there is something to put in it, so
            // a person who never used the plan tab does not inherit four empty
            // folders they now have to tidy up.
            let folderID: UUID
            if let existing = folderIDs[destination.folder] {
                folderID = existing
            } else {
                let folder = try store.createFolder(name: destination.folder, bucket: destination.bucket)
                folderIDs[destination.folder] = folder.id
                folderID = folder.id
            }

            for entry in entries {
                var blocks: [NoteBlock] = []
                if let detail = entry.detail, !detail.isEmpty {
                    blocks.append(contentsOf: NoteBlockParser.blocks(fromMarkdown: detail))
                }
                if blocks.isEmpty { blocks = NoteBlock.blank }

                let document = try store.createDocument(
                    // A journal entry never had a title: its whole text was the
                    // title field. Migrating that into the title would produce a
                    // page whose heading is a paragraph, so the day becomes the
                    // title and the text becomes the first block.
                    title: kind == .journal
                        ? entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
                        : entry.title,
                    kind: destination.noteKind,
                    bucket: destination.bucket,
                    folderID: folderID,
                    blocks: kind == .journal
                        ? NoteBlockParser.blocks(fromMarkdown: entry.title)
                        : blocks,
                    entryDate: kind == .journal ? calendar.startOfDay(for: entry.createdAt) : nil,
                    dueDate: entry.dueDate,
                    status: entry.status
                )
                document.originPlanEntryID = entry.id
                document.createdAt = entry.createdAt
                document.updatedAt = entry.updatedAt
                created += 1
            }
        }

        if created > 0 { try context.save() }
        return created
    }

    /// Seeds the one folder the app itself writes into, so the first journal
    /// entry has somewhere to land. Runs only when the tree is completely
    /// empty: the shelves are the person's to organise, and pre-filling them
    /// with folders nobody asked for is how a fresh install feels like someone
    /// else's mess.
    public static func seedIfEmpty(context: ModelContext, calendar: Calendar = .current) throws {
        let store = NotesStore(context: context, calendar: calendar)
        guard try store.folders().isEmpty, try store.documents(includeArchived: true).isEmpty else { return }
        try store.createFolder(name: "Journal", bucket: .areas, icon: "\u{1F5D3}")
    }
}
