import Foundation
import SwiftData
import Persistence

/// Pushes local note changes to Supabase and pulls back what other devices
/// wrote.
///
/// Local-first, deliberately. The editor writes to SwiftData and returns; sync
/// happens afterwards and can fail without the person ever noticing. What it
/// must never do is lose an edit, so:
///
///   - Push before pull, always. Pulling first would let a stale server row
///     overwrite an edit that has not been sent yet.
///   - `updatedAt` decides conflicts, and a tie goes to the local row. Ties
///     happen when the same device wrote both, and re-applying its own bytes
///     over the top would only clear the dirty flag it still needs.
///   - A row is marked synced only after the server has confirmed it, and the
///     mark does not touch `updatedAt`, so an edit made mid-flight stays dirty
///     and goes out on the next pass.
@MainActor
public final class NoteSync {
    private let context: ModelContext
    private let rest: SupabaseREST
    private let calendar: Calendar
    private let defaults: UserDefaults
    /// Returns a live access token, refreshing it if needed. Nil when nobody is
    /// signed in, which is not an error: the whole notes feature works offline
    /// and a guest simply never syncs.
    private let accessToken: @MainActor () async -> String?

    private static let cursorKey = "notes.sync.cursor"

    /// Coalesces the several triggers that fire together on a cold start.
    private var inFlight: Task<Void, Never>?

    public private(set) var lastError: String?
    public private(set) var lastSyncedAt: Date?

    public init(
        context: ModelContext,
        rest: SupabaseREST,
        calendar: Calendar = .current,
        defaults: UserDefaults = .currentAccount,
        accessToken: @escaping @MainActor () async -> String?
    ) {
        self.context = context
        self.rest = rest
        self.calendar = calendar
        self.defaults = defaults
        self.accessToken = accessToken
        self.lastSyncedAt = defaults.object(forKey: Self.cursorKey) as? Date
    }

    /// Runs a full pass, or joins the one already running.
    public func sync() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in await self.run() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func run() async {
        guard let token = await accessToken() else {
            // Signed out. Not an error worth surfacing: everything still works
            // locally and the first sync after signing in carries it all up.
            lastError = nil
            return
        }

        do {
            try await push(token: token)
            try await pull(token: token)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Push


    private func push(token: String) async throws {
        let store = NotesStore(context: context, calendar: calendar)

        // Folders first. A page whose folder has never been pushed would
        // otherwise arrive pointing at a row the server does not have, and
        // although `folder_id` carries no foreign key, a pull on another device
        // would file that page at the root until the folder caught up.
        let folders = try store.pendingFolders()
        let documents = try store.pendingDocuments()
        guard !folders.isEmpty || !documents.isEmpty else { return }

        if !folders.isEmpty {
            let body = try SupabaseREST.encode(folders.map { Self.row(from: $0).payload() })
            try await rest.upsert(table: "note_folders", body: body, accessToken: token)
        }

        // Batched, because a page carrying ink is large and a person who has
        // been offline for a week can have a great many of them. One oversized
        // body is a 413 that fails every page in it, including the small ones.
        for batch in stride(from: 0, to: documents.count, by: 25).map({
            Array(documents[$0..<min($0 + 25, documents.count)])
        }) {
            let body = try SupabaseREST.encode(batch.map { Self.row(from: $0).payload() })
            try await rest.upsert(table: "note_documents", body: body, accessToken: token)
            try store.markSynced(documentIDs: batch.map(\.id), folderIDs: [], at: .now)
        }

        try store.markSynced(documentIDs: [], folderIDs: folders.map(\.id), at: .now)
    }

    // MARK: - Pull

    private func pull(token: String) async throws {
        let store = NotesStore(context: context, calendar: calendar)
        // Rewound a second, so a row written by another device in the same
        // instant as our cursor is not stranded on the far side of it.
        let since = lastSyncedAt.map { $0.addingTimeInterval(-1) }

        let folderRows = SupabaseREST
            .decode(try await rest.fetch(table: "note_folders", since: since, accessToken: token))
            .compactMap(NoteFolderRow.init(json:))
        let documentRows = SupabaseREST
            .decode(try await rest.fetch(table: "note_documents", since: since, accessToken: token))
            .compactMap(NoteDocumentRow.init(json:))

        var newest = lastSyncedAt ?? .distantPast

        for row in folderRows {
            newest = max(newest, row.updatedAt)
            try apply(row, store: store)
        }
        for row in documentRows {
            newest = max(newest, row.updatedAt)
            try apply(row, store: store)
        }

        if !folderRows.isEmpty || !documentRows.isEmpty {
            context.processPendingChanges()
            try context.save()
        }

        lastSyncedAt = newest == .distantPast ? .now : newest
        defaults.set(lastSyncedAt, forKey: Self.cursorKey)
    }

    private func apply(_ row: NoteFolderRow, store: NotesStore) throws {
        let id = row.id
        let existing = try context.fetch(
            FetchDescriptor<NoteFolder>(predicate: #Predicate { $0.id == id })
        ).first

        if let existing {
            // A local edit newer than the server's copy wins and stays dirty,
            // so the next push carries it up rather than this pull flattening it.
            guard row.updatedAt > existing.updatedAt else { return }
            if row.deletedAt != nil {
                context.delete(existing)
                return
            }
            existing.name = row.name
            existing.icon = row.icon
            existing.bucketRaw = row.bucket
            existing.accentRaw = row.accent
            existing.parentID = row.parentID
            existing.sortOrder = row.sortOrder
            existing.updatedAt = row.updatedAt
            existing.syncedAt = .now
            return
        }

        // A tombstone for a row this device never had is already satisfied.
        guard row.deletedAt == nil else { return }

        let folder = NoteFolder(
            id: row.id,
            name: row.name,
            icon: row.icon,
            bucket: NoteBucket(rawValue: row.bucket) ?? .projects,
            accent: NoteAccent(rawValue: row.accent) ?? .sage,
            parentID: row.parentID,
            sortOrder: row.sortOrder,
            createdAt: row.createdAt
        )
        folder.updatedAt = row.updatedAt
        folder.syncedAt = .now
        context.insert(folder)
    }

    /// Internal rather than private so the index wiring can be tested without
    /// standing up a network. Nothing outside this package calls it.
    func apply(_ row: NoteDocumentRow, store: NotesStore) throws {
        let id = row.id
        let existing = try context.fetch(
            FetchDescriptor<NoteDocument>(predicate: #Predicate { $0.id == id })
        ).first

        if let existing {
            guard row.updatedAt > existing.updatedAt else { return }
            if row.deletedAt != nil {
                // Clear the index before the page goes, since a deleted row
                // cannot be reindexed afterwards.
                existing.deletedAt = row.deletedAt
                try NoteIndexer.reindex(existing, in: context)
                context.delete(existing)
                return
            }
            existing.title = row.title
            existing.icon = row.icon
            existing.kindRaw = row.kind
            existing.bucketRaw = row.bucket
            existing.accentRaw = row.accent
            existing.folderID = row.folderID
            existing.blocks = row.blocks
            // Ink that was too large to push comes back null. Keeping what is
            // on disk is right: null means "not carried", not "erased", and
            // clearing it here would let one oversized page delete its own
            // drawing on the device that made it.
            if let drawing = row.drawing { existing.drawingData = drawing }
            existing.entryDate = row.entryDate
            existing.dueDate = row.dueDate
            existing.statusRaw = row.status
            existing.sortOrder = row.sortOrder
            existing.isFavorite = row.isFavorite
            existing.archivedAt = row.archivedAt
            existing.updatedAt = row.updatedAt
            existing.syncedAt = .now
            // Derived rows never travel, so each device builds its own from
            // whatever it just pulled.
            try NoteIndexer.reindex(existing, in: context)
            return
        }

        guard row.deletedAt == nil else { return }

        let document = NoteDocument(
            id: row.id,
            title: row.title,
            icon: row.icon,
            kind: NoteKind(rawValue: row.kind) ?? .note,
            bucket: NoteBucket(rawValue: row.bucket) ?? .projects,
            accent: NoteAccent(rawValue: row.accent) ?? .sage,
            folderID: row.folderID,
            blocks: row.blocks,
            entryDate: row.entryDate,
            dueDate: row.dueDate,
            status: PlanStatus(rawValue: row.status) ?? .todo,
            sortOrder: row.sortOrder,
            createdAt: row.createdAt
        )
        document.drawingData = row.drawing
        // A page arriving from another device was filed on the device that made
        // it, so it is not new capture here and does not belong in this
        // device's Inbox. `filed_at` is not on the wire in this phase; phase 3
        // adds the real column and replaces this stand-in. Insert path only:
        // an update must not refile a page the person has since unfiled.
        document.filedAt = row.createdAt
        document.isFavorite = row.isFavorite
        document.openedAt = row.openedAt
        document.archivedAt = row.archivedAt
        document.updatedAt = row.updatedAt
        document.syncedAt = .now
        context.insert(document)
        try NoteIndexer.reindex(document, in: context)
    }

    // MARK: - Model to row

    static func row(from document: NoteDocument) -> NoteDocumentRow {
        NoteDocumentRow(
            id: document.id,
            title: document.title,
            icon: document.icon,
            kind: document.kindRaw,
            bucket: document.bucketRaw,
            accent: document.accentRaw,
            folderID: document.folderID,
            blocks: document.blocks,
            drawing: document.drawingData,
            entryDate: document.entryDate,
            dueDate: document.dueDate,
            status: document.statusRaw,
            sortOrder: document.sortOrder,
            isFavorite: document.isFavorite,
            openedAt: document.openedAt,
            archivedAt: document.archivedAt,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            deletedAt: document.deletedAt
        )
    }

    static func row(from folder: NoteFolder) -> NoteFolderRow {
        NoteFolderRow(
            id: folder.id,
            name: folder.name,
            icon: folder.icon,
            bucket: folder.bucketRaw,
            accent: folder.accentRaw,
            parentID: folder.parentID,
            sortOrder: folder.sortOrder,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt,
            deletedAt: folder.deletedAt
        )
    }
}
