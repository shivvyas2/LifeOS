import SwiftUI
import DesignSystem
import Persistence

/// One page on a shelf.
///
/// Drawn as a filled pastel tile rather than as a white card with a shadow: a
/// grid of two dozen shadowed cards is two dozen offscreen passes, and the
/// colour is doing the separating here anyway.
struct NoteCard: View {
    let card: NoteCardSnapshot
    var onOpen: () -> Void
    var onFavorite: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { NoteAccentPalette.ink(card.accent, scheme) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                title
                if !card.excerpt.isEmpty {
                    Text(card.excerpt)
                        .font(.system(size: 14))
                        .foregroundStyle(ink.opacity(0.68))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                footer
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NoteAccentPalette.fill(card.accent, scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(NoteAccentPalette.edge(scheme), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(card.isFavorite ? "Remove from favourites" : "Add to favourites",
                   systemImage: card.isFavorite ? "star.slash" : "star", action: onFavorite)
            Button(card.isArchived ? "Restore" : "Archive",
                   systemImage: card.isArchived ? "tray.and.arrow.up" : "archivebox", action: onArchive)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.title)
        .accessibilityHint(card.excerpt)
    }

    /// The reference this is drawn from puts a year chip and a category on one
    /// line above the title. The same two slots here carry whichever of date
    /// and folder the page actually has, so the row never collapses to nothing.
    private var header: some View {
        HStack(spacing: 8) {
            if let entryDate = card.entryDate {
                Text(entryDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ink.opacity(0.10)))
                    .foregroundStyle(ink.opacity(0.85))
            }

            Text(card.folderName ?? card.bucket.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
                .lineLimit(1)

            Spacer(minLength: 0)

            if card.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.7))
            }
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !card.icon.isEmpty {
                Text(card.icon).font(.system(size: 17))
            }
            Text(card.title)
                .font(.noteSerif(21))
                .foregroundStyle(ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if card.taskCount > 0 {
                Label("\(card.doneCount)/\(card.taskCount)", systemImage: "checkmark.circle")
                    .labelStyle(.titleAndIcon)
            }
            if card.linkCount > 0 {
                Label("\(card.linkCount)", systemImage: "link")
            }
            if card.hasInk {
                Image(systemName: "scribble")
            }
            Spacer(minLength: 0)
            Text(card.updatedAt.formatted(.relative(presentation: .numeric)))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ink.opacity(0.62))
    }
}

#Preview {
    let card = NoteCardSnapshot(
        id: UUID(), title: "Marathon block, week four", icon: "",
        excerpt: "Long run moved to Sunday. Calf held up. Keep the Tuesday session easy.",
        accent: .sage, kind: .note, bucket: .projects, folderID: nil, folderName: "Training",
        entryDate: .now, dueDate: nil, status: .inProgress, updatedAt: .now,
        isFavorite: true, isArchived: false, doneCount: 2, taskCount: 5,
        hasInk: true, linkCount: 3
    )
    return ZStack {
        LifeOSTokens.canvas.resolve(.light).ignoresSafeArea()
        NoteCard(card: card, onOpen: {})
            .frame(width: 240)
    }
}
