import SwiftUI
import Observation
import DesignSystem
import Persistence

/// Walks someone through Notes over the real screens.
///
/// The app drives; the person only taps Next or Skip. Steps 1, 4 and 5 point
/// at the shelf, 2 and 3 at a sample page the walkthrough opens, so moving
/// between them is a request the hub carries out (`request`), because only the
/// hub knows whether a page is pushed or shown beside the shelf.
@MainActor @Observable
final class NotesWalkthrough {
    enum Request: Equatable {
        case showShelf
        case openPage(UUID)
    }

    static let sampleTitle = "Your first page"
    static let seenKey = "hasSeenNotesWalkthrough"
    /// How long a step waits for its anchor before it is skipped.
    static let anchorWait: Duration = .seconds(2)

    let frames = WalkthroughFrames()
    private(set) var stepIndex: Int?
    private(set) var request: Request?
    private weak var notes: NotesViewModel?
    private var samplePageID: UUID?
    /// Anchors that did not turn up in time this run; `next` passes over them.
    private var missing: Set<WalkthroughAnchor> = []
    private var watch: Task<Void, Never>?

    var currentStep: WalkthroughStep? { stepIndex.map { WalkthroughScript.notes[$0] } }

    var isLastStep: Bool {
        guard let stepIndex else { return false }
        return WalkthroughScript.isLast(stepIndex, available: candidates)
    }

    private var candidates: Set<WalkthroughAnchor> { Set(WalkthroughAnchor.allCases).subtracting(missing) }

    private static func isEditorStep(_ index: Int) -> Bool {
        [.notesFileChip, .notesBlockPicker].contains(WalkthroughScript.notes[index].anchor)
    }

    func start(notes: NotesViewModel) {
        guard stepIndex == nil else { return }
        self.notes = notes
        missing = []
        request = .showShelf
        move(to: WalkthroughScript.next(after: nil, available: candidates))
    }

    func next() { move(to: WalkthroughScript.next(after: stepIndex, available: candidates)) }

    func skip() { finish() }

    func consumeRequest() { request = nil }

    /// Enters a step: the sample page for the editor steps, the shelf again
    /// when coming back from them. No step left means the walkthrough is over.
    private func move(to index: Int?) {
        guard let index else { return finish() }
        if Self.isEditorStep(index) {
            if samplePageID == nil, let id = notes?.createWalkthroughSample() {
                samplePageID = id
                request = .openPage(id)
            }
        } else if let stepIndex, Self.isEditorStep(stepIndex) {
            request = .showShelf
        }
        stepIndex = index
        watchForAnchor(of: index)
    }

    /// Skips a step whose anchor has not appeared in time, so the screen is
    /// never left dimmed with nothing cut out and no card.
    private func watchForAnchor(of index: Int) {
        watch?.cancel()
        watch = Task { [weak self] in
            try? await Task.sleep(for: Self.anchorWait)
            guard let self, !Task.isCancelled, self.stepIndex == index else { return }
            let anchor = WalkthroughScript.notes[index].anchor
            guard self.frames.frames[anchor] == nil else { return }
            self.missing.insert(anchor)
            self.next()
        }
    }

    private func finish() {
        watch?.cancel()
        if let samplePageID {
            notes?.discardWalkthroughSample(samplePageID)
            request = .showShelf
        }
        samplePageID = nil
        stepIndex = nil
        UserDefaults.currentAccount.set(true, forKey: Self.seenKey)
    }
}

extension EnvironmentValues {
    /// Owned by `RootView`; nil in previews that do not run a walkthrough.
    @Entry var notesWalkthrough: NotesWalkthrough? = nil
}
