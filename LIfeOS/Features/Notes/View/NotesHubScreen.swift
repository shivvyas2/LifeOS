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
    @Environment(\.modelContext) private var context

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
    /// The phone's Inbox stream, above the pushed Library. Owned here rather
    /// than by `NoteInboxScreen` so the shell can hand it the same
    /// `ModelContext` it hands everything else.
    @State private var inbox = NoteInboxViewModel()
    /// The phone's library drawer. Open, it slides in from the leading edge
    /// and pushes the stack to the right by its own width; nothing is
    /// covered, the page moves over. Closed, it sits just off screen.
    @State private var isDrawerOpen = false
    /// The live finger offset while a drag is in flight, in points along the
    /// drawer's axis. Zero whenever nothing is being dragged.
    @State private var drawerDrag: CGFloat = 0

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
                        .quickActionsToolbar()
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
                        .quickActionsToolbar()
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

    /// What choosing something in the library does to the stack, stated once
    /// so the iPad rail and the phone drawer cannot drift apart.
    private var librarySelection: Binding<NoteSelection> {
        Binding(
            get: { model.selection },
            set: { selection in
                model.selection = selection
                // On an iPad, the shelf is the interior stack's own root,
                // so returning to it is a clear. Leaving an open page
                // beside a rail that highlights a different folder is the
                // state that makes split views confusing.
                //
                // On a phone the Library is a drawer beside the stack,
                // not a screen on it, so the stack is set to the shelf
                // outright and the drawer closes to reveal it.
                if layout.isRegular {
                    path.removeAll()
                } else {
                    path = [.shelf]
                    setDrawer(open: false)
                }
                openPage = nil
            }
        )
    }

    private var libraryHabits: () -> Void {
        {
            if !layout.isRegular { setDrawer(open: false) }
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
            query: $model.query,
            isSearchFocused: $isSearchFocused,
            onNewFolder: { newFolderBucket = $0 },
            onOpenHabits: libraryHabits,
            habitCount: plan.snapshot.habits.count,
            onRenameFolder: startRename,
            onDeleteFolder: { model.deleteFolder($0) },
            onDropNotes: libraryDrop
        )
    }

    /// The phone drawer's list: the same library as a system sidebar list.
    private var libraryList: some View {
        NotesLibraryList(
            snapshot: model.snapshot,
            selection: librarySelection,
            query: $model.query,
            isSearchFocused: $isSearchFocused,
            onNewFolder: { newFolderBucket = $0 },
            onOpenHabits: libraryHabits,
            habitCount: plan.snapshot.habits.count,
            onRenameFolder: startRename,
            onDeleteFolder: { model.deleteFolder($0) },
            onDropNotes: libraryDrop
        )
    }

    /// Phone. The Inbox stream is the root screen, so the first thing someone
    /// sees is a composer ready to write in, rather than a shelf to file into.
    /// The Library is a drawer off the leading edge rather than the front
    /// door: the nav bar's leading button, or a swipe in from that edge,
    /// slides it in and pushes the stack over to make room.
    private var compactShell: some View {
        GeometryReader { proxy in
            let width = Self.drawerWidth(in: proxy.size.width)
            let offset = drawerOffset(width: width)
            let progress = offset / width

            ZStack(alignment: .leading) {
                compactLibrary
                    .frame(width: width)
                    .offset(x: offset - width)
                    .zIndex(1)
                    // Hidden from the accessibility tree while closed, so
                    // VoiceOver does not read a rail that is off screen.
                    .accessibilityHidden(!isDrawerOpen)

                compactStack
                    // The corners round as the page moves, so the pushed
                    // stack reads as a card lifted off the drawer under it.
                    .clipShape(RoundedRectangle(cornerRadius: 28 * progress, style: .continuous))
                    .shadow(color: .black.opacity(0.18 * progress), radius: 24, x: -8)
                    .overlay {
                        // A scrim over the pushed stack: tap it to close, and
                        // it says the page is not the thing to touch right now.
                        // Present only while open, so a closed drawer leaves
                        // the stack's own touches alone.
                        if isDrawerOpen {
                            Button { setDrawer(open: false) } label: {
                                Color.black
                                    .opacity(0.22 * progress)
                                    .ignoresSafeArea()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close library")
                        }
                    }
                    // Pushed by a little over half the drawer's width, not
                    // all of it, so the page slides under the glass and is
                    // what the drawer blurs. A page shoved fully clear would
                    // leave the drawer blurring nothing but canvas.
                    .offset(x: offset * 0.58)
            }
            .simultaneousGesture(drawerDragGesture(width: width))
            .animation(drawerDrag == 0 ? .spring(response: 0.38, dampingFraction: 0.86) : nil,
                       value: isDrawerOpen)
        }
        // A query typed in the drawer shows its results on the shelf, so the
        // shelf is put up behind the drawer as soon as there is a query. Not
        // closing the drawer: the field keeps focus, and the results are one
        // swipe away rather than replacing the thing being typed into.
        .onChange(of: model.query) { _, query in
            guard !layout.isRegular, !query.isEmpty, path.last != .shelf else { return }
            path.append(.shelf)
        }
    }

    /// Two thirds of the screen, capped: enough for the rail's rows and the
    /// search field, while the pushed page stays a visible strip beside it
    /// rather than a sliver, so it is obvious what a tap out there does.
    private static func drawerWidth(in available: CGFloat) -> CGFloat {
        min(available * 0.68, 280)
    }

    /// Where the drawer's leading edge sits: 0 closed, `width` open, and
    /// anywhere between while a finger has it.
    private func drawerOffset(width: CGFloat) -> CGFloat {
        let resting: CGFloat = isDrawerOpen ? width : 0
        return min(max(resting + drawerDrag, 0), width)
    }

    private func setDrawer(open: Bool) {
        drawerDrag = 0
        isDrawerOpen = open
    }

    /// Open from the leading edge, close from anywhere. Only on the Inbox
    /// root: further in, the leading edge belongs to the navigation stack's
    /// own back swipe, and two gestures claiming it would fight.
    private func drawerDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                if isDrawerOpen {
                    drawerDrag = min(value.translation.width, 0)
                } else if path.isEmpty, value.startLocation.x < 32 {
                    drawerDrag = max(value.translation.width, 0)
                }
            }
            .onEnded { value in
                guard drawerDrag != 0 else { return }
                // Where the finger was heading, not just where it stopped: a
                // quick flick that has not crossed halfway still means "open".
                let projected = drawerOffset(width: width)
                    + (value.predictedEndTranslation.width - value.translation.width) * 0.6
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    setDrawer(open: projected > width / 2)
                }
            }
    }

    /// The drawer's contents: a header that mirrors the nav bar, then the
    /// shared library rail.
    ///
    /// Drawn to look like the screen it slides out of rather than a panel
    /// from somewhere else: the same canvas, the same type, and a glass
    /// circle in exactly the spot the nav bar's Library button occupies, so
    /// the button reads as having stayed put while the panel grew out from
    /// behind it. Tapping that circle closes the drawer.
    private var compactLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        setDrawer(open: false)
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(LifeOSType.body.weight(.medium))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close library")

                Text("Library")
                    .font(LifeOSType.sectionTitle.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            // The system bar's leading item sits this far from the edge and
            // this tall; matching both is what makes the circle line up.
            .padding(.horizontal, 16)
            .frame(height: 52)

            libraryList
        }
        .padding(.bottom, layout.contentBottomInset)
        .frame(maxHeight: .infinity, alignment: .top)
        // Glass, not canvas: the page it pushed shows through, blurred, and
        // the trailing corners round off so the panel reads as a sheet of
        // material lying over the page rather than a wall beside it.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 36, topTrailingRadius: 36,
                                   style: .continuous)
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 36, topTrailingRadius: 36,
                                   style: .continuous)
                .inset(by: -200)
        )
        .shadow(color: .black.opacity(0.12), radius: 30, x: 10)
    }

    /// The phone's navigation stack, unchanged by the drawer around it.
    private var compactStack: some View {
        NavigationStack(path: $path) {
            NoteInboxScreen(
                model: inbox,
                library: model,
                onOpen: { open($0) },
                onOpenLibrary: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        setDrawer(open: true)
                    }
                }
            )
            .padding(.bottom, layout.contentBottomInset)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .quickActionsToolbar()
            .navigationDestination(for: NoteRoute.self, destination: destination)
            .onAppear {
                inbox.attach(context)
                inbox.load()
            }
        }
        // Every other tab's model is reloaded from `RootView`'s
        // `ModelContext.didSave` fan-out, but the Inbox's view model belongs
        // to the notes tab alone, and hoisting it into `RootView` would give
        // the app shell a model nothing else uses. Reloading when the stack
        // pops back to the stream instead catches the case that fan-out
        // exists for: editing a page's title and returning leaves a stale
        // row here otherwise.
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { inbox.load() }
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
                if layout.isRegular { isLibraryVisible = true } else { setDrawer(open: true) }
                isSearchFocused = true
            },
            toggleLibrary: {
                if layout.isRegular { isLibraryVisible.toggle() } else { setDrawer(open: !isDrawerOpen) }
            },
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
