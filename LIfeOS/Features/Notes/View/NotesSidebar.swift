import SwiftUI
import DesignSystem
import Persistence

/// The library rail: the four PARA shelves, the folders on each, and the two
/// lists that cut across them.
///
/// Text rows with a coloured dot and a count, not a `List`. `List` brings its
/// own background, its own separators and its own insets, all of which would
/// have to be undone to sit on this canvas, and none of which are wanted.
struct NotesSidebar: View {
    let snapshot: NotesSnapshot
    @Binding var selection: NoteSelection
    @Binding var query: String
    var onNewFolder: (NoteBucket) -> Void
    /// Habits are the one thing in this tab that is not a page. See
    /// `PlanNoteMigration` for why they stayed behind.
    var onOpenHabits: () -> Void = {}
    var habitCount: Int = 0
    var onRenameFolder: (UUID) -> Void = { _ in }
    var onDeleteFolder: (UUID) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    /// Which shelves are open. All four to begin with: a first launch showing
    /// four collapsed rows tells a new user nothing about what PARA is.
    @State private var expanded: Set<NoteBucket> = Set(NoteBucket.allCases)

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)

                shortcut(.recent, title: "Recent", systemImage: "clock", count: snapshot.recent.count)
                shortcut(.favorites, title: "Favourites", systemImage: "star", count: snapshot.favorites.count)
                habitsRow

                ForEach(NoteBucket.allCases) { bucket in
                    shelf(bucket)
                }

                Spacer(minLength: 24)
            }
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(secondary)
            TextField("Search notes", text: $query)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.10 : 0.05))
        )
    }

    /// Styled as a shortcut but pushing its own screen rather than selecting,
    /// because habits are ticked, not read.
    private var habitsRow: some View {
        Button(action: onOpenHabits) {
            HStack(spacing: 10) {
                Image(systemName: "flame")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 14)
                Text("Habits")
                    .font(.system(size: 15))
                Spacer(minLength: 8)
                if habitCount > 0 {
                    Text("\(habitCount)")
                        .font(.system(size: 13))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func shortcut(_ target: NoteSelection, title: String, systemImage: String, count: Int) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 15, weight: selection == target ? .semibold : .regular))
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 13))
                        .foregroundStyle(secondary)
                }
            }
            .foregroundStyle(selection == target ? primary : secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(rowHighlight(selection == target))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shelf(_ bucket: NoteBucket) -> some View {
        let folders = snapshot.folders(in: bucket)
        let isOpen = expanded.contains(bucket)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    selection = .bucket(bucket)
                    // Selecting a collapsed shelf opens it. Being sent to a
                    // screen whose contents stay hidden in the rail that sent
                    // you there is disorienting for no benefit.
                    expanded.insert(bucket)
                } label: {
                    HStack(spacing: 8) {
                        Text(bucket.title.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.6)
                        Spacer(minLength: 4)
                        Text("\(snapshot.count(in: bucket))")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(selection == .bucket(bucket) ? primary : secondary)
                }
                .buttonStyle(.plain)

                if !folders.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isOpen { expanded.remove(bucket) } else { expanded.insert(bucket) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(isOpen ? 0 : -90))
                            .foregroundStyle(secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isOpen ? "Collapse \(bucket.title)" : "Expand \(bucket.title)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 6)

            if isOpen {
                ForEach(folders) { folder in
                    NoteFolderRow(
                        folder: folder,
                        depth: 0,
                        selection: $selection,
                        onRename: onRenameFolder,
                        onDelete: onDeleteFolder
                    )
                }

                // Archive is a state a page is put into, never a place folders
                // are made, so it gets no new-folder row.
                if bucket != .archive {
                    Button {
                        onNewFolder(bucket)
                    } label: {
                        HStack(spacing: 8) {
                            Text("New folder")
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(secondary.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The selected row's ground. Inset from the rail's own edges so the
    /// highlight reads as a pill against the canvas rather than as a band
    /// running out of the panel.
    @ViewBuilder
    private func rowHighlight(_ isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.14 : 0.06))
                .padding(.horizontal, 8)
        }
    }
}


/// One folder and everything nested under it.
///
/// A named type rather than a method on the sidebar, because a `some View`
/// function that calls itself defines its opaque return type in terms of
/// itself and will not compile. A struct's body may reference the struct.
private struct NoteFolderRow: View {
    let folder: NoteFolderSnapshot
    let depth: Int
    @Binding var selection: NoteSelection
    var onRename: (UUID) -> Void
    var onDelete: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme

    private var isSelected: Bool { selection == .folder(folder.id) }
    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selection = .folder(folder.id)
            } label: {
                HStack(spacing: 9) {
                    if folder.icon.isEmpty {
                        Circle()
                            .fill(NoteAccentPalette.dot(folder.accent, scheme))
                            .frame(width: 9, height: 9)
                    } else {
                        Text(folder.icon).font(.system(size: 13))
                    }
                    Text(folder.name)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if folder.count > 0 {
                        Text("\(folder.count)")
                            .font(.system(size: 13))
                            .foregroundStyle(secondary)
                    }
                }
                .foregroundStyle(isSelected ? primary : secondary)
                .padding(.leading, 14 + CGFloat(depth) * 16)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(primary.opacity(scheme == .dark ? 0.14 : 0.06))
                            .padding(.horizontal, 8)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename", systemImage: "pencil") { onRename(folder.id) }
                Button("Delete folder", systemImage: "trash", role: .destructive) {
                    onDelete(folder.id)
                }
            }

            ForEach(folder.children) { child in
                NoteFolderRow(
                    folder: child,
                    depth: depth + 1,
                    selection: $selection,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
        }
    }
}
