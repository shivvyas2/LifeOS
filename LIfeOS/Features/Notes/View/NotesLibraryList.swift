import SwiftUI
import DesignSystem
import Persistence

/// The library for the phone's drawer.
///
/// The iPad rail (`NotesSidebar`) is text rows on the canvas, which suits a
/// column that is always there. A drawer that slides in on a phone wants the
/// app's own card vocabulary instead: the shortcuts as a row of tiles, and
/// each PARA shelf as one soft card with a coloured spine down its edge, the
/// way the edge of a folder shows its colour on a shelf. The spine is the
/// one bold thing here; everything else is the canvas, the pastel icon
/// bubbles the rest of the app uses, and quiet type.
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
            VStack(alignment: .leading, spacing: 14) {
                searchField
                shortcuts
                ForEach(NoteBucket.allCases) { bucket in
                    shelfCard(bucket)
                }
                Spacer(minLength: 24)
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.10 : 0.05))
        )
    }

    // MARK: - Shortcuts

    /// Recent, Favourites and Habits as three tiles in a row: the things
    /// reached for most, reachable without scrolling past the shelves.
    private var shortcuts: some View {
        HStack(spacing: 8) {
            shortcutTile(.recent, title: "Recent", systemImage: "clock.fill",
                         hue: .recovery, count: snapshot.recent.count)
            shortcutTile(.favorites, title: "Favourites", systemImage: "star.fill",
                         hue: .activity, count: snapshot.favorites.count)
            Button(action: onOpenHabits) {
                tileLabel(title: "Habits", systemImage: "flame.fill", hue: .habits,
                          count: habitCount, isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens habits")
        }
    }

    private func shortcutTile(_ target: NoteSelection, title: String, systemImage: String,
                              hue: ModuleHue, count: Int) -> some View {
        Button {
            selection = target
        } label: {
            tileLabel(title: title, systemImage: systemImage, hue: hue,
                      count: count, isSelected: selection == target)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == target ? [.isSelected] : [])
    }

    private func tileLabel(title: String, systemImage: String, hue: ModuleHue,
                           count: Int, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                iconBubble(systemImage, hue: hue)
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
        .background(card(selected: isSelected))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Shelves

    /// One shelf: a card with a coloured spine, the shelf row at the top,
    /// its folders under a hairline, and a quiet row to add one.
    @ViewBuilder
    private func shelfCard(_ bucket: NoteBucket) -> some View {
        let folders = Self.flattened(snapshot.folders(in: bucket))
        let isOpen = expanded.contains(bucket)
        let hue = Self.hue(for: bucket)
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
                        iconBubble(bucket.systemImage, hue: hue)
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
                            Image(systemName: "plus")
                                .font(LifeOSType.caption.weight(.semibold))
                                .frame(width: 22)
                            Text("New folder")
                                .font(LifeOSType.secondary)
                            Spacer()
                        }
                        .foregroundStyle(secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
        .background(card(selected: false))
        // The spine: the shelf's colour down its leading edge, inside the
        // card's corner so it reads as the card's own edge and not a bar
        // beside it.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(hue.top)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 5)
        }
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
                        Circle()
                            .fill(NoteAccentPalette.dot(folder.accent, scheme))
                            .frame(width: 9, height: 9)
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

    /// The app's card: its surface, its corner, its soft shadow in light.
    /// A selected tile deepens to the primary tint rather than changing hue,
    /// so "current" never competes with the spines for colour.
    private func card(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(selected
                  ? primary.opacity(scheme == .dark ? 0.16 : 0.07)
                  : LifeOSTokens.cardSurface.resolve(scheme))
            .shadow(color: scheme == .dark || selected ? .clear : LifeOSTokens.cardShadow,
                    radius: 8, y: 2)
    }

    /// The pastel bubble the rail and the stat tiles use.
    private func iconBubble(_ symbol: String, hue: ModuleHue) -> some View {
        Image(systemName: symbol)
            .font(LifeOSType.caption.weight(.semibold))
            .foregroundStyle(hue.top)
            .frame(width: 28, height: 28)
            .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(LifeOSType.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(primary.opacity(scheme == .dark ? 0.12 : 0.05)))
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
                .fill(LifeOSTokens.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LifeOSTokens.accent.opacity(0.6), lineWidth: 1.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.14 : 0.06))
        }
    }

    /// Each shelf keeps one hue, so its spine, its bubble and (on the shelf
    /// screen) its cards agree. Archive is grey: a state, not a place.
    private static func hue(for bucket: NoteBucket) -> ModuleHue {
        switch bucket {
        case .projects: .habits
        case .areas:    .recovery
        case .research: .nutrition
        case .archive:  .body
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
