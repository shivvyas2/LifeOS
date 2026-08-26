import SwiftUI
import DesignSystem
import Persistence

/// The notes tab.
///
/// Two shells over one set of screens, matching what `RootView` already does
/// for the app as a whole. A phone gets the library as its own screen and
/// pushes into a shelf and then a page; an iPad gets the library as a permanent
/// rail with the shelf beside it, which is the layout the reference this was
/// drawn from uses and the reason it reads as a desk rather than as a list.
struct NotesHubScreen: View {
    @Bindable var model: NotesViewModel
    /// Habits did not become pages, so the tab hosts the one screen that still
    /// renders them. Passed in rather than owned here because `RootView` needs
    /// the same view model for Today's habit ticks.
    @Bindable var plan: PlanViewModel
    var onAddHabit: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    /// One navigation path, shared by both shells. The iPad's detail column
    /// pushes a page onto it exactly as the phone does, so opening a note is
    /// one code path rather than two that have to be kept in step.
    @State private var path: [NoteRoute] = []
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

    /// iPad and wide panes. The rail is a real column that takes its width out
    /// of the layout, unlike the app's tab rail, which floats: a sidebar that
    /// overlapped the shelf would put the note grid underneath it.
    private var wideShell: some View {
        HStack(spacing: 0) {
            NotesSidebar(
                snapshot: model.snapshot,
                selection: Binding(
                    get: { model.selection },
                    set: { selection in
                        model.selection = selection
                        // Selecting in the rail returns the detail column to
                        // the shelf. Leaving an open page there while the rail
                        // highlights a different folder is the state that makes
                        // split views confusing.
                        path.removeAll()
                    }
                ),
                query: $model.query,
                onNewFolder: { newFolderBucket = $0 },
                onOpenHabits: { path.append(.habits) },
                habitCount: plan.snapshot.habits.count,
                onRenameFolder: startRename,
                onDeleteFolder: { model.deleteFolder($0) }
            )
            .frame(width: 268)
            .padding(.leading, layout.railInset)
            .background(LifeOSTokens.canvas.resolve(scheme))

            Rectangle()
                .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(scheme == .dark ? 0.14 : 0.07))
                .frame(width: 1)

            NavigationStack(path: $path) {
                shelf
                    .navigationDestination(for: NoteRoute.self, destination: destination)
            }
        }
    }

    /// Phone. The library is the root screen, so the first thing someone sees
    /// is the shape of the system rather than a page of one folder's contents.
    private var compactShell: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(.noteSerif(32))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, layout.gutter)
                    .padding(.top, 4)

                NotesSidebar(
                    snapshot: model.snapshot,
                    selection: Binding(
                        get: { model.selection },
                        set: { selection in
                            model.selection = selection
                            path = [.shelf]
                        }
                    ),
                    query: $model.query,
                    onNewFolder: { newFolderBucket = $0 },
                    onOpenHabits: { path.append(.habits) },
                    habitCount: plan.snapshot.habits.count,
                    onRenameFolder: startRename,
                    onDeleteFolder: { model.deleteFolder($0) }
                )
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
            NoteEditorHost(documentID: id, onOpenLinked: { path.append(.page($0)) })
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
            onOpen: { path.append(.page($0)) },
            onNewFolder: { newFolderBucket = $0 }
        )
        .navigationBarTitleDisplayMode(.inline)
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
                    .font(.system(size: 18))
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
                                    Image(systemName: "circle.dashed").font(.system(size: 20))
                                } else {
                                    Text(candidate).font(.system(size: 22))
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
