import SwiftUI
import DesignSystem
import Persistence

/// A searchable page library, shared by iPhone and iPad columns.
struct NoteShelfScreen: View {
    @Bindable var model: NotesViewModel
    var openPageID: UUID?
    var onOpen: (UUID) -> Void
    var onNewFolder: (NoteBucket) -> Void
    var onToggleLibrary: (() -> Void)?
    var isLibraryVisible = true
    var isSearchFocused: Binding<Bool>?
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    if let onToggleLibrary {
                        Button(action: onToggleLibrary) {
                            Image(systemName: "sidebar.leading").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(isLibraryVisible ? "Hide library" : "Show library")
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                    Text(model.headerTitle).font(.largeTitle.bold()).tracking(-0.7)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    creationMenu
                }
                searchField
                HStack {
                    Text("\(model.cards.count) \(model.cards.count == 1 ? "page" : "pages")")
                        .font(.subheadline).foregroundStyle(secondary)
                    Spacer()
                    if model.selection.bucket != nil || model.selection.folderID != nil {
                        Menu {
                            Picker("Page type", selection: $model.filter) {
                                ForEach(NoteShelfFilter.allCases) { filter in
                                    Label(filter.title, systemImage: filter.systemImage).tag(filter)
                                }
                            }
                        } label: {
                            Label(model.filter.title, systemImage: "line.3.horizontal.decrease")
                                .font(.subheadline).frame(minHeight: 44)
                        }
                        .accessibilityLabel("Filter pages")
                    }
                    Menu {
                        Picker("Sort pages", selection: $model.sort) {
                            ForEach(NoteSort.allCases) { sort in
                                Label(sort.title, systemImage: sort.systemImage).tag(sort)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Sort: \(model.sort.title)")
                }
                if model.cards.isEmpty {
                    ContentUnavailableView {
                        Label(model.isSearching ? "No matching pages" : "Room for your next idea", systemImage: "doc.text")
                    } description: {
                        Text(model.isSearching ? "Try another title or a word from your notes." : "Start a page, make a checklist, or sketch something out.")
                    } actions: {
                        if model.isSearching {
                            Button("Clear search") { model.query = "" }
                        } else {
                            Button("Create a page") { open(model.createNote()) }
                                .buttonStyle(.editorial(.primary, size: .compact))
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.cards) { card in
                            NoteCard(card: card, isOpen: card.id == openPageID,
                                onOpen: { onOpen(card.id) },
                                onFavorite: { model.toggleFavorite(card.id) },
                                onArchive: { model.toggleArchive(card.id) },
                                onDelete: { model.delete(card.id) },
                                moveTargets: moveTargets,
                                onMove: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) })
                            if card.id != model.cards.last?.id { Divider().padding(.leading, 54) }
                        }
                    }
                    .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 16))
                }
                Spacer(minLength: layout.contentBottomInset)
            }
            .padding(.horizontal, layout.isRegular ? 24 : 20)
            .padding(.top, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .foregroundStyle(primary)
        .tint(LifeOSTokens.accent)
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(secondary)
            TextField("Search all pages", text: $model.query)
                .textFieldStyle(.plain).focused($searchFocused).submitLabel(.search)
                .autocorrectionDisabled()
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 32, height: 44)
                }.accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var creationMenu: some View {
        Menu {
            Button("Blank page", systemImage: "doc") { open(model.createNote(kind: .note)) }
            Button("Today's journal", systemImage: "book.closed") { open(model.openTodaysJournal()) }
            Button("Task list", systemImage: "checklist") { open(model.createNote(kind: .task)) }
            Divider()
            Button("New folder", systemImage: "folder.badge.plus") { onNewFolder(model.activeBucket) }
        } label: {
            Image(systemName: "plus").font(.body.weight(.semibold))
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 44, height: 44)
                .background(primary, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Create a page or folder")
    }

    /// Every shelf, and every folder on it, flattened for the move menu.
    /// Nested folders are shown with their parent's name in front, since a menu
    /// has no indentation to say what is inside what.
    private var moveTargets: [NoteMoveTarget] {
        var targets: [NoteMoveTarget] = []

        for bucket in NoteBucket.filing {
            targets.append(NoteMoveTarget(bucket: bucket, folderID: nil, title: bucket.title))

            func walk(_ folders: [NoteFolderSnapshot], prefix: String) {
                for folder in folders {
                    let name = prefix.isEmpty ? folder.name : "\(prefix) / \(folder.name)"
                    targets.append(
                        NoteMoveTarget(bucket: bucket, folderID: folder.id, title: name)
                    )
                    walk(folder.children, prefix: name)
                }
            }
            walk(model.snapshot.folders(in: bucket), prefix: "")
        }
        return targets
    }

    private func open(_ id: UUID?) {
        guard let id else { return }
        onOpen(id)
    }
}
