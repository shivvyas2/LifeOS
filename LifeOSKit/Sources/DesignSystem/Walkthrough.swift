import Foundation

/// A view the walkthrough can point at. Each one reports its own frame, so a
/// layout change moves the spotlight with it instead of leaving it on a
/// remembered rectangle.
public enum WalkthroughAnchor: String, CaseIterable, Hashable, Sendable {
    case notesNew, notesFileChip, notesBlockPicker, notesTodos, notesLibrary
}

public struct WalkthroughStep: Equatable, Sendable {
    public let anchor: WalkthroughAnchor
    public let sentence: String
    /// What the cut-out is round, for VoiceOver, which cannot see it.
    public let target: String

    public init(anchor: WalkthroughAnchor, sentence: String, target: String) {
        self.anchor = anchor
        self.sentence = sentence
        self.target = target
    }
}

/// The order of the steps and which one comes next.
public enum WalkthroughScript {
    public static let notes: [WalkthroughStep] = [
        WalkthroughStep(anchor: .notesNew, sentence: "One tap starts a page. It lands in your Inbox until you file it.", target: "New button"),
        WalkthroughStep(anchor: .notesFileChip, sentence: "This says where the page lives. Tap it to move it anywhere.", target: "File chip"),
        WalkthroughStep(anchor: .notesBlockPicker, sentence: "To-dos, headings and lists from here, or type / in the text.", target: "Block picker"),
        WalkthroughStep(anchor: .notesTodos, sentence: "Every open to-do from every page, in one list.", target: "To-dos tab"),
        WalkthroughStep(anchor: .notesLibrary, sentence: "Folders, favourites and habits live here.", target: "Library button"),
    ]

    /// The steps that point into a page rather than at the shelf.
    public static let pageAnchors: Set<WalkthroughAnchor> = [.notesFileChip, .notesBlockPicker]

    /// The next step after `index` (nil: before the first) whose anchor can
    /// be shown; nil when none remain.
    public static func next(after index: Int?, available: Set<WalkthroughAnchor>) -> Int? {
        let start = (index ?? -1) + 1
        guard start < notes.count else { return nil }
        return notes[start...].firstIndex { available.contains($0.anchor) }
    }

    public static func isLast(_ index: Int, available: Set<WalkthroughAnchor>) -> Bool {
        next(after: index, available: available) == nil
    }

    /// The card goes on the far side of the screen's middle from the cut-out,
    /// so it never covers what it is pointing at.
    public static func cardSitsBelow(_ cutout: CGRect, in height: CGFloat) -> Bool {
        cutout.midY < height / 2
    }
}

/// Where a walkthrough has got to, and what the app must do as it moves.
///
/// A value, so every transition is tested; the app only carries out the
/// effects. The order of the effects matters: `discardSample` comes before
/// `showShelf`, so the app can save the open sample before deciding whether
/// anything was written in it.
public struct WalkthroughRun: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case openSample, showShelf, discardSample, markSeen
    }

    public private(set) var stepIndex: Int?
    /// Anchors that did not turn up in time this run; `next` passes over them.
    public private(set) var missing: Set<WalkthroughAnchor> = []
    private var sampleOpened = false

    public init() {}

    public var isRunning: Bool { stepIndex != nil }

    public var isLast: Bool {
        guard let stepIndex else { return false }
        return WalkthroughScript.isLast(stepIndex, available: candidates)
    }

    private var candidates: Set<WalkthroughAnchor> { Set(WalkthroughAnchor.allCases).subtracting(missing) }

    public mutating func start() -> [Effect] {
        guard stepIndex == nil else { return [] }
        missing = []
        sampleOpened = false
        return [.showShelf] + move(to: WalkthroughScript.next(after: nil, available: candidates))
    }

    public mutating func next() -> [Effect] {
        move(to: WalkthroughScript.next(after: stepIndex, available: candidates))
    }

    public mutating func skip() -> [Effect] { finish() }

    /// The step at `index` waited and its anchor never showed. A timeout for
    /// a step already left behind does nothing.
    public mutating func anchorMissing(at index: Int) -> [Effect] {
        guard stepIndex == index else { return [] }
        missing.insert(WalkthroughScript.notes[index].anchor)
        return next()
    }

    private mutating func move(to index: Int?) -> [Effect] {
        guard let index else { return finish() }
        var effects: [Effect] = []
        let onPage = WalkthroughScript.pageAnchors.contains(WalkthroughScript.notes[index].anchor)
        if onPage, !sampleOpened {
            sampleOpened = true
            effects.append(.openSample)
        } else if !onPage, let stepIndex,
                  WalkthroughScript.pageAnchors.contains(WalkthroughScript.notes[stepIndex].anchor) {
            effects.append(.showShelf)
        }
        stepIndex = index
        return effects
    }

    private mutating func finish() -> [Effect] {
        let effects: [Effect] = sampleOpened ? [.discardSample, .showShelf, .markSeen] : [.markSeen]
        stepIndex = nil
        sampleOpened = false
        return effects
    }
}
