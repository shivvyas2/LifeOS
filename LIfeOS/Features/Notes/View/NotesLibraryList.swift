import SwiftUI
import DesignSystem
import Persistence

/// The library as a system sidebar list, for the phone's drawer.
///
/// The iPad rail (`NotesSidebar`) is text rows on the canvas, which suits a
/// column that is always there. A drawer that slides in on a phone is read
/// the way Settings and Files are read: grouped sections, tinted icon
/// squares, native headers, swipe actions. So this is a `List` in the
/// sidebar style, with the same inputs and the same callbacks as the rail,
/// and the shell decides which one to show.
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
    /// the rail opens them: four collapsed headers tell a new user nothing.
    @State private var expanded: Set<NoteBucket> = Set(NoteBucket.allCases)
    @State private var droppingOn: NoteSelection?
    @FocusState private var searchFieldFocused: Bool

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        List {
            Section {
                searchRow
            }

            Section {
                shortcutRow(.recent, title: "Recent", systemImage: "clock.fill",
                            tint: ModuleHue.recovery.top, count: snapshot.recent.count)
                shortcutRow(.favorites, title: "Favourites", systemImage: "star.fill",
                            tint: ModuleHue.activity.top, count: snapshot.favorites.count)
                habitsRow
            }

            ForEach(NoteBucket.allCases) { bucket in
                shelfSection(bucket)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .scrollIndicators(.hidden)
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFieldFocused = true }
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    // MARK: - Rows

    private var searchRow: some View {
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
                        .foregroundStyle(secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
    }

    private func shortcutRow(_ target: NoteSelection, title: String, systemImage: String,
                             tint: Color, count: Int) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 12) {
                iconSquare(systemImage, tint: tint)
                Text(title)
                    .font(LifeOSType.rowTitle.weight(.regular))
                    .foregroundStyle(primary)
                Spacer(minLength: 8)
                if count > 0 { countText(count) }
            }
        }
        .listRowBackground(rowBackground(selection == target))
    }

    private var habitsRow: some View {
        Button(action: onOpenHabits) {
            HStack(spacing: 12) {
                iconSquare("flame.fill", tint: ModuleHue.habits.top)
                Text("Habits")
                    .font(LifeOSType.rowTitle.weight(.regular))
                    .foregroundStyle(primary)
                Spacer(minLength: 8)
                if habitCount > 0 { countText(habitCount) }
                Image(systemName: "chevron.right")
                    .font(LifeOSType.eyebrow.weight(.semibold))
                    .foregroundStyle(secondary.opacity(0.6))
            }
        }
    }

    /// One shelf: a collapsible section whose first row is the shelf itself,
    /// then its folders, then a row to add one.
    @ViewBuilder
    private func shelfSection(_ bucket: NoteBucket) -> some View {
        let folders = Self.flattened(snapshot.folders(in: bucket))
        Section(isExpanded: expandedBinding(bucket)) {
            Button {
                selection = .bucket(bucket)
            } label: {
                HStack(spacing: 12) {
                    iconSquare(bucket.systemImage, tint: LifeOSTokens.accent)
                    Text("All \(bucket.title.lowercased())")
                        .font(LifeOSType.rowTitle.weight(.regular))
                        .foregroundStyle(primary)
                    Spacer(minLength: 8)
                    countText(snapshot.count(in: bucket))
                }
            }
            .listRowBackground(rowBackground(selection == .bucket(bucket) || droppingOn == .bucket(bucket)))
            .dropDestination(for: NoteDragPayload.self) { payload, _ in
                onDropNotes(payload.map(\.id), bucket, nil)
                droppingOn = nil
                return !payload.isEmpty
            } isTargeted: { targeted in
                droppingOn = targeted ? .bucket(bucket) : (droppingOn == .bucket(bucket) ? nil : droppingOn)
            }

            ForEach(folders, id: \.folder.id) { entry in
                folderRow(entry.folder, depth: entry.depth)
            }

            // Archive is a state a page is put into, never a place folders
            // are made, so it gets no new-folder row.
            if bucket != .archive {
                Button {
                    onNewFolder(bucket)
                } label: {
                    Label("New folder", systemImage: "plus")
                        .font(LifeOSType.rowTitle.weight(.regular))
                        .foregroundStyle(LifeOSTokens.accent)
                }
            }
        } header: {
            Text(bucket.title)
        }
    }

    private func folderRow(_ folder: NoteFolderSnapshot, depth: Int) -> some View {
        let isSelected = selection == .folder(folder.id)
        return Button {
            selection = .folder(folder.id)
        } label: {
            HStack(spacing: 12) {
                if folder.icon.isEmpty {
                    Circle()
                        .fill(NoteAccentPalette.dot(folder.accent, scheme))
                        .frame(width: 10, height: 10)
                        .frame(width: 28)
                } else {
                    Text(folder.icon)
                        .font(LifeOSType.body)
                        .frame(width: 28)
                }
                Text(folder.name)
                    .font(LifeOSType.rowTitle.weight(.regular))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if folder.count > 0 { countText(folder.count) }
            }
            .padding(.leading, CGFloat(depth) * 20)
        }
        .listRowBackground(rowBackground(isSelected || droppingOn == .folder(folder.id)))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDeleteFolder(folder.id) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onRenameFolder(folder.id) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(LifeOSTokens.accent)
        }
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

    /// The Settings-style tinted square: white glyph on a solid colour.
    private func iconSquare(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(LifeOSType.label.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
    }

    private func countText(_ count: Int) -> some View {
        Text("\(count)")
            .font(LifeOSType.label.weight(.regular))
            .monospacedDigit()
            .foregroundStyle(secondary)
    }

    /// The selected row's ground, in the accent's soft tint the way a native
    /// sidebar marks the current item. Nil leaves the system cell colour.
    private func rowBackground(_ isSelected: Bool) -> Color? {
        isSelected ? LifeOSTokens.accentSoft.resolve(scheme) : nil
    }

    private func expandedBinding(_ bucket: NoteBucket) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(bucket) },
            set: { open in
                if open { expanded.insert(bucket) } else { expanded.remove(bucket) }
            }
        )
    }

    /// Folders and their children in display order, each with its depth, so
    /// a `List` can show the tree as rows.
    private static func flattened(_ folders: [NoteFolderSnapshot], depth: Int = 0)
        -> [(folder: NoteFolderSnapshot, depth: Int)] {
        folders.flatMap { folder in
            [(folder, depth)] + flattened(folder.children, depth: depth + 1)
        }
    }
}
