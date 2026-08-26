import SwiftUI
import DesignSystem
import Persistence

/// One shelf, one folder, or one of the two cross-cutting lists.
///
/// The layout follows the reference: a breadcrumb, a display-size serif title,
/// a paragraph explaining what the shelf is for, a row of tabs, and then the
/// grid. The paragraph is the part that earns its space here: PARA only works
/// if a person knows what belongs where, and a folder app that never says so
/// leaves them to guess.
struct NoteShelfScreen: View {
    @Bindable var model: NotesViewModel
    var onOpen: (UUID) -> Void
    var onNewFolder: (NoteBucket) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: layout.isRegular ? 3 : 2
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                breadcrumb
                title
                blurb

                if !model.isSearching, model.selection.bucket != nil || model.selection.folderID != nil {
                    filterTabs.padding(.top, 22)
                }

                controls.padding(.top, model.isSearching ? 22 : 16)

                if model.cards.isEmpty {
                    emptyState.padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.cards) { card in
                            NoteCard(
                                card: card,
                                onOpen: { onOpen(card.id) },
                                onFavorite: { model.toggleFavorite(card.id) },
                                onArchive: { model.toggleArchive(card.id) },
                                onDelete: { model.delete(card.id) }
                            )
                        }
                    }
                    .padding(.top, 14)
                }

                Spacer(minLength: layout.contentBottomInset)
            }
            .padding(.horizontal, layout.gutter)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .background(LifeOSTokens.canvas.resolve(scheme))
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("/").foregroundStyle(secondary.opacity(0.5))
                }
                if index == model.breadcrumb.count - 1, index > 0 {
                    Circle()
                        .fill(NoteAccentPalette.dot(model.headerAccent, scheme))
                        .frame(width: 7, height: 7)
                }
                Text(crumb)
                    .foregroundStyle(index == model.breadcrumb.count - 1 ? primary : secondary)
            }
        }
        .font(LifeOSType.label)
        .lineLimit(1)
    }

    private var title: some View {
        Text(model.headerTitle)
            .font(LifeOSType.display)
            .foregroundStyle(primary)
            .padding(.top, 10)
    }

    private var blurb: some View {
        Text(model.headerBlurb)
            .font(LifeOSType.secondary)
            .foregroundStyle(secondary)
            .lineSpacing(3)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.top, 8)
    }

    /// Tabs drawn as attached folder tabs sitting on a hairline, which is what
    /// the reference does and what makes them read as part of the page rather
    /// than as a segmented control dropped onto it.
    private var filterTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(NoteShelfFilter.allCases) { filter in
                    let isSelected = model.filter == filter
                    Button {
                        model.filter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImage)
                                .font(LifeOSType.caption.weight(.semibold))
                            Text(filter.title)
                                .font(LifeOSType.label.weight(isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? primary : secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 10, bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0, topTrailingRadius: 10,
                                    style: .continuous
                                )
                                .fill(LifeOSTokens.cardSurface.resolve(scheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(primary.opacity(scheme == .dark ? 0.16 : 0.09))
                .frame(height: 1)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text("\(model.cards.count) \(model.cards.count == 1 ? "page" : "pages")")
                .font(LifeOSType.rowTitle)
                .foregroundStyle(primary)

            Spacer(minLength: 0)

            Menu {
                Button("Blank page", systemImage: "doc") { open(model.createNote(kind: .note)) }
                Button("Today's journal", systemImage: "book.closed") { open(model.openTodaysJournal()) }
                Button("Task list", systemImage: "checklist") { open(model.createNote(kind: .task)) }
                Divider()
                Button("New folder", systemImage: "folder.badge.plus") { onNewFolder(model.activeBucket) }
            } label: {
                Label("New", systemImage: "plus")
                    .font(LifeOSType.label.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(LifeOSTokens.accent))
                    .foregroundStyle(.white)
            }

            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(NoteSort.allCases) { sort in
                        Label(sort.title, systemImage: sort.systemImage).tag(sort)
                    }
                }
            } label: {
                Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                    .font(LifeOSType.label)
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().strokeBorder(secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.selection.bucket?.systemImage ?? "doc.text")
                .font(LifeOSType.display.weight(.light))
                .foregroundStyle(secondary.opacity(0.6))
            Text(model.isSearching ? "No matches" : "Nothing here yet")
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(primary)
            Text(model.isSearching
                 ? "Try a shorter phrase, or a word from the body of the page."
                 : "Start a page and it will show up here.")
                .font(LifeOSType.secondary)
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)

            if !model.isSearching {
                Button("New page") { open(model.createNote()) }
                    .font(LifeOSType.rowTitle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(LifeOSTokens.accent))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func open(_ id: UUID?) {
        guard let id else { return }
        onOpen(id)
    }
}
