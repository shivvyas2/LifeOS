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

    public init(anchor: WalkthroughAnchor, sentence: String) {
        self.anchor = anchor
        self.sentence = sentence
    }
}

/// The order of the steps and which one comes next.
public enum WalkthroughScript {
    public static let notes: [WalkthroughStep] = [
        WalkthroughStep(anchor: .notesNew, sentence: "One tap starts a page. It lands in your Inbox until you file it."),
        WalkthroughStep(anchor: .notesFileChip, sentence: "This says where the page lives. Tap it to move it anywhere."),
        WalkthroughStep(anchor: .notesBlockPicker, sentence: "To-dos, headings and lists from here, or type / in the text."),
        WalkthroughStep(anchor: .notesTodos, sentence: "Every open to-do from every page, in one list."),
        WalkthroughStep(anchor: .notesLibrary, sentence: "Folders, favourites and habits live here."),
    ]

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
