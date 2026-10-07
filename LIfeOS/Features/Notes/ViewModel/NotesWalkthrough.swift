import SwiftUI
import Observation
import DesignSystem
import Persistence

/// Walks someone through Notes over the real screens.
///
/// The app drives; the person only taps Next or Skip. Where the walk has got
/// to is a tested `WalkthroughRun`; this class carries out its effects. Steps
/// 1, 4 and 5 point at the shelf, 2 and 3 at a sample page, so moving between
/// them is a request the hub carries out (`request`), because only the hub
/// knows whether a page is pushed or shown beside the shelf.
@MainActor @Observable
final class NotesWalkthrough {
    /// Numbered, so two identical requests in a row still read as a change.
    struct Request: Equatable {
        enum Kind: Equatable { case showShelf, openPage(UUID) }
        let id: Int
        let kind: Kind
    }

    static let sampleTitle = "Your first page"
    static let seenKey = "hasSeenNotesWalkthrough"
    /// How long a step waits for its anchor before it is skipped.
    static let anchorWait: Duration = .seconds(2)

    let frames = WalkthroughFrames()
    private(set) var run = WalkthroughRun()
    private(set) var request: Request?
    private var requestCount = 0
    private weak var notes: NotesViewModel?
    private var samplePageID: UUID?
    /// The sample's editor while it is open, so its last keystrokes are saved
    /// before the walkthrough decides whether the page was written in.
    private weak var sampleEditor: NoteEditorViewModel?
    private var watch: Task<Void, Never>?

    var isRunning: Bool { run.isRunning }
    var currentStep: WalkthroughStep? { run.stepIndex.map { WalkthroughScript.notes[$0] } }
    var isLastStep: Bool { run.isLast }

    func start(notes: NotesViewModel) {
        guard !run.isRunning else { return }
        self.notes = notes
        apply(run.start())
    }

    func next() { apply(run.next()) }

    func skip() { apply(run.skip()) }

    func consumeRequest() { request = nil }

    /// The hub hands over each editor it builds; only the sample's is kept.
    func editorOpened(_ editor: NoteEditorViewModel, for documentID: UUID) {
        if documentID == samplePageID { sampleEditor = editor }
    }

    /// Waits for the current step's anchor and skips the step if it does not
    /// show. Called on every step, and again whenever the anchor goes away
    /// mid-step (the slash menu, Escape, a closed page), so a lost anchor can
    /// never leave the walkthrough running with nothing on screen.
    func watchForAnchor() {
        watch?.cancel()
        guard let index = run.stepIndex else { return }
        watch = Task { [weak self] in
            try? await Task.sleep(for: Self.anchorWait)
            guard let self, !Task.isCancelled, self.run.stepIndex == index else { return }
            guard self.frames.frames[WalkthroughScript.notes[index].anchor] == nil else { return }
            self.apply(self.run.anchorMissing(at: index))
        }
    }

    private func apply(_ effects: [WalkthroughRun.Effect]) {
        for effect in effects {
            switch effect {
            case .openSample:
                if let id = notes?.createWalkthroughSample() {
                    samplePageID = id
                    send(.openPage(id))
                }
            case .showShelf:
                send(.showShelf)
            case .discardSample:
                sampleEditor?.flush()
                if let samplePageID { notes?.discardWalkthroughSample(samplePageID) }
                samplePageID = nil
                sampleEditor = nil
            case .markSeen:
                UserDefaults.currentAccount.set(true, forKey: Self.seenKey)
            }
        }
        if run.isRunning { watchForAnchor() } else { watch?.cancel() }
    }

    private func send(_ kind: Request.Kind) {
        requestCount += 1
        request = Request(id: requestCount, kind: kind)
    }
}

extension EnvironmentValues {
    /// Owned by `RootView`; nil in previews that do not run a walkthrough.
    @Entry var notesWalkthrough: NotesWalkthrough? = nil
}
