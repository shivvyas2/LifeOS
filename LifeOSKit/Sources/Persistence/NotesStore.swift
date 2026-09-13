import Foundation
import SwiftData

/// Reads and writes the PARA note tree.
///
/// Every method that changes something stamps `updatedAt`, which is both what
/// orders the recent list and what marks a row for the next push. Forgetting
/// that stamp is the one bug that silently stops sync, so no caller sets it.
@MainActor
public struct NotesStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Reading

    /// Live pages, tombstones excluded. Every read funnels through here so a
    /// deleted row can never surface from a path that forgot the predicate.
    public func documents(includeArchived: Bool = false) throws -> [NoteDocument] {
        let all = try context.fetch(
            FetchDescriptor<NoteDocument>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )
        return all.filter { $0.deletedAt == nil && (includeArchived || !$0.isArchived) }
    }

    public func document(id: UUID) throws -> NoteDocument? {
        try context.fetch(FetchDescriptor<NoteDocument>(predicate: #Predicate { $0.id == id }))
            .first { $0.deletedAt == nil }
    }

    public func folders(includeDeleted: Bool = false) throws -> [NoteFolder] {
        let all = try context.fetch(
            FetchDescriptor<NoteFolder>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        )
        return includeDeleted ? all : all.filter { $0.deletedAt == nil }
    }

    public func folder(id: UUID) throws -> NoteFolder? {
        try context.fetch(FetchDescriptor<NoteFolder>(predicate: #Predicate { $0.id == id }))
            .first { $0.deletedAt == nil }
    }

    /// The pages on one shelf, optionally narrowed to one folder and one kind.
    ///
    /// `folder: .some(nil)` means "filed on the shelf itself"; `folder: nil`
    /// means "anywhere on the shelf". The double optional is ugly and the two
    /// questions are genuinely different, so it earns its keep.
    public func cards(
        bucket: NoteBucket,
        folder: UUID?? = nil,
        kind: NoteKind? = nil
    ) throws -> [NoteCardSnapshot] {
        let names = try folderNames()
        let archived = bucket == .archive

        return try documents(includeArchived: true)
            .filter { document in
                guard document.isArchived == archived else { return false }
                // An archived page keeps the shelf it was filed on, so that
                // restoring it needs no decision. The archive shelf therefore
                // ignores `bucket` entirely and shows the lot.
                if !archived, document.bucket != bucket { return false }
                if let folder, document.folderID != folder { return false }
                if let kind, document.kind != kind { return false }
                return true
            }
            .sorted(by: Self.displayOrder)
            .map { card($0, folderNames: names) }
    }

    /// Recently opened, for the sidebar's top row. Falls back to recently
    /// edited for pages that predate `openedAt`.
    public func recent(limit: Int = 8) throws -> [NoteCardSnapshot] {
        let names = try folderNames()
        return try documents(includeArchived: false)
            .sorted { ($0.openedAt ?? $0.updatedAt) > ($1.openedAt ?? $1.updatedAt) }
            .prefix(limit)
            .map { card($0, folderNames: names) }
    }

    public func favorites() throws -> [NoteCardSnapshot] {
        let names = try folderNames()
        return try documents(includeArchived: false)
            .filter(\.isFavorite)
            .sorted(by: Self.displayOrder)
            .map { card($0, folderNames: names) }
    }

    /// The whole sidebar in one pass: folder tree per shelf, page counts, the
    /// recent list and the favourites. Four separate reads would each walk the
    /// same rows.
    public func snapshot() throws -> NotesSnapshot {
        let allFolders = try folders()
        let allDocuments = try documents(includeArchived: true)

        // Direct page counts per folder, before any child folder is rolled in.
        var direct: [UUID: Int] = [:]
        for document in allDocuments where !document.isArchived {
            guard let folderID = document.folderID else { continue }
            direct[folderID, default: 0] += 1
        }

        var childrenOf: [UUID?: [NoteFolder]] = [:]
        for folder in allFolders {
            childrenOf[folder.parentID, default: []].append(folder)
        }

        func build(_ folder: NoteFolder) -> NoteFolderSnapshot {
            let children = (childrenOf[folder.id] ?? []).map(build)
            return NoteFolderSnapshot(
                id: folder.id,
                name: folder.name,
                icon: folder.icon,
                accent: folder.accent,
                bucket: folder.bucket,
                parentID: folder.parentID,
                count: (direct[folder.id] ?? 0) + children.reduce(0) { $0 + $1.count },
                children: children
            )
        }

        var tree: [NoteBucket: [NoteFolderSnapshot]] = [:]
        for root in childrenOf[nil] ?? [] {
            tree[root.bucket, default: []].append(build(root))
        }

        var counts: [NoteBucket: Int] = [:]
        for document in allDocuments {
            if document.isArchived {
                counts[.archive, default: 0] += 1
            } else {
                counts[document.bucket, default: 0] += 1
            }
        }

        return NotesSnapshot(
            folders: tree,
            counts: counts,
            recent: try recent(),
            favorites: try favorites(),
            totalCount: allDocuments.filter { !$0.isArchived }.count
        )
    }

    /// Title, excerpt and folder name search across live pages. Substring, case
    /// and diacritic insensitive: there is no index here and there does not
    /// need to be one until a person has thousands of notes.
    public func search(_ query: String, limit: Int = 40) throws -> [NoteCardSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let names = try folderNames()

        func matches(_ haystack: String) -> Bool {
            haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        return try documents(includeArchived: true)
            .filter { document in
                matches(document.displayTitle)
                    || document.blocks.contains { matches($0.text) }
            }
            .sorted(by: Self.displayOrder)
            .prefix(limit)
            .map { card($0, folderNames: names) }
    }

    /// Pages whose text contains `[[title]]`. Matched case insensitively so a
    /// link typed in lower case still finds a capitalised page.
    public func backlinks(to title: String) throws -> [NoteBacklink] {
        let target = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return [] }

        return try documents(includeArchived: true).compactMap { document in
            guard let block = document.blocks.first(where: { block in
                NoteLinkScanner.links(in: block.text).contains { $0.lowercased() == target }
            }) else { return nil }

            return NoteBacklink(
                id: document.id,
                title: document.displayTitle,
                accent: document.accent,
                context: block.text
            )
        }
    }

    /// The indexed to-dos, newest page first and in written order within a
    /// page. What the To-dos chip reads.
    public func indexedTasks(openOnly: Bool = false) throws -> [NoteTask] {
        let rows = try context.fetch(
            FetchDescriptor<NoteTask>(
                sortBy: [
                    SortDescriptor(\.documentUpdatedAt, order: .reverse),
                    SortDescriptor(\.sortOrder),
                ]
            )
        )
        return openOnly ? rows.filter { !$0.isChecked } : rows
    }

    /// Every link edge. The mindmap's input.
    public func indexedLinks() throws -> [NoteLink] {
        try context.fetch(FetchDescriptor<NoteLink>())
    }

    /// Captured and not yet filed, newest first. The phone's first screen.
    ///
    /// Newest first rather than `displayOrder`: the Inbox is a capture queue,
    /// and the thing you just wrote is the thing you are still thinking about.
    public func inbox() throws -> [NoteCardSnapshot] {
        try cardsNewestFirst(filter: \.isInInbox)
    }

    /// Live pages, newest first, mapped to cards. `inbox()` and
    /// `stream(for: .all)` differ only in which documents qualify, so the
    /// sort and the mapping to a card live here once rather than twice
    /// slowly drifting apart.
    private func cardsNewestFirst(filter: (NoteDocument) -> Bool = { _ in true }) throws -> [NoteCardSnapshot] {
        let names = try folderNames()
        return try documents(includeArchived: false)
            .filter(filter)
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { card($0, folderNames: names) }
    }

    /// The rows one chip shows. The single place a chip's meaning lives, so
    /// the view never decides what "All" includes.
    public func stream(for chip: NoteStreamChip) throws -> NoteStream {
        switch chip {
        case .inbox:
            return .cards(try inbox())

        case .all:
            return .cards(try cardsNewestFirst())

        case .todos:
            // The index keeps a page's task rows when it is archived, so the
            // filter belongs here. Clearing rows on archive instead would
            // change what the index means for sync and for every future
            // consumer, which is a far larger change than this chip needs.
            let live = Set(try documents(includeArchived: false).map(\.id))
            return .tasks(try indexedTasks(openOnly: true).filter { live.contains($0.documentID) })
        }
    }

    /// The page a `[[link]]` points at, matched on title. Nil when nothing
    /// carries that title yet, which is the cue to offer creating it.
    public func document(titled title: String) throws -> NoteDocument? {
        let target = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        return try documents(includeArchived: true)
            .first { $0.displayTitle.lowercased() == target }
    }

    // MARK: - Writing

    @discardableResult
    public func createFolder(
        name: String,
        bucket: NoteBucket,
        parentID: UUID? = nil,
        icon: String = ""
    ) throws -> NoteFolder {
        let siblings = try folders().filter { $0.bucket == bucket && $0.parentID == parentID }
        let folder = NoteFolder(
            name: name,
            icon: icon,
            bucket: bucket,
            accent: .next(after: try folders().count),
            parentID: parentID,
            sortOrder: (siblings.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    @discardableResult
    public func createDocument(
        title: String = "",
        kind: NoteKind = .note,
        bucket: NoteBucket,
        folderID: UUID? = nil,
        blocks: [NoteBlock] = NoteBlock.blank,
        entryDate: Date? = nil,
        dueDate: Date? = nil,
        status: PlanStatus = .todo
    ) throws -> NoteDocument {
        // A page inherits its folder's colour, so a shelf reads as a set of
        // coloured groups rather than as confetti.
        let accent: NoteAccent
        if let folderID, let folder = try folder(id: folderID) {
            accent = folder.accent
        } else {
            accent = .next(after: try documents(includeArchived: true).count)
        }

        let document = NoteDocument(
            title: title,
            kind: kind,
            bucket: bucket,
            accent: accent,
            folderID: folderID,
            blocks: blocks,
            entryDate: entryDate,
            dueDate: dueDate,
            status: status,
            sortOrder: 0
        )
        document.openedAt = .now
        // Choosing a folder is choosing a home, so a page created into one is
        // already filed. A page created loose on a shelf is not: phase 1's
        // rule is that a note starts unfiled and stays that way while it is
        // only being written in, and deciding where it belongs is what files
        // it. Only an explicit folder counts as that decision.
        if folderID != nil { document.filedAt = .now }
        context.insert(document)
        try NoteIndexer.reindex(document, in: context)
        try context.save()
        return document
    }

    /// One line of text, straight into the Inbox.
    ///
    /// The title is deliberately left empty: `NoteDocument.displayTitle`
    /// already falls back to the first textual block, so a captured thought
    /// reads correctly on a card without storing the same sentence twice.
    ///
    /// `filedAt` is untouched, which is what puts the page in the Inbox.
    /// Filing it later through `move(_:to:folderID:)` is what stamps it and
    /// takes it out again.
    ///
    /// Returns nil for text that is empty once trimmed, so the composer can
    /// bind Return unconditionally instead of guarding at the call site.
    @discardableResult
    public func capture(_ text: String, isTodo: Bool = false) throws -> NoteDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return try createDocument(
            bucket: .areas,
            blocks: [NoteBlock(kind: isTodo ? .todo : .paragraph, text: trimmed)]
        )
    }

    /// Today's journal entry, created on first write rather than on first
    /// launch: an empty page dated every day is noise, not a journal.
    @discardableResult
    public func journalEntry(on date: Date = .now, in bucket: NoteBucket = .areas) throws -> NoteDocument {
        let day = calendar.startOfDay(for: date)
        if let existing = try documents(includeArchived: true).first(where: {
            $0.kind == .journal && $0.entryDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }) {
            return existing
        }

        return try createDocument(
            title: day.formatted(.dateTime.weekday(.wide).month(.wide).day()),
            kind: .journal,
            bucket: bucket,
            entryDate: day
        )
    }

    public func update(_ document: NoteDocument, blocks: [NoteBlock]) throws {
        guard document.blocks != blocks else { return }
        document.blocks = blocks
        try touch(document)
    }

    public func rename(_ document: NoteDocument, to title: String) throws {
        document.title = title
        try touch(document)
    }

    public func setIcon(_ icon: String, on document: NoteDocument) throws {
        document.icon = icon
        try touch(document)
    }

    public func setAccent(_ accent: NoteAccent, on document: NoteDocument) throws {
        document.accent = accent
        try touch(document)
    }

    public func setStatus(_ status: PlanStatus, on document: NoteDocument) throws {
        document.status = status
        try touch(document)
    }

    public func setDueDate(_ date: Date?, on document: NoteDocument) throws {
        document.dueDate = date
        try touch(document)
    }

    public func setDrawing(_ data: Data?, on document: NoteDocument) throws {
        document.drawingData = data
        try touch(document)
    }

    public func move(_ document: NoteDocument, to bucket: NoteBucket, folderID: UUID?) throws {
        document.bucket = bucket
        document.folderID = folderID
        // Choosing a home is what files a page. Editing one never does.
        if document.filedAt == nil { document.filedAt = .now }
        try touch(document)
    }

    public func toggleFavorite(_ document: NoteDocument) throws {
        document.isFavorite.toggle()
        try touch(document)
    }

    /// Opening is recorded separately from editing. It advances `openedAt` but
    /// not `updatedAt`, so reading a page on one device does not fabricate an
    /// edit that wins a sync conflict against a real one on another.
    public func markOpened(_ document: NoteDocument) throws {
        document.openedAt = .now
        try context.save()
    }

    public func archive(_ document: NoteDocument) throws {
        document.archivedAt = .now
        try touch(document)
    }

    public func unarchive(_ document: NoteDocument) throws {
        document.archivedAt = nil
        try touch(document)
    }

    /// A tombstone, not a delete: the row has to survive long enough to tell
    /// the server the page is gone. `NoteSync` reaps it once the push lands.
    public func delete(_ document: NoteDocument) throws {
        document.deletedAt = .now
        try touch(document)
    }

    public func rename(_ folder: NoteFolder, to name: String) throws {
        folder.name = name
        try touch(folder)
    }

    public func setAccent(_ accent: NoteAccent, on folder: NoteFolder) throws {
        folder.accent = accent
        try touch(folder)
    }

    /// Deleting a folder empties it onto its shelf rather than taking the pages
    /// with it. Losing a folder is an organising decision; losing what was in
    /// it is not the same decision and must never be made by implication.
    public func delete(_ folder: NoteFolder) throws {
        for document in try documents(includeArchived: true) where document.folderID == folder.id {
            document.folderID = folder.parentID
            document.updatedAt = .now
            // These pages change outside `touch`, so the index has to be
            // rewritten by hand here or their rows keep the old
            // `documentUpdatedAt` and every cross page list orders them wrong.
            // The single save at the end still covers the whole move.
            try NoteIndexer.reindex(document, in: context)
        }
        for child in try folders() where child.parentID == folder.id {
            child.parentID = folder.parentID
            child.updatedAt = .now
        }
        folder.deletedAt = .now
        try touch(folder)
    }

    // MARK: - Sync support

    public func pendingDocuments() throws -> [NoteDocument] {
        try context.fetch(FetchDescriptor<NoteDocument>()).filter(\.needsPush)
    }

    public func pendingFolders() throws -> [NoteFolder] {
        try context.fetch(FetchDescriptor<NoteFolder>()).filter(\.needsPush)
    }

    /// Called after the server confirms a row. Deliberately does not touch
    /// `updatedAt`: an edit made while the push was in flight must stay dirty.
    public func markSynced(documentIDs: [UUID], folderIDs: [UUID], at date: Date = .now) throws {
        let documents = Set(documentIDs)
        let folders = Set(folderIDs)

        for document in try context.fetch(FetchDescriptor<NoteDocument>()) where documents.contains(document.id) {
            document.syncedAt = date
            // The tombstone has done its job once the server has it.
            if document.deletedAt != nil { context.delete(document) }
        }
        for folder in try context.fetch(FetchDescriptor<NoteFolder>()) where folders.contains(folder.id) {
            folder.syncedAt = date
            if folder.deletedAt != nil { context.delete(folder) }
        }
        try context.save()
    }

    // MARK: - Helpers

    private func touch(_ document: NoteDocument) throws {
        document.updatedAt = .now
        // Every document mutation funnels through here, which is exactly why
        // the index is rewritten here and nowhere else. A path that forgot to
        // reindex would show a stale to-do list with no other symptom.
        try NoteIndexer.reindex(document, in: context)
        try context.save()
    }

    private func touch(_ folder: NoteFolder) throws {
        folder.updatedAt = .now
        try context.save()
    }

    private func folderNames() throws -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: try folders().map { ($0.id, $0.name) })
    }

    /// Favourites first, then dated entries newest first, then everything else
    /// by last edit. One comparator so a shelf, a folder and a search result
    /// never disagree about what "first" means.
    private static func displayOrder(_ a: NoteDocument, _ b: NoteDocument) -> Bool {
        if a.isFavorite != b.isFavorite { return a.isFavorite }
        switch (a.entryDate, b.entryDate) {
        case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
        case (.some, .none): return true
        case (.none, .some): return false
        default: return a.updatedAt > b.updatedAt
        }
    }

    private func card(_ document: NoteDocument, folderNames: [UUID: String]) -> NoteCardSnapshot {
        let blocks = document.blocks
        let progress = NoteBlockParser.taskProgress(blocks)

        return NoteCardSnapshot(
            id: document.id,
            title: document.displayTitle,
            icon: document.icon,
            excerpt: NoteBlockParser.excerpt(blocks),
            accent: document.accent,
            kind: document.kind,
            bucket: document.bucket,
            folderID: document.folderID,
            folderName: document.folderID.flatMap { folderNames[$0] },
            entryDate: document.entryDate,
            dueDate: document.dueDate,
            status: document.status,
            updatedAt: document.updatedAt,
            isFavorite: document.isFavorite,
            isArchived: document.isArchived,
            doneCount: progress.done,
            taskCount: progress.total,
            hasInk: document.drawingData?.isEmpty == false,
            linkCount: NoteLinkScanner.links(in: blocks).count,
            createdAt: document.createdAt,
            openedAt: document.openedAt
        )
    }
}
