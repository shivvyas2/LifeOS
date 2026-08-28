import Foundation
import SwiftData
import Persistence

/// Drives the phone's notes shell.
///
/// Thin by the same rule as `LifeBoardViewModel`: what a chip means and what
/// a capture writes both live in `NotesStore`, where the app's lack of a test
/// target does not matter. This holds the draft, the selected chip, and the
/// rows last read.
@MainActor @Observable
final class NoteInboxViewModel {
    private(set) var stream: NoteStream = .cards([])

    var chip: NoteStreamChip = .inbox {
        didSet { if chip != oldValue { load() } }
    }

    /// What is in the composer right now. Cleared by `capture()` on success
    /// and left alone on failure, so a thought is never silently dropped.
    var draft: String = ""
    /// Whether the next capture becomes a to-do rather than a paragraph.
    /// Sticky across captures on purpose: someone logging three tasks should
    /// not have to press it three times.
    var isTodo: Bool = false

    private var context: ModelContext?
    private var store: NotesStore?

    func attach(_ context: ModelContext) {
        self.context = context
        self.store = NotesStore(context: context)
    }

    func load() {
        guard let store else { return }
        stream = (try? store.stream(for: chip)) ?? .cards([])
    }

    /// Writes the draft and returns the new page's id, so the caller can open
    /// it when the capture was a sketch rather than a sentence. Nil when
    /// there was nothing to write.
    @discardableResult
    func capture() -> UUID? {
        guard let store, let captured = try? store.capture(draft, isTodo: isTodo) else { return nil }
        draft = ""
        // A capture always belongs in the Inbox, so show it even if the
        // person was looking at another chip when they typed it.
        if chip != .inbox { chip = .inbox } else { load() }
        return captured.id
    }

    /// A page holding one empty sketch block, opened straight away. Separate
    /// from `capture()` because a sketch has nothing typed to trim, and
    /// pushing it through the draft would file a paragraph reading "Sketch".
    @discardableResult
    func captureSketch() -> UUID? {
        guard let store else { return nil }
        let page = try? store.createDocument(
            bucket: .areas,
            blocks: [NoteBlock(kind: .sketch)]
        )
        load()
        return page?.id
    }

    func file(_ id: UUID, to bucket: NoteBucket, folderID: UUID?) {
        guard let store, let document = try? store.document(id: id) else { return }
        try? store.move(document, to: bucket, folderID: folderID)
        load()
    }

    func archive(_ id: UUID) {
        guard let store, let document = try? store.document(id: id) else { return }
        try? store.archive(document)
        load()
    }
}
