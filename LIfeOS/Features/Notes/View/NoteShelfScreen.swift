import SwiftUI
import DesignSystem
import Persistence

/// The page library, shared by iPhone and iPad columns: the Inbox, All or
/// To-dos stream, or one shelf or folder, over the same search.
///
/// A `List` on paper rather than a scroll view, so a card can carry swipe
/// actions; everything that is not a card is a row too, with the list's
/// own chrome switched off.
struct NoteShelfScreen: View {
    @Bindable var model: NotesViewModel
    var openPageID: UUID?
    var onOpen: (UUID) -> Void
    /// A page `New` just made: opened with its title focused.
    var onOpenNew: (UUID) -> Void
    var onToggleLibrary: (() -> Void)?
    var isLibraryVisible = true
    var isSearchFocused: Binding<Bool>?
    /// Bumped by the hub to bring the masthead back into view.
    var scrollToTop = 0
    @FocusState private var searchFocused: Bool
    @State private var filing: NoteCardSnapshot?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Group {
                    mastheadRow
                        .id(Self.topRow)
                    searchField
                    if model.isStream, !model.isSearching {
                        chips
                    } else if !model.isSearching {
                        pagesHeader
                    }
                    content
                    Color.clear.frame(height: layout.contentBottomInset)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: Space.x3, trailing: layout.gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onChange(of: scrollToTop) { proxy.scrollTo(Self.topRow, anchor: .top) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .foregroundStyle(primary)
        .sheet(item: $filing) { card in
            NoteFilingSheet(
                targets: model.moveTargets(), currentBucket: card.isInInbox ? nil : card.bucket, currentFolderID: card.folderID,
                onPick: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) },
                onCreateFolder: { model.makeFolder(named: $0, in: $1) }
            )
        }
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    private static let topRow = "shelf.top"

    // MARK: Rows above the cards

    private var mastheadRow: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            if let onToggleLibrary {
                Button(action: onToggleLibrary) {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(.editorial(.secondary, size: .compact))
                .accessibilityLabel(isLibraryVisible ? "Hide library" : "Show library")
                .keyboardShortcut("s", modifiers: [.command, .control])
                .walkthroughAnchor(.notesLibrary)
            }
            EditorialMasthead(eyebrow: NotesHeadline.eyebrow(model.scope, count: model.headerCount),
                              title: model.headerTitle)
            Button("New") { open(model.createNote(kind: .note), isNew: true) }
                .buttonStyle(.editorial(.primary, size: .compact))
                .accessibilityLabel("New page")
                .accessibilityHint("Starts a page in your Inbox")
                .walkthroughAnchor(.notesNew)
        }
        .padding(.top, Space.x2)
    }

    private var searchField: some View {
        HairlineField(text: $model.query, placeholder: "Search all pages", focus: $searchFocused)
    }

    private var chips: some View {
        UnderlinePicker(
            selection: Binding(get: { model.selection.streamChip ?? .inbox },
                               set: { model.selection = NoteSelection(chip: $0) }),
            options: [(NoteStreamChip.inbox, "Inbox"), (.all, "All"), (.todos, "To-dos")],
            anchors: [.todos: .notesTodos]
        )
    }

    private var pagesHeader: some View {
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
                    .buttonStyle(.editorial(.secondary, size: .compact))
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
                .buttonStyle(.editorial(.secondary, size: .compact))
                .accessibilityLabel("Sort: \(model.sort.title)")
            }
        }
    }

    // MARK: The rows

    @ViewBuilder
    private var content: some View {
        if model.selection == .todos, !model.isSearching {
            if model.tasks.isEmpty {
                Text("No open to-dos.").font(LifeOSType.secondary).foregroundStyle(quiet)
            }
            ForEach(model.tasks) { group in
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(group.page.title).font(LifeOSType.caption).foregroundStyle(quiet).lineLimit(1)
                    ChecklistRows(rows: group.rows,
                                  onTick: { row in
                                      if case .page(let documentID, let blockID) = row.source {
                                          model.toggleTask(documentID: documentID, blockID: blockID)
                                      }
                                  },
                                  onOpen: { _ in onOpen(group.page.id) })
                }
            }
        } else if model.cards.isEmpty {
            emptyState
        } else {
            ForEach(model.cards) { card in
                VStack(spacing: 0) {
                    NoteCard(card: card, isOpen: card.id == openPageID,
                        onOpen: { onOpen(card.id) },
                        onFavorite: { model.toggleFavorite(card.id) },
                        onArchive: { model.toggleArchive(card.id) },
                        onDelete: { model.delete(card.id) },
                        moveTargets: model.moveTargets(),
                        onMove: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) })
                    Hairline()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    // An archived page is restored first, from the other edge.
                    if !card.isArchived {
                        Button("File", systemImage: "tray.and.arrow.down") { filing = card }
                            .tint(LifeOSTokens.primaryText.resolve(scheme))
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(card.isArchived ? "Restore" : "Archive",
                           systemImage: card.isArchived ? "tray.and.arrow.up" : "archivebox") {
                        model.toggleArchive(card.id)
                    }
                    .tint(Editorial.quietInk(scheme))
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearching {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("No matching pages").font(LifeOSType.rowTitle)
                Text("Try another title or a word from your notes.")
                    .font(LifeOSType.secondary).foregroundStyle(quiet)
                Button("Clear search") { model.query = "" }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
            .editorialCard()
        } else if model.selection == .inbox {
            EditorialEmptyState(
                sentence: "Nothing waiting. New starts a page here.",
                action: "New page",
                onAction: { open(model.createNote(kind: .note), isNew: true) }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialRow("A thought worth keeping", value: "Just now")
                    EditorialRow("Call the dentist", value: "To-do")
                }
            }
        } else {
            EditorialEmptyState(
                sentence: "Pages, journals and task lists, all in one place.",
                action: "New page",
                onAction: { open(model.createNote(kind: .note), isNew: true) }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialRow("Monday journal", value: "Today")
                    EditorialRow("Groceries", value: "3 of 8")
                    EditorialRow("Ideas for the trip", value: "Yesterday")
                }
            }
        }
    }

    private func open(_ id: UUID?, isNew: Bool = false) {
        guard let id else { return }
        if isNew { onOpenNew(id) } else { onOpen(id) }
    }
}
