import Foundation
import Persistence

/// One page's open to-dos, as the rows the day screen draws, under the
/// page's title. What the To-dos chip lists.
struct NoteTaskGroup: Identifiable, Equatable {
    let page: NoteCardSnapshot
    let rows: [ChecklistRow]
    var id: UUID { page.id }
}

/// What the editor focuses when a page opens: nothing for a page being
/// read, the title for one `New` just made, the first block when the
/// walkthrough wants the block picker up.
enum NoteEditorFocus: Hashable {
    case none, title, firstBlock
}
