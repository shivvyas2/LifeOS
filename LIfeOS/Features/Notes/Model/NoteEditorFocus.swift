import Foundation

/// What the editor focuses when a page opens: nothing for a page being
/// read, the title for one `New` just made, the first block when the
/// walkthrough wants the block picker up.
enum NoteEditorFocus: Hashable {
    case none, title, firstBlock
}
