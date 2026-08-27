import SwiftUI
import DesignSystem
import Persistence

/// The notes tab.
///
/// One set of screens in three arrangements, chosen by how much width there
/// actually is rather than by the size class alone.
///
/// A phone gets the library as its own screen and pushes into a shelf and then
/// a page. A narrow iPad pane gets library and shelf side by side, with a page
/// pushed over the shelf. A wide one gets all three at once, which is the whole
/// argument for the layout: on a landscape iPad, opening a note should not hide
/// the grid you were reading it from.
///
/// The threshold is measured, not assumed. A regular size class covers
/// everything from a 1366pt landscape iPad to a narrow Stage Manager window,
/// and those two want different arrangements.
struct NotesHubScreen: View {
    @Bindable var model: NotesViewModel
    /// Habits did not become pages, so the tab hosts the one screen that still
    /// renders them. Passed in rather than owned here because `RootView` needs
    /// the same view model for Today's habit ticks.
    @Bindable var plan: PlanViewModel
    var onAddHabit: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    /// Pushed navigation: the phone's whole journey, and the shelf column's
    /// own stack on an iPad. A page is only ever on here when there is no
    /// detail column to put it in.
    @State private var path: [NoteRoute] = []
    /// The page in the detail column. Only used in the three-column
    /// arrangement; everywhere else a page is pushed onto `path` instead.
    /// Keeping one of the two always empty is what stops them disagreeing.
    @State private var openPage: UUID?
    /// Collapsing the library gives the page the width back, which is what a
    /// person writing rather than filing actually wants.
    @State private var isLibraryVisible = true
    /// Measured rather than derived from the size class, for the reason in the
    /// type comment above.
    @State private var paneWidth: CGFloat = 0
    /// Raised by Command-F. The sidebar owns the field; this is how the scene's
    /// menu reaches it.
    @State private var isSearchFocused = false
    @State private var newFolderBucket: NoteBucket?
    @State private var renamingFolder: UUID?
    @State private var folderName = ""

    enum NoteRoute: Hashable {
        case shelf
        case page(UUID)
        case habits
    }

    var body: some View {
        Group {
            if layout.isRegular {
                wideShell
            } else {
                compactShell
            }
        }
        .background(LifeOSTokens.canvas.resolve(scheme))
        .focusedSceneValue(\.notesCommands, commandTarget)
        .sheet(item: $newFolderBucket) { bucket in
            NoteFolderSheet(
                title: "New folder in \(bucket.title)",
                name: "",
                onSave: { name, icon in model.createFolder(named: name, in: bucket, icon: icon) }
            )
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            NoteFolderSheet(
                title: "Rename folder",
                name: folderName,
                onSave: { name, _ in
                    if let id = renamingFolder { model.renameFolder(id, to: name) }
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - Shells

    private static let libraryWidth: CGFloat = 268
    private static let minShelfWidth: CGFloat = 340
    /// Below this the page stops being somewhere you would write. It is the
    /// number the whole arrangement turns on, so it is stated rather than
    /// buried in a threshold.
    private static let minPageWidth: CGFloat = 520

    /// Three columns only when all three can have the width they need.
    ///
    /// A single overall threshold was wrong: at 1024pt it read as wide enough,
    /// but the library and the tab rail take 380 of that before the shelf and
    /// the page have divided anything, leaving a 310pt column to write in.
    /// Subtracting what is already spoken for is what makes collapsing the
    /// library buy a third column on a screen that could not otherwise hold
    /// one.
    private var isThreeColumn: Bool {
        guard layout.isRegular else { return false }
        let spokenFor = layout.railInset + (isLibraryVisible ? Self.libraryWidth : 0)
        return paneWidth - spokenFor >= Self.minShelfWidth + Self.minPageWidth
    }

    /// iPad and wide panes.
    private var wideShell: some View {
        HStack(spacing: 0) {
            if isLibraryVisible {
                library
                    .frame(width: Self.libraryWidth)
                    .padding(.leading, layout.railInset)
                    .background(LifeOSTokens.canvas.resolve(scheme))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                columnRule
            }

            if isThreeColumn {
                NavigationStack(path: $path) {
                    shelf
                        .navigationDestination(for: NoteRoute.self, destination: destination)
                }
                // Bounded on both sides: below the minimum a card stops being
                // legible, above the maximum the shelf starts stealing width
                // from the thing being written.
                .frame(minWidth: Self.minShelfWidth, idealWidth: 420, maxWidth: 480)

                columnRule
                detailColumn
            } else {
                NavigationStack(path: $path) {
                    shelf
                        .navigationDestination(for: NoteRoute.self, destination: destination)
                }
            }
        }
        // The rail's clearance moves onto whichever column is leftmost, so
        // collapsing the library does not tuck the shelf under the tab rail.
        .padding(.leading, isLibraryVisible ? 0 : layout.railInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            paneWidth = width
        }
        .animation(.easeInOut(duration: 0.22), value: isLibraryVisible)
        // Rotating an iPad, or resizing a Stage Manager window, changes which
        // arrangement applies. The open page has to move between the detail
        // column and the navigation stack with it, or it vanishes.
        .onChange(of: isThreeColumn) { _, three in
            if three {
                if case .page(let id) = path.last {
                    path.removeLast()
                    openPage = id
                }
            } else if let page = openPage {
                openPage = nil
                path.append(.page(page))
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let openPage {
            NavigationStack {
                NoteEditorHost(documentID: openPage, onOpenLinked: { open($0) })
            }
            // Rebuilt per page rather than reused, so the editor never shows
            // the previous page's blocks for a frame while the new ones load.
            .id(openPage)
        } else {
            noPageSelected
        }
    }

    private var noPageSelected: some View {
        VStack(spacing: 10) {
            Image(systemName: model.selection.bucket?.systemImage ?? "doc.text")
                .font(LifeOSType.display.weight(.light))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.5))
            Text("No page open")
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text("Pick one from \(model.headerTitle), or press Command N to start a new page.")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeOSTokens.canvas.resolve(scheme))
    }

    private var columnRule: some View {
        Rectangle()
            .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(scheme == .dark ? 0.14 : 0.07))
            .frame(width: 1)
    }

    /// The library rail, shared by both shells so its wiring is stated once.
    private var library: some View {
        NotesSidebar(
            snapshot: model.snapshot,
            selection: Binding(
                get: { model.selection },
                set: { selection in
                    model.selection = selection
                    // Selecting in the rail returns to the shelf. Leaving an
                    // open page beside a rail that highlights a different
                    // folder is the state that makes split views confusing.
                    path.removeAll()
                    openPage = nil
                }
            ),
            query: $model.query,
            isSearchFocused: $isSearchFocused,
            onNewFolder: { newFolderBucket = $0 },
            onOpenHabits: { path.append(.habits) },
            habitCount: plan.snapshot.habits.count,
            onRenameFolder: startRename,
            onDeleteFolder: { model.deleteFolder($0) },
            onDropNotes: { ids, bucket, folderID in
                for id in ids { model.move(id, to: bucket, folderID: folderID) }
            }
        )
    }

    /// Phone. The library is the root screen, so the first thing someone sees
    /// is the shape of the system rather than a page of one folder's contents.
    private var compactShell: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(LifeOSType.display)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, layout.gutter)
                    .padding(.top, 4)

                library
            }
            .padding(.bottom, layout.contentBottomInset)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .navigationDestination(for: NoteRoute.self, destination: destination)
            .onChange(of: model.query) { _, query in
                // Typing in the rail's search field on a phone should show
                // results, and results live on the shelf.
                if !query.isEmpty, path.isEmpty { path = [.shelf] }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: NoteRoute) -> some View {
        switch route {
        case .shelf:
            shelf
        case .page(let id):
            NoteEditorHost(documentID: id, onOpenLinked: { open($0) })
        case .habits:
            PlanScreen(
                snapshot: plan.snapshot,
                section: .constant(.habits),
                showsSections: false,
                onAdd: onAddHabit,
                onAdvance: { plan.advance(id: $0) },
                onToggleHabit: { plan.toggleHabit(id: $0) },
                onDelete: { plan.delete(id: $0) }
            )
            .navigationTitle("Habits")
        }
    }

    private var shelf: some View {
        NoteShelfScreen(
            model: model,
            openPageID: openPage,
            onOpen: { open($0) },
            onNewFolder: { newFolderBucket = $0 },
            // Offered only where there is a library to collapse.
            onToggleLibrary: layout.isRegular ? { isLibraryVisible.toggle() } : nil,
            isLibraryVisible: isLibraryVisible
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What the hardware keyboard drives. Built here because only the shell
    /// knows whether a page is pushed or shown beside the shelf.
    private var commandTarget: NotesCommandTarget {
        NotesCommandTarget(
            newPage: { if let id = model.createNote() { open(id) } },
            newFolder: { newFolderBucket = model.activeBucket },
            todaysJournal: { if let id = model.openTodaysJournal() { open(id) } },
            focusSearch: {
                // The field lives in the library, so raising it has to raise
                // the library first or the caret goes somewhere invisible.
                isLibraryVisible = true
                isSearchFocused = true
            },
            toggleLibrary: { isLibraryVisible.toggle() },
            selectBucket: { bucket in
                model.selection = .bucket(bucket)
                path.removeAll()
                openPage = nil
            },
            selectRecent: {
                model.selection = .recent
                path.removeAll()
                openPage = nil
            },
            closePage: closeAction
        )
    }

    /// Nil when there is nothing open, which greys out Command-W rather than
    /// letting it fire into an empty detail column.
    private var closeAction: (() -> Void)? {
        if openPage != nil {
            return { openPage = nil }
        }
        if case .page = path.last {
            return { path.removeLast() }
        }
        return nil
    }

    /// Opens a page wherever this arrangement puts one.
    private func open(_ id: UUID) {
        if isThreeColumn {
            openPage = id
        } else {
            path.append(.page(id))
        }
    }

    private func startRename(_ id: UUID) {
        folderName = ""
        renamingFolder = id
    }
}


/// Builds an editor view model for one page and keeps it alive for as long as
/// the page is on screen.
///
/// A separate view because the model has to be created with the document id in
/// hand, and `@State` cannot be initialised from a navigation destination's
/// argument without a wrapper like this one.
private struct NoteEditorHost: View {
    let documentID: UUID
    var onOpenLinked: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.noteSync) private var sync
    @State private var model: NoteEditorViewModel?

    var body: some View {
        Group {
            if let model, model.documentID == documentID {
                NoteEditorScreen(model: model, onOpenLinked: onOpenLinked)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: documentID) {
            let editor = NoteEditorViewModel(documentID: documentID)
            editor.attach(context, sync: sync)
            editor.load()
            model = editor
        }
    }
}

/// Name and icon for a folder, used for both creating and renaming.
struct NoteFolderSheet: View {
    let title: String
    @State var name: String
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var icon = ""
    @FocusState private var focused: Bool

    private let icons = ["", "\u{1F3AF}", "\u{1F4DA}", "\u{1F331}", "\u{1F4B0}", "\u{1F3C3}", "\u{1F5D3}", "\u{1F9E0}"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Folder name", text: $name)
                    .font(LifeOSType.body)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                HStack(spacing: 10) {
                    ForEach(icons, id: \.self) { candidate in
                        Button {
                            icon = candidate
                        } label: {
                            Group {
                                if candidate.isEmpty {
                                    Image(systemName: "circle.dashed").font(LifeOSType.sectionTitle.weight(.regular))
                                } else {
                                    Text(candidate).font(LifeOSType.sectionTitle.weight(.regular))
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(icon == candidate ? Color.primary.opacity(0.1) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, icon)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

extension EnvironmentValues {
    /// Injected once by the composition root. The editor is created deep inside
    /// a navigation destination, which is too far down to thread a dependency
    /// through by hand.
    @Entry var noteSync: NoteSyncing?
}
