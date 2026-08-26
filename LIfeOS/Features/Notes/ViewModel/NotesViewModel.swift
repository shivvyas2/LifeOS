import Foundation
import Observation
import SwiftData
import Persistence

/// Owns the notes tab's state: what the rail points at, what the shelf shows,
/// and every write that changes either.
///
/// Follows the pattern the rest of the app's view models use. It is the only
/// thing in the notes feature that holds a `ModelContext`; the screens below it
/// see snapshots and closures.
@Observable
@MainActor
final class NotesViewModel {
    private(set) var snapshot: NotesSnapshot = .empty
    private(set) var cards: [NoteCardSnapshot] = []
    /// Set while a search is running, so the shelf can say it is showing
    /// results rather than the folder the rail still highlights.
    private(set) var isSearching = false

    var selection: NoteSelection = .recent {
        didSet { if selection != oldValue { load() } }
    }
    var filter: NoteShelfFilter = .all {
        didSet { if filter != oldValue { load() } }
    }
    var sort: NoteSort = .recentlyEdited {
        didSet { if sort != oldValue { load() } }
    }
    var query: String = "" {
        didSet { if query != oldValue { load() } }
    }

    private var context: ModelContext?
    private var sync: NoteSyncing?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext, sync: NoteSyncing? = nil) {
        self.context = context
        self.sync = sync
    }

    private var store: NotesStore? {
        context.map { NotesStore(context: $0, calendar: calendar) }
    }

    // MARK: - Reading

    func load() {
        guard let store else { return }
        do {
            snapshot = try store.snapshot()

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            isSearching = !trimmed.isEmpty

            if isSearching {
                cards = try store.search(trimmed)
                return
            }

            switch selection {
            case .recent:
                cards = try store.recent(limit: 40)
            case .favorites:
                cards = try store.favorites()
            case .bucket(let bucket):
                cards = try store.cards(bucket: bucket, kind: filter.kind)
            case .folder(let id):
                let bucket = try store.folder(id: id)?.bucket ?? .projects
                cards = try store.cards(bucket: bucket, folder: .some(id), kind: filter.kind)
            }
            cards = sorted(cards)
        } catch {
            assertionFailure("Notes load failed: \(error)")
        }
    }

    private func sorted(_ cards: [NoteCardSnapshot]) -> [NoteCardSnapshot] {
        switch sort {
        case .recentlyEdited:
            // The store's own order already leads with favourites and dated
            // entries, which is what "recently edited" should preserve.
            return cards
        case .recentlyOpened:
            return cards.sorted { $0.updatedAt > $1.updatedAt }
        case .title:
            return cards.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .created:
            return cards.sorted { ($0.entryDate ?? $0.updatedAt) > ($1.entryDate ?? $1.updatedAt) }
        }
    }

    // MARK: - Header

    /// The shelf a new page lands on, given where the rail points. Recent and
    /// Favourites are cross-cutting lists rather than places, so a page made
    /// from either goes to Projects, which is where PARA says active work goes.
    var activeBucket: NoteBucket {
        switch selection {
        case .bucket(let bucket): bucket == .archive ? .projects : bucket
        case .folder(let id):     (try? store?.folder(id: id))??.bucket ?? .projects
        default:                  .projects
        }
    }

    var activeFolderID: UUID? { selection.folderID }

    var headerTitle: String {
        if isSearching { return "Search" }
        switch selection {
        case .recent:              return "Recent"
        case .favorites:           return "Favourites"
        case .bucket(let bucket):  return bucket.title
        case .folder(let id):      return folderSnapshot(id)?.name ?? "Folder"
        }
    }

    var headerBlurb: String {
        if isSearching {
            return cards.isEmpty
                ? "Nothing matches \"\(query)\" yet."
                : "\(cards.count) \(cards.count == 1 ? "page" : "pages") matching \"\(query)\"."
        }
        switch selection {
        case .recent:
            return "The pages you opened last, newest first. Nothing is filed here; this is a view onto everything else."
        case .favorites:
            return "Pages you starred, from every shelf."
        case .bucket(let bucket):
            return bucket.blurb
        case .folder(let id):
            guard let folder = folderSnapshot(id) else { return "" }
            return "\(folder.count) \(folder.count == 1 ? "page" : "pages") in \(folder.name), filed under \(folder.bucket.title)."
        }
    }

    var headerAccent: NoteAccent {
        switch selection {
        case .folder(let id): folderSnapshot(id)?.accent ?? .sage
        case .bucket(let bucket): NoteAccent.derived(from: bucket.rawValue)
        default: .slate
        }
    }

    /// "Library / Projects / Training", the trail across the top of the shelf.
    var breadcrumb: [String] {
        var trail = ["Library"]
        switch selection {
        case .recent:    trail.append("Recent")
        case .favorites: trail.append("Favourites")
        case .bucket(let bucket): trail.append(bucket.title)
        case .folder(let id):
            if let folder = folderSnapshot(id) {
                trail.append(folder.bucket.title)
                trail.append(folder.name)
            }
        }
        return trail
    }

    private func folderSnapshot(_ id: UUID) -> NoteFolderSnapshot? {
        for bucket in NoteBucket.allCases {
            if let found = Self.find(id, in: snapshot.folders(in: bucket)) { return found }
        }
        return nil
    }

    private static func find(_ id: UUID, in folders: [NoteFolderSnapshot]) -> NoteFolderSnapshot? {
        for folder in folders {
            if folder.id == id { return folder }
            if let found = find(id, in: folder.children) { return found }
        }
        return nil
    }

    // MARK: - Writing

    /// Creates a page and returns its id, so the caller can open it straight
    /// into the editor. A note made from a button and then left for the person
    /// to find is a note they will not write.
    @discardableResult
    func createNote(kind: NoteKind = .note, title: String = "") -> UUID? {
        guard let store else { return nil }
        do {
            let document = try store.createDocument(
                title: title,
                kind: kind,
                bucket: activeBucket,
                folderID: activeFolderID
            )
            load()
            requestSync()
            return document.id
        } catch {
            assertionFailure("Note create failed: \(error)")
            return nil
        }
    }

    /// Today's journal page, created on first use. Returns an existing entry
    /// rather than a second one for the same day.
    @discardableResult
    func openTodaysJournal() -> UUID? {
        guard let store else { return nil }
        do {
            let document = try store.journalEntry()
            load()
            requestSync()
            return document.id
        } catch {
            assertionFailure("Journal open failed: \(error)")
            return nil
        }
    }

    func createFolder(named name: String, in bucket: NoteBucket, icon: String = "") {
        guard let store, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let folder = try store.createFolder(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bucket: bucket,
                icon: icon
            )
            load()
            selection = .folder(folder.id)
            requestSync()
        } catch {
            assertionFailure("Folder create failed: \(error)")
        }
    }

    func renameFolder(_ id: UUID, to name: String) {
        mutateFolder(id) { store, folder in try store.rename(folder, to: name) }
    }

    func deleteFolder(_ id: UUID) {
        // The rail must not keep pointing at a folder that no longer exists.
        if selection == .folder(id) { selection = .bucket(activeBucket) }
        mutateFolder(id) { store, folder in try store.delete(folder) }
    }

    func toggleFavorite(_ id: UUID) {
        mutate(id) { store, document in try store.toggleFavorite(document) }
    }

    func toggleArchive(_ id: UUID) {
        mutate(id) { store, document in
            document.isArchived ? try store.unarchive(document) : try store.archive(document)
        }
    }

    func delete(_ id: UUID) {
        mutate(id) { store, document in try store.delete(document) }
    }

    func move(_ id: UUID, to bucket: NoteBucket, folderID: UUID?) {
        mutate(id) { store, document in try store.move(document, to: bucket, folderID: folderID) }
    }

    private func mutate(_ id: UUID, _ work: (NotesStore, NoteDocument) throws -> Void) {
        guard let store else { return }
        do {
            guard let document = try store.document(id: id) else { return }
            try work(store, document)
            load()
            requestSync()
        } catch {
            assertionFailure("Note update failed: \(error)")
        }
    }

    private func mutateFolder(_ id: UUID, _ work: (NotesStore, NoteFolder) throws -> Void) {
        guard let store else { return }
        do {
            guard let folder = try store.folder(id: id) else { return }
            try work(store, folder)
            load()
            requestSync()
        } catch {
            assertionFailure("Folder update failed: \(error)")
        }
    }

    /// Fire and forget. Nothing in the UI waits on the server: the write has
    /// already landed locally by the time this is called, and a failure here
    /// only means the next pass carries the row instead.
    private func requestSync() {
        guard let sync else { return }
        Task { await sync.sync() }
    }
}

/// What the view model needs from sync, stated as a protocol so a preview and a
/// test can hand it nothing without standing up a network stack.
@MainActor
protocol NoteSyncing: AnyObject {
    func sync() async
}
