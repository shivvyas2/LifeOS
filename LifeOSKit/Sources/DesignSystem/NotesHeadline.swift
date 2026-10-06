/// What the Notes shelf is showing, as far as the eyebrow cares.
public enum NotesScope: Sendable {
    case inbox, all, todos, favorites, pages
}

/// The Notes masthead eyebrow, so "1 pages" never ships.
public enum NotesHeadline {
    public static func eyebrow(count: Int) -> String {
        switch count {
        case 0: "Notes · No pages"
        case 1: "Notes · 1 page"
        default: "Notes · \(count) pages"
        }
    }

    public static func eyebrow(_ scope: NotesScope, count: Int) -> String {
        switch scope {
        case .inbox:
            count == 0 ? "Notes · Nothing in Inbox" : "Notes · \(count) in Inbox"
        case .all, .pages:
            eyebrow(count: count)
        case .todos:
            switch count {
            case 0: "Notes · No to-dos"
            case 1: "Notes · 1 to-do"
            default: "Notes · \(count) to-dos"
            }
        case .favorites:
            switch count {
            case 0: "Notes · No favourites"
            case 1: "Notes · 1 favourite"
            default: "Notes · \(count) favourites"
            }
        }
    }
}
