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
    /// Driven by Command-F from the scene's menu. A binding rather than a
    /// `@FocusState` owned here, because the thing that raises it is three
    /// views up and cannot reach a focus state.
    var isSearchFocused: Binding<Bool>?
    var onNewFolder: (NoteBucket) -> Void
    /// Habits are the one thing in this tab that is not a page. See
    /// `PlanNoteMigration` for why they stayed behind.
    var onOpenHabits: () -> Void = {}
    var habitCount: Int = 0
    var onRenameFolder: (UUID) -> Void = { _ in }
    var onDeleteFolder: (UUID) -> Void = { _ in }
    /// Pages dropped onto a shelf or a folder. The folder is nil for a drop on
    /// the shelf itself, which files the page loose on that shelf.
    var onDropNotes: (_ ids: [UUID], _ bucket: NoteBucket, _ folderID: UUID?) -> Void = { _, _, _ in }

    @Environment(\.colorScheme) private var scheme
    /// Which shelves are open. All four to begin with: a first launch showing
    /// four collapsed rows tells a new user nothing about what PARA is.
    @State private var expanded: Set<NoteBucket> = Set(NoteBucket.allCases)
    /// Which row a drag is currently over. One value rather than a flag per
    /// row, because only one row can be targeted at a time and two rows both
    /// believing they are is exactly how a stuck highlight happens.
    @State private var droppingOn: NoteSelection?
    @FocusState private var searchFieldFocused: Bool

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)

                shortcut(.recent, title: "Recent", systemImage: "clock.fill",
                         hue: .recovery, count: snapshot.recent.count)
                shortcut(.favorites, title: "Favourites", systemImage: "star.fill",
                         hue: .activity, count: snapshot.favorites.count)
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
                .font(LifeOSType.label)
                .foregroundStyle(secondary)
            TextField("Search notes", text: $query)
                .font(LifeOSType.secondary)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LifeOSType.label.weight(.regular))
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
                iconBubble("flame.fill", hue: .habits)
                Text("Habits")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(primary)
                Spacer(minLength: 8)
                if habitCount > 0 { countBadge(habitCount) }
                Image(systemName: "chevron.right")
                    .font(LifeOSType.eyebrow)
                    .foregroundStyle(secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func shortcut(_ target: NoteSelection, title: String, systemImage: String,
                          hue: ModuleHue, count: Int) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 10) {
                iconBubble(systemImage, hue: hue)
                Text(title)
                    .font(LifeOSType.rowTitle.weight(selection == target ? .semibold : .regular))
                    .foregroundStyle(primary)
                Spacer(minLength: 8)
                if count > 0 { countBadge(count) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(rowHighlight(selection == target))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    /// The same pastel-bubble vocabulary as the journey rows and the stat
    /// tiles, sized for a rail row.
    private func iconBubble(_ symbol: String, hue: ModuleHue) -> some View {
        Image(systemName: symbol)
            .font(LifeOSType.caption.weight(.semibold))
            .foregroundStyle(hue.top)
            .frame(width: 26, height: 26)
            .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
    }

    /// A quiet capsule rather than a bare number, so counts read as badges
    /// instead of trailing digits.
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(LifeOSType.caption.weight(.medium))
            .foregroundStyle(secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(primary.opacity(scheme == .dark ? 0.12 : 0.05)))
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
                            .font(LifeOSType.label.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(selection == .bucket(bucket) ? primary : secondary)
                        Spacer(minLength: 4)
                        countBadge(snapshot.count(in: bucket))
                    }
                }
                .buttonStyle(.plain)

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
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isOpen ? "Collapse \(bucket.title)" : "Expand \(bucket.title)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .background {
                if droppingOn == .bucket(bucket) { dropHighlight }
            }
            .dropDestination(for: NoteDragPayload.self) { payload, _ in
                // Archive is a state, not a place, so a page dropped on it is
                // archived rather than refiled onto an "archive shelf".
                onDropNotes(payload.map(\.id), bucket, nil)
                droppingOn = nil
                return !payload.isEmpty
            } isTargeted: { targeted in
                droppingOn = targeted ? .bucket(bucket) : (droppingOn == .bucket(bucket) ? nil : droppingOn)
            }

            if isOpen {
                ForEach(folders) { folder in
                    NoteFolderRow(
                        folder: folder,
                        depth: 0,
                        selection: $selection,
                        droppingOn: $droppingOn,
                        onRename: onRenameFolder,
                        onDelete: onDeleteFolder,
                        onDropNotes: onDropNotes
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
                                .font(LifeOSType.eyebrow)
                            Spacer()
                        }
                        .font(LifeOSType.secondary)
                        .foregroundStyle(secondary.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// What a row under a drag looks like. Deliberately not the selection
    /// highlight: "this is where it will land" and "this is what you are
    /// looking at" are different statements and must not share a colour.
    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LifeOSTokens.accent.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(LifeOSTokens.accent.opacity(0.6), lineWidth: 1.5)
            )
            .padding(.horizontal, 8)
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
    @Binding var droppingOn: NoteSelection?
    var onRename: (UUID) -> Void
    var onDelete: (UUID) -> Void
    var onDropNotes: (_ ids: [UUID], _ bucket: NoteBucket, _ folderID: UUID?) -> Void

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
                        Text(folder.icon).font(LifeOSType.label.weight(.regular))
                    }
                    Text(folder.name)
                        .font(LifeOSType.rowTitle.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if folder.count > 0 {
                        Text("\(folder.count)")
                            .font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(secondary)
                    }
                }
                .foregroundStyle(isSelected ? primary : secondary)
                .padding(.leading, 14 + CGFloat(depth) * 16)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .background {
                    if droppingOn == .folder(folder.id) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LifeOSTokens.accent.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(LifeOSTokens.accent.opacity(0.6), lineWidth: 1.5)
                            )
                            .padding(.horizontal, 8)
                    } else if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(primary.opacity(scheme == .dark ? 0.14 : 0.06))
                            .padding(.horizontal, 8)
                    }
                }
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .dropDestination(for: NoteDragPayload.self) { payload, _ in
                onDropNotes(payload.map(\.id), folder.bucket, folder.id)
                droppingOn = nil
                return !payload.isEmpty
            } isTargeted: { targeted in
                let me = NoteSelection.folder(folder.id)
                droppingOn = targeted ? me : (droppingOn == me ? nil : droppingOn)
            }
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
                    droppingOn: $droppingOn,
                    onRename: onRename,
                    onDelete: onDelete,
                    onDropNotes: onDropNotes
                )
            }
        }
    }
}
