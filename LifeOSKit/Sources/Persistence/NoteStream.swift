import Foundation

/// A filter across the whole library, as opposed to `NoteSelection`, which
/// picks one shelf or folder.
///
/// Deliberately small. The spec's Goals chip and the person's own collection
/// chips arrive with the phases that build those models; adding cases here
/// before then would mean a chip that routes to nothing.
public enum NoteStreamChip: String, Sendable, CaseIterable, Equatable, Identifiable {
    case inbox, all, todos

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .all:   "All"
        case .todos: "To-dos"
        }
    }

    /// Reading order in the chip row. Kept separate from `allCases` so that
    /// adding a chip later cannot silently reshuffle the row.
    ///
    /// Named `rowOrder` rather than `all` because this enum already has an
    /// `all` case, and a static of the same name is an invalid redeclaration.
    public static let rowOrder: [NoteStreamChip] = [.inbox, .all, .todos]
}

/// What a chip resolves to. Two shapes because to-dos are rows mirrored out
/// of blocks, not pages, and flattening them into cards would lose the one
/// thing that makes the chip worth having: which page each came from.
public enum NoteStream {
    case cards([NoteCardSnapshot])
    case tasks([NoteTask])

    public var isEmpty: Bool {
        switch self {
        case .cards(let cards): cards.isEmpty
        case .tasks(let tasks): tasks.isEmpty
        }
    }
}
