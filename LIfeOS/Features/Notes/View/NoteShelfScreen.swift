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
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .top, spacing: Space.x2) {
                    if let onToggleLibrary {
                        Button(action: onToggleLibrary) {
                            Image(systemName: "sidebar.leading")
                        }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                        .accessibilityLabel(isLibraryVisible ? "Hide library" : "Show library")
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                    EditorialMasthead(eyebrow: NotesHeadline.eyebrow(count: model.cards.count),
                                      title: model.headerTitle)
                    creationMenu
                }

                searchField

                EditorialSectionHeader(title: "Pages") {
                    HStack(spacing: Space.x1) {
                        if model.selection.bucket != nil || model.selection.folderID != nil {
                            Menu {
                                Picker("Page type", selection: $model.filter) {
                                    ForEach(NoteShelfFilter.allCases) { filter in
                                        Label(filter.title, systemImage: filter.systemImage).tag(filter)
                                    }
                                }
                            } label: {
                                Text(model.filter.title)
                            }
                            .buttonStyle(.editorial(.quiet, size: .compact))
                            .accessibilityLabel("Filter pages")
                        }
                        Menu {
                            Picker("Sort pages", selection: $model.sort) {
                                ForEach(NoteSort.allCases) { sort in
                                    Label(sort.title, systemImage: sort.systemImage).tag(sort)
                                }
                            }
                        } label: {
                            Text(model.sort.title)
                        }
                        .buttonStyle(.editorial(.quiet, size: .compact))
                        .accessibilityLabel("Sort: \(model.sort.title)")
                    }
                }

                if model.cards.isEmpty {
                    if model.isSearching {
                        VStack(alignment: .leading, spacing: Space.x2) {
                            Text("No matching pages").font(LifeOSType.rowTitle)
                            Text("Try another title or a word from your notes.")
                                .font(LifeOSType.secondary).foregroundStyle(secondary)
                            Button("Clear search") { model.query = "" }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                        }
                        .editorialCard()
                    } else {
                        EditorialEmptyState(
                            sentence: "Pages, journals and task lists, all in one place.",
                            action: "Create a page",
                            onAction: { open(model.createNote()) }
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                EditorialRow("Monday journal", value: "Today")
                                EditorialRow("Groceries", value: "3 of 8")
                                EditorialRow("Ideas for the trip", value: "Yesterday")
                            }
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
                            Hairline()
                        }
                    }
                }

                Spacer(minLength: layout.contentBottomInset)
            }
            .padding(.horizontal, layout.gutter)
            .padding(.top, Space.x2)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .foregroundStyle(primary)
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    private var searchField: some View {
        VStack(spacing: Space.half) {
            HStack(spacing: Space.x1) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                TextField("Search all pages", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused).submitLabel(.search)
                    .autocorrectionDisabled()
                    .font(LifeOSType.body)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    private var creationMenu: some View {
        Menu {
            Button("Blank page", systemImage: "doc") { open(model.createNote(kind: .note)) }
            Button("Today's journal", systemImage: "book.closed") { open(model.openTodaysJournal()) }
            Button("Task list", systemImage: "checklist") { open(model.createNote(kind: .task)) }
            Divider()
            Button("New folder", systemImage: "folder.badge.plus") { onNewFolder(model.activeBucket) }
        } label: {
            Text("New page")
        }
        .buttonStyle(.editorial(.primary, size: .compact))
        .accessibilityLabel("Create a page or folder")
    }

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
