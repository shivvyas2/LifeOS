import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Native phone navigation and adaptive iPad columns for the same page library.
struct NotesHubScreen: View {
    @Bindable var model: NotesViewModel
    /// Habits did not become pages, so the tab hosts the one screen that still
    /// renders them. Passed in rather than owned here because `RootView` needs
    /// the same view model for Today's habit ticks.
    @Bindable var plan: PlanViewModel
    var onAddHabit: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.notesWalkthrough) private var walkthrough
    @AppStorage(NotesWalkthrough.seenKey, store: .currentAccount) private var hasSeenNotesWalkthrough = false
    @AppStorage("hasSeenFirstRunTour", store: .currentAccount) private var hasSeenFirstRunTour = false

    /// Pushed navigation: the phone's whole journey, and the shelf column's
    /// own stack on an iPad. A page is only ever on here when there is no
    /// detail column to put it in.
    @State private var path: [NoteRoute] = []
    /// The page in the detail column. Only used in the three-column
    /// arrangement; everywhere else a page is pushed onto `path` instead.
    /// Keeping one of the two always empty is what stops them disagreeing.
    @State private var openPage: UUID?
    @State private var openPageFocus: NoteEditorFocus = .none
    /// Collapsing the library gives the page the width back, which is what a
    /// person writing rather than filing actually wants.
    @State private var isLibraryVisible = true
    /// Measured rather than derived from the size class, for the reason in the
    /// type comment above.
    @State private var paneWidth: CGFloat = 0
    /// Raised by Command-F to focus the page search field.
    @State private var isSearchFocused = false
    @State private var newFolderBucket: NoteBucket?
    @State private var renamingFolder: UUID?
    @State private var folderName = ""
    @State private var isLibraryPresented = false
    @State private var pendingNewFolder: NoteBucket?
    @State private var pendingRename: UUID?

    enum NoteRoute: Hashable {
        case page(UUID, focus: NoteEditorFocus)
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
        // Once per account, and never over the welcome tour.
        .onAppear {
            guard let walkthrough, !hasSeenNotesWalkthrough, hasSeenFirstRunTour else { return }
            walkthrough.start(notes: model)
        }
        .onChange(of: walkthrough?.request) { _, request in
            guard let request else { return }
            switch request {
            case .showShelf:
                // The To-dos chip only exists on the Inbox, All and To-dos
                // selections, and a search hides it too.
                model.selection = .inbox
                model.query = ""
                path.removeAll()
                openPage = nil
            case .openPage(let id):
                open(id, focus: .firstBlock)
            }
            walkthrough?.consumeRequest()
        }
        .sheet(item: $newFolderBucket) { bucket in
            NoteFolderSheet(
                title: "New folder in \(bucket.title)",
                name: "",
                onSave: { name, icon in model.createFolder(named: name, in: bucket, icon: icon) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            NoteFolderSheet(
                title: "Rename folder",
                name: folderName,
                showsIconPicker: false,
                onSave: { name, _ in
                    if let id = renamingFolder { model.renameFolder(id, to: name) }
                }
            )
            .presentationDetents([.medium, .large])
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
                // A page moved by a rotation is one already being read, so
                // it opens without the focus it was first opened with.
                if case .page(let id, _) = path.last {
                    path.removeLast()
                    openPageFocus = .none
                    openPage = id
                }
            } else if let page = openPage {
                openPage = nil
                path.append(.page(page, focus: .none))
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let openPage {
            NavigationStack {
                NoteEditorHost(documentID: openPage, focus: openPageFocus, onOpenLinked: { open($0) })
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

    /// What choosing something in the library does to the stack, stated once
    /// so the iPad rail and the phone drawer cannot drift apart.
    private var librarySelection: Binding<NoteSelection> {
        Binding(
            get: { model.selection },
            set: { selection in
                model.selection = selection
                path.removeAll()
                if !layout.isRegular { setLibrary(open: false) }
                openPage = nil
            }
        )
    }

    private var libraryHabits: () -> Void {
        {
            if !layout.isRegular { setLibrary(open: false) }
            path.append(.habits)
        }
    }

    private var libraryDrop: (_ ids: [UUID], _ bucket: NoteBucket, _ folderID: UUID?) -> Void {
        { ids, bucket, folderID in
            for id in ids { model.move(id, to: bucket, folderID: folderID) }
        }
    }

    /// The iPad rail.
    private var library: some View {
        NotesSidebar(
            snapshot: model.snapshot,
            selection: librarySelection,
            onNewFolder: { newFolderBucket = $0 },
            onOpenHabits: libraryHabits,
            habitCount: plan.snapshot.habits.count,
            onRenameFolder: startRename,
            onDeleteFolder: { model.deleteFolder($0) },
            onDropNotes: libraryDrop
        )
    }

    /// Folders and shortcuts in the phone's library sheet.
    private var libraryList: some View {
        NotesLibraryList(
            snapshot: model.snapshot,
            selection: librarySelection,
            onNewFolder: { pendingNewFolder = $0; isLibraryPresented = false },
            onOpenHabits: libraryHabits,
            habitCount: plan.snapshot.habits.count,
            onRenameFolder: { pendingRename = $0; isLibraryPresented = false },
            onDeleteFolder: { model.deleteFolder($0) },
            onDropNotes: libraryDrop
        )
    }

    /// A native page stack on iPhone, with the library one tap away.
    private var compactShell: some View {
        NavigationStack(path: $path) {
            shelf
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { isLibraryPresented = true } label: {
                            Image(systemName: "sidebar.left")
                                .walkthroughAnchor(.notesLibrary)
                        }
                        .accessibilityLabel("Browse folders")
                    }
                }
                .navigationDestination(for: NoteRoute.self, destination: destination)
        }
        .sheet(isPresented: $isLibraryPresented, onDismiss: {
            if let bucket = pendingNewFolder {
                pendingNewFolder = nil
                newFolderBucket = bucket
            } else if let id = pendingRename {
                pendingRename = nil
                startRename(id)
            }
        }) {
            NavigationStack {
                libraryList
                    .background(LifeOSTokens.canvas.resolve(scheme))
                    .navigationTitle("Your library")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isLibraryPresented = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .tint(LifeOSTokens.accent)
        }
    }

    private func setLibrary(open: Bool) { isLibraryPresented = open }

    @ViewBuilder
    private func destination(_ route: NoteRoute) -> some View {
        switch route {
        case .page(let id, let focus):
            NoteEditorHost(documentID: id, focus: focus, onOpenLinked: { open($0) })
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
            onOpenNew: { open($0, focus: .title) },
            // Offered only where there is a library to collapse.
            onToggleLibrary: layout.isRegular ? { isLibraryVisible.toggle() } : nil,
            isLibraryVisible: isLibraryVisible,
            isSearchFocused: $isSearchFocused
        )
        .navigationBarTitleDisplayMode(.inline)
        .shellToolbar()
    }

    /// What the hardware keyboard drives. Built here because only the shell
    /// knows whether a page is pushed or shown beside the shelf.
    private var commandTarget: NotesCommandTarget {
        NotesCommandTarget(
            newPage: { if let id = model.createNote() { open(id, focus: .title) } },
            newFolder: { newFolderBucket = model.activeBucket },
            todaysJournal: { if let id = model.openTodaysJournal() { open(id) } },
            focusSearch: {
                // Return to the page list before focusing its search field.
                path.removeAll()
                isSearchFocused = true
            },
            toggleLibrary: {
                if layout.isRegular { isLibraryVisible.toggle() } else { setLibrary(open: !isLibraryPresented) }
            },
            selectBucket: { bucket in
                model.selection = .bucket(bucket)
                path.removeAll()
                openPage = nil
            },
            selectInbox: {
                model.selection = .inbox
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

    /// Opens a page wherever this arrangement puts one, focusing what the
    /// caller asked for: the title for a page just made, nothing otherwise.
    private func open(_ id: UUID, focus: NoteEditorFocus = .none) {
        if isThreeColumn {
            openPageFocus = focus
            openPage = id
        } else {
            path.append(.page(id, focus: focus))
        }
    }

    private func startRename(_ id: UUID) {
        folderName = model.folderSnapshot(id)?.name ?? ""
        renamingFolder = id
    }
}


/// Builds an editor view model for one page and keeps it alive for as long as
/// the page is on screen.
///
/// A separate view because the model has to be created with the document id in
/// hand, and `@State` cannot be initialised from a navigation destination's
/// argument without a wrapper like this one.
struct NoteEditorHost: View {
    let documentID: UUID
    var focus: NoteEditorFocus = .none
    var onOpenLinked: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.noteSync) private var sync
    @State private var model: NoteEditorViewModel?

    var body: some View {
        Group {
            if let model, model.documentID == documentID {
                NoteEditorScreen(model: model, focusOnAppear: focus, onOpenLinked: onOpenLinked)
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
        // A tick from the To-dos chip or the day screen beside this page
        // must reach it before its next save writes the old blocks back.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model?.reloadIfClean()
        }
    }
}

/// Name and icon for a folder, used for both creating and renaming.
struct NoteFolderSheet: View {
    let title: String
    @State var name: String
    var showsIconPicker = true
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

                if showsIconPicker {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
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
