import SwiftUI
import Persistence

/// What the hardware keyboard can ask the notes tab to do.
///
/// Routed through `focusedSceneValue` rather than hidden buttons scattered in
/// the view tree. That is what puts these in the shortcut overlay a person sees
/// when they hold Command on an iPad, and it means the shortcuts are declared
/// once, in the scene, instead of once per screen that happens to be on show.
///
/// Every field is a closure rather than a reference to the view model, because
/// the actions differ by which shell is up: opening a page means pushing on a
/// phone and filling the detail column on a wide iPad, and the scene must not
/// have to know which.
struct NotesCommandTarget: Equatable {
    let newPage: () -> Void
    let newFolder: () -> Void
    let todaysJournal: () -> Void
    let focusSearch: () -> Void
    let toggleLibrary: () -> Void
    let selectBucket: (NoteBucket) -> Void
    let selectRecent: () -> Void
    /// Nil when no page is open, which is what disables the page-scoped items
    /// rather than letting them fire into nothing.
    let closePage: (() -> Void)?

    /// Closures are never equal, and the only thing a comparison here needs to
    /// answer is whether the menu should re-enable its page items.
    static func == (lhs: NotesCommandTarget, rhs: NotesCommandTarget) -> Bool {
        (lhs.closePage == nil) == (rhs.closePage == nil)
    }
}

extension FocusedValues {
    @Entry var notesCommands: NotesCommandTarget?
}

/// The Notes menu, and the shortcuts behind it.
///
/// Sits in the scene so the shortcuts work wherever focus is, and greys itself
/// out when the notes tab is not the one on screen instead of firing into a tab
/// nobody is looking at.
struct NotesCommands: Commands {
    @FocusedValue(\.notesCommands) private var target

    var body: some Commands {
        CommandMenu("Notes") {
            Button("New Page") { target?.newPage() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(target == nil)

            Button("New Folder") { target?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(target == nil)

            Button("Today's Journal") { target?.todaysJournal() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(target == nil)

            Divider()

            Button("Search Notes") { target?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(target == nil)

            Button("Show or Hide Library") { target?.toggleLibrary() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(target == nil)

            Divider()

            // Command-Option-number, matching how browsers and editors number
            // their tabs, with Recent at zero because it is the one that is not
            // a shelf.
            Button("Recent") { target?.selectRecent() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(target == nil)

            ForEach(Array(NoteBucket.allCases.enumerated()), id: \.element) { index, bucket in
                Button(bucket.title) { target?.selectBucket(bucket) }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: [.command, .option]
                    )
                    .disabled(target == nil)
            }

            Divider()

            Button("Close Page") { target?.closePage?() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(target?.closePage == nil)
        }
    }
}
