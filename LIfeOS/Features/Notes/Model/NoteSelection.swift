import Foundation
import Persistence

/// What the library currently points at.
///
/// One enum rather than a pair of optionals, because "a folder is selected"
/// and "a shelf is selected" are mutually exclusive and expressing them as
/// two nullable properties makes a fourth, meaningless state representable.
/// The first three are the stream chips across the top of the shelf.
enum NoteSelection: Hashable {
    case inbox
    case all
    case todos
    case favorites
    case bucket(NoteBucket)
    case folder(UUID)

    var bucket: NoteBucket? {
        if case .bucket(let bucket) = self { return bucket }
        return nil
    }

    var folderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }

    /// The chip this selection is, or nil on a shelf, a folder or favourites.
    var streamChip: NoteStreamChip? {
        switch self {
        case .inbox: .inbox
        case .all: .all
        case .todos: .todos
        default: nil
        }
    }

    init(chip: NoteStreamChip) {
        switch chip {
        case .inbox: self = .inbox
        case .all: self = .all
        case .todos: self = .todos
        }
    }
}

/// The filter across the top of a shelf. The reference this is drawn from calls
/// them Items, Notebooks and Canvases; here they are the three things a page
/// can actually be, plus everything.
enum NoteShelfFilter: String, CaseIterable, Identifiable, Hashable {
    case all, notes, journal, tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:     "All"
        case .notes:   "Notes"
        case .journal: "Journal"
        case .tasks:   "Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .all:     "square.grid.2x2"
        case .notes:   "doc.text"
        case .journal: "book.closed"
        case .tasks:   "checklist"
        }
    }

    var kind: NoteKind? {
        switch self {
        case .all:     nil
        case .notes:   .note
        case .journal: .journal
        case .tasks:   .task
        }
    }
}

/// How a shelf orders its cards. The reference puts this behind a single
/// control next to the add button, and four options is the most that control
/// can carry without becoming a menu of its own.
enum NoteSort: String, CaseIterable, Identifiable, Hashable {
    case recentlyEdited, recentlyOpened, title, created

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyEdited: "Recently edited"
        case .recentlyOpened: "Recently opened"
        case .title:          "Title"
        case .created:        "Date created"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyEdited: "arrow.up.arrow.down"
        case .recentlyOpened: "clock.arrow.circlepath"
        case .title:          "textformat.abc"
        case .created:        "calendar"
        }
    }
}
