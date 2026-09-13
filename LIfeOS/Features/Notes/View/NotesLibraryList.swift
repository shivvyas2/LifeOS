import SwiftUI
import DesignSystem
import Persistence

/// The library for the phone's drawer.
///
/// The iPad rail (`NotesSidebar`) is text rows on the canvas, which suits a
/// column that is always there. A drawer that slides in on a phone wants the
/// app's own card vocabulary instead: the shortcuts as a row of tiles, and
/// each PARA shelf as one soft card. Colour is Apple's: system grays for
/// every icon square and fill, and the bright system orange for exactly one
/// thing, whatever is selected. No hue per shelf; the shelf is named by its
/// symbol and its title.
///
/// Same inputs and callbacks as the rail, so the shell can hand either the
/// same wiring.
struct NotesLibraryList: View {
    let snapshot: NotesSnapshot
    @Binding var selection: NoteSelection
    @Binding var query: String
    var isSearchFocused: Binding<Bool>?
    var onNewFolder: (NoteBucket) -> Void
    var onOpenHabits: () -> Void = {}
    var habitCount: Int = 0
    var onRenameFolder: (UUID) -> Void = { _ in }
    var onDeleteFolder: (UUID) -> Void = { _ in }
    var onDropNotes: (_ ids: [UUID], _ bucket: NoteBucket, _ folderID: UUID?) -> Void = { _, _, _ in }

    @Environment(\.colorScheme) private var scheme
    /// Which shelves are open. All four to begin with, for the same reason
    /// the rail opens them: four collapsed cards tell a new user nothing.
    @State private var expanded: Set<NoteBucket> = Set(NoteBucket.allCases)
    @State private var droppingOn: NoteSelection?
    @FocusState private var searchFieldFocused: Bool

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            // One container, so neighbouring glass tiles merge and separate
            // as they move rather than each rendering its own lens.
            GlassEffectContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    searchField
                    shortcuts
                    ForEach(NoteBucket.allCases) { bucket in
                        shelfCard(bucket)
                    }
                    Spacer(minLength: 24)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFieldFocused = true }
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(LifeOSType.label)
                .foregroundStyle(secondary)
            TextField("Search notes", text: $query)
                .font(LifeOSType.secondary)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFieldFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LifeOSType.label)
                        .foregroundStyle(secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shortcuts

    /// Recent, Favourites and Habits as three tiles in a row: the things
    /// reached for most, reachable without scrolling past the shelves.
    private var shortcuts: some View {
        HStack(spacing: 8) {
            shortcutTile(.recent, title: "Recent", systemImage: "clock.fill",
                         count: snapshot.recent.count)
            shortcutTile(.favorites, title: "Favourites", systemImage: "star.fill",
                         count: snapshot.favorites.count)
            Button(action: onOpenHabits) {
                tileLabel(title: "Habits", systemImage: "flame.fill",
                          count: habitCount, isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens habits")
        }
    }

    private func shortcutTile(_ target: NoteSelection, title: String, systemImage: String,
                              count: Int) -> some View {
        Button {
            selection = target
        } label: {
            tileLabel(title: title, systemImage: systemImage,
                      count: count, isSelected: selection == target)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == target ? [.isSelected] : [])
    }

    private func tileLabel(title: String, systemImage: String,
                           count: Int, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                iconSquare(systemImage, selected: isSelected)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(LifeOSType.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                }
            }
            Text(title)
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .libraryCard(selected: isSelected)
    }

    // MARK: - Shelves

    /// One shelf: a card with the shelf row at the top,
    /// its folders under a hairline, and a quiet row to add one.
    @ViewBuilder
    private func shelfCard(_ bucket: NoteBucket) -> some View {
        let folders = Self.flattened(snapshot.folders(in: bucket))
        let isOpen = expanded.contains(bucket)
        let isSelected = selection == .bucket(bucket)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    selection = .bucket(bucket)
                    // Selecting a collapsed shelf opens it: being sent to a
                    // screen whose contents stay hidden in the drawer that
                    // sent you there is disorienting for no benefit.
                    expanded.insert(bucket)
                } label: {
                    HStack(spacing: 10) {
                        iconSquare(Self.symbol(for: bucket), selected: isSelected)
                        Text(bucket.title)
                            .font(LifeOSType.rowTitle.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(primary)
                        Spacer(minLength: 6)
                        countBadge(snapshot.count(in: bucket))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                if !folders.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isOpen { expanded.remove(bucket) } else { expanded.insert(bucket) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(LifeOSType.eyebrow.weight(.bold))
                            .rotationEffect(.degrees(isOpen ? 0 : -90))
                            .foregroundStyle(secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isOpen ? "Collapse \(bucket.title)" : "Expand \(bucket.title)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isSelected || droppingOn == .bucket(bucket) {
                    rowHighlight(dropping: droppingOn == .bucket(bucket))
                        .padding(4)
                }
            }
            .dropDestination(for: NoteDragPayload.self) { payload, _ in
                onDropNotes(payload.map(\.id), bucket, nil)
                droppingOn = nil
                return !payload.isEmpty
            } isTargeted: { targeted in
                droppingOn = targeted ? .bucket(bucket) : (droppingOn == .bucket(bucket) ? nil : droppingOn)
            }

            if isOpen, !folders.isEmpty || bucket != .archive {
                hairline

                ForEach(folders, id: \.folder.id) { entry in
                    folderRow(entry.folder, depth: entry.depth)
                }

                // Archive is a state a page is put into, never a place
                // folders are made, so it gets no new-folder row.
                if bucket != .archive {
                    Button {
                        onNewFolder(bucket)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(LifeOSType.label)
                                .foregroundStyle(Self.orange)
                                .frame(width: 22)
                            Text("New folder")
                                .font(LifeOSType.secondary)
                                .foregroundStyle(secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
        .libraryCard(selected: false)
    }

    private func folderRow(_ folder: NoteFolderSnapshot, depth: Int) -> some View {
        let isSelected = selection == .folder(folder.id)
        let isDropping = droppingOn == .folder(folder.id)
        return Button {
            selection = .folder(folder.id)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if folder.icon.isEmpty {
                        Image(systemName: isSelected ? "folder.fill" : "folder")
                            .font(LifeOSType.label.weight(.medium))
                            .foregroundStyle(isSelected ? Self.orange : secondary)
                    } else {
                        Text(folder.icon).font(LifeOSType.label)
                    }
                }
                .frame(width: 22)
                Text(folder.name)
                    .font(LifeOSType.secondary.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? primary : primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                if folder.count > 0 {
                    Text("\(folder.count)")
                        .font(LifeOSType.caption)
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                }
            }
            .padding(.leading, 14 + CGFloat(depth) * 18)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected || isDropping {
                    rowHighlight(dropping: isDropping).padding(.horizontal, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Rename", systemImage: "pencil") { onRenameFolder(folder.id) }
            Button("Delete folder", systemImage: "trash", role: .destructive) { onDeleteFolder(folder.id) }
        }
        .dropDestination(for: NoteDragPayload.self) { payload, _ in
            onDropNotes(payload.map(\.id), folder.bucket, folder.id)
            droppingOn = nil
            return !payload.isEmpty
        } isTargeted: { targeted in
            let me = NoteSelection.folder(folder.id)
            droppingOn = targeted ? me : (droppingOn == me ? nil : droppingOn)
        }
    }

    // MARK: - Pieces

    /// The same orange used throughout LifeOS.
    static let orange = LifeOSTokens.accent
    /// Apple's grays: the fill behind an icon, and the fill behind a row.
    private var iconFill: Color { Color(uiColor: .secondarySystemFill) }
    private var rowFill: Color { Color(uiColor: .tertiarySystemFill) }


    /// The Settings-style icon: a rounded square, gray with a dark glyph,
    /// or orange with a white one for whatever is selected.
    private func iconSquare(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(LifeOSType.rowTitle.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selected ? .white : primary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Self.orange : iconFill)
            )
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(LifeOSType.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)

    }

    private var hairline: some View {
        Rectangle()
            .fill(primary.opacity(scheme == .dark ? 0.12 : 0.06))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    /// "This is what you are looking at" and "this is where it will land"
    /// are different statements and do not share a colour.
    @ViewBuilder
    private func rowHighlight(dropping: Bool) -> some View {
        if dropping {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.orange.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Self.orange.opacity(0.7), lineWidth: 1.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        }
    }

    /// Filled symbols, so the glyph reads at a glance in a small square.
    private static func symbol(for bucket: NoteBucket) -> String {
        switch bucket {
        case .projects: "target"
        case .areas:    "square.grid.2x2.fill"
        case .research: "books.vertical.fill"
        case .archive:  "archivebox.fill"
        }
    }

    /// Folders and their children in display order, each with its depth.
    private static func flattened(_ folders: [NoteFolderSnapshot], depth: Int = 0)
        -> [(folder: NoteFolderSnapshot, depth: Int)] {
        folders.flatMap { folder in
            [(folder, depth)] + flattened(folder.children, depth: depth + 1)
        }
    }
}

private extension View {
    /// Quiet surfaces with an orange selection state.
    @ViewBuilder
    func libraryCard(selected: Bool) -> some View {
        self.background(selected ? NotesLibraryList.orange.opacity(0.09) : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
    }
}
