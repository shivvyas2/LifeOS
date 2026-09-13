import Foundation
import Observation
import SwiftData
import Persistence

/// One open page.
///
/// Holds the blocks in memory and writes them back on a short delay. Saving on
/// every keystroke would mean a SwiftData write and a `didSave` notification
/// per character, and every screen in the app reloads on that notification.
@Observable
@MainActor
final class NoteEditorViewModel {
    let documentID: UUID

    var title: String = "" {
        didSet { if title != oldValue { scheduleSave() } }
    }
    var icon: String = ""
    private(set) var blocks: [NoteBlock] = NoteBlock.blank
    private(set) var kind: NoteKind = .note
    private(set) var bucket: NoteBucket = .projects
    private(set) var accent: NoteAccent = .sage
    private(set) var status: PlanStatus = .todo
    private(set) var entryDate: Date?
    private(set) var updatedAt: Date = .now
    private(set) var isFavorite = false
    private(set) var isArchived = false

    /// Which block owns the caret. The editor decides this, not UIKit, so that
    /// inserting a block can put the caret straight into it.
    var focusedBlockID: UUID?

    /// The text after a "/" in the focused block, or nil when the menu is shut.
    var slashQuery: String?
    /// The partial title inside an unclosed `[[`, or nil when there is none.
    var linkQuery: String?

    /// Ink mode. On iPad with a Pencil this is the difference between writing
    /// and drawing; on a phone it is a full-page sketch layer.
    var isInking = false
    private(set) var drawingData: Data?

    private(set) var backlinks: [NoteBacklink] = []
    private(set) var titleIndex: [String] = []

    private var context: ModelContext?
    private var sync: NoteSyncing?
    private let calendar: Calendar
    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    private(set) var saveMessage = "Saved on this device"
    private(set) var hasSaveError = false

    init(documentID: UUID, calendar: Calendar = .current) {
        self.documentID = documentID
        self.calendar = calendar
    }

    func attach(_ context: ModelContext, sync: NoteSyncing? = nil) {
        self.context = context
        self.sync = sync
    }

    private var store: NotesStore? {
        context.map { NotesStore(context: $0, calendar: calendar) }
    }

    // MARK: - Loading

    func load() {
        guard let store, let document = try? store.document(id: documentID) else { return }

        isLoading = true
        defer { isLoading = false }
        title = document.title
        icon = document.icon
        blocks = document.blocks
        kind = document.kind
        bucket = document.bucket
        accent = document.accent
        status = document.status
        entryDate = document.entryDate
        updatedAt = document.updatedAt
        isFavorite = document.isFavorite
        isArchived = document.isArchived
        drawingData = document.drawingData

        try? store.markOpened(document)
        refreshLinks()
    }

    private func refreshLinks() {
        guard let store else { return }
        backlinks = (try? store.backlinks(to: displayTitle)) ?? []
        titleIndex = ((try? store.documents(includeArchived: true)) ?? [])
            .filter { $0.id != documentID }
            .map(\.displayTitle)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return blocks.first { $0.kind.isTextual && !$0.isEmpty }?.text ?? "Untitled"
    }

    var ordinals: [UUID: Int] { NoteBlockEditor.ordinals(blocks) }

    // MARK: - Editing

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    func setText(_ text: String, on id: UUID) {
        guard let index = index(of: id), blocks[index].text != text else { return }
        blocks[index].text = text
        scheduleSave()
    }

    func toggleCheck(on id: UUID) {
        let result = NoteBlockEditor.toggleCheck(blocks, at: id)
        guard result.handled else { return }
        blocks = result.blocks
        // Ticking a box is a decision, not a keystroke. Saved at once so it
        // survives the app being closed a second later.
        saveNow()
    }

    /// Return. The rule itself lives in `NoteBlockEditor`; this applies the
    /// result and moves the caret.
    func splitBlock(_ id: UUID, before: String, after: String) {
        let result = NoteBlockEditor.split(blocks, at: id, before: before, after: after)
        guard result.handled else { return }
        blocks = result.blocks
        if let focus = result.focus { focusedBlockID = focus }
        slashQuery = nil
        linkQuery = nil
        scheduleSave()
    }

    /// Backspace at offset zero. Returns whether the editor consumed it, so
    /// UIKit knows whether to also delete a character.
    func backspaceAtStart(of id: UUID) -> Bool {
        let result = NoteBlockEditor.backspaceAtStart(blocks, at: id)
        guard result.handled else { return false }
        blocks = result.blocks
        if let focus = result.focus { focusedBlockID = focus }
        scheduleSave()
        return true
    }

    /// Ink inside a sketch block. Saved on the same debounce as text: a stroke
    /// lands every few milliseconds while someone is drawing, and writing the
    /// document on each one would rewrite every block in the page per stroke.
    func setSketchDrawing(_ drawing: Data?, on id: UUID) {
        let result = NoteBlockEditor.setDrawing(blocks, at: id, drawing: drawing)
        guard result.handled else { return }
        blocks = result.blocks
        scheduleSave()
    }

    func setSketchHeight(_ height: Double, on id: UUID) {
        let result = NoteBlockEditor.setSketchHeight(blocks, at: id, height: height)
        guard result.handled else { return }
        blocks = result.blocks
        scheduleSave()
    }

    func indent(_ id: UUID, by delta: Int) {
        let result = NoteBlockEditor.indent(blocks, at: id, by: delta)
        guard result.handled else { return }
        blocks = result.blocks
        scheduleSave()
    }

    /// Applies a typed markdown prefix: `# ` becomes a heading, `- ` a bullet.
    func transform(_ id: UUID, to kind: NoteBlockKind, text: String) {
        let result = NoteBlockEditor.transform(blocks, at: id, to: kind, text: text)
        guard result.handled else { return }
        blocks = result.blocks
        if let focus = result.focus { focusedBlockID = focus }
        slashQuery = nil
        scheduleSave()
    }

    /// The slash menu's pick. Clears the "/query" the person typed, since it
    /// was a command rather than content.
    func applySlashCommand(_ kind: NoteBlockKind) {
        guard let id = focusedBlockID else { return }
        transform(id, to: kind, text: "")
        slashQuery = nil
    }

    /// Completes an open `[[` with a page title.
    func completeLink(with title: String) {
        guard let id = focusedBlockID else { return }
        let result = NoteBlockEditor.completeLink(blocks, at: id, with: title)
        guard result.handled else { return }
        blocks = result.blocks
        linkQuery = nil
        scheduleSave()
    }

    /// Titles matching what has been typed inside `[[`, plus the raw text so a
    /// link to a page that does not exist yet is still offerable. Obsidian
    /// creates the page when the link is first followed, and so does this.
    var linkSuggestions: [String] {
        guard let query = linkQuery else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(titleIndex.prefix(6)) }

        return Array(
            titleIndex
                .filter { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                .prefix(6)
        )
    }

    /// Follows a `[[link]]`, creating the page if nothing carries that title.
    /// Returns the id to open.
    func resolveLink(_ title: String) -> UUID? {
        guard let store else { return nil }
        do {
            if let existing = try store.document(titled: title) { return existing.id }
            let created = try store.createDocument(title: title, bucket: bucket)
            requestSync()
            return created.id
        } catch {
            assertionFailure("Link resolve failed: \(error)")
            return nil
        }
    }

    // MARK: - Properties

    func setStatus(_ status: PlanStatus) {
        self.status = status
        mutate { store, document in try store.setStatus(status, on: document) }
    }

    func setAccent(_ accent: NoteAccent) {
        self.accent = accent
        mutate { store, document in try store.setAccent(accent, on: document) }
    }

    func setIcon(_ icon: String) {
        self.icon = icon
        mutate { store, document in try store.setIcon(icon, on: document) }
    }

    func toggleFavorite() {
        isFavorite.toggle()
        mutate { store, document in try store.toggleFavorite(document) }
    }

    func toggleArchive() {
        isArchived.toggle()
        mutate { store, document in
            document.isArchived ? try store.unarchive(document) : try store.archive(document)
        }
    }

    func setDrawing(_ data: Data?) {
        // Compared before writing: PencilKit reports a change on every stroke
        // *and* on every tool switch, and rewriting identical bytes would mark
        // the page dirty for a sync that carries nothing new.
        guard drawingData != data else { return }
        drawingData = data
        mutate { store, document in try store.setDrawing(data, on: document) }
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard !isLoading else { return }
        saveMessage = "Saving…"
        hasSaveError = false
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Called on the way out, so a page closed inside the debounce window still
    /// lands. Cancelling the pending task first stops it firing a second write
    /// against a view model the screen has already let go of.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func saveNow() {
        guard let store, let document = try? store.document(id: documentID) else { return }
        do {
            try store.update(document, blocks: blocks)
            if document.title != title { try store.rename(document, to: title) }
            updatedAt = document.updatedAt
            refreshLinks()
            saveMessage = "Saved on this device"
            hasSaveError = false
            requestSync()
        } catch {
            saveMessage = "Couldn’t save · Retry"
            hasSaveError = true
        }
    }

    private func mutate(_ work: (NotesStore, NoteDocument) throws -> Void) {
        guard let store, let document = try? store.document(id: documentID) else { return }
        do {
            try work(store, document)
            updatedAt = document.updatedAt
            requestSync()
        } catch {
            assertionFailure("Note property update failed: \(error)")
        }
    }

    private func requestSync() {
        guard let sync else { return }
        Task { await sync.sync() }
    }
}
