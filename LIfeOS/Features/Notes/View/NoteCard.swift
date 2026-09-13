import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
import Persistence

/// A document row with a preview, filing context, and familiar page actions.
struct NoteCard: View {
    let card: NoteCardSnapshot
    /// True when this card's page is the one showing in the detail column, so
    /// a three-column layout can say which of the grid produced it.
    var isOpen = false
    var onOpen: () -> Void
    var onFavorite: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Where this page could go. Drag and drop is the quick way on an iPad,
    /// but it is a pointer gesture, so the same move has to exist as a menu.
    var moveTargets: [NoteMoveTarget] = []
    var onMove: (NoteMoveTarget) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if card.icon.isEmpty {
                        Image(systemName: card.hasInk ? "pencil.and.outline" : "doc.text")
                            .foregroundStyle(LifeOSTokens.accent)
                    } else { Text(card.icon) }
                }
                .font(.title3).frame(width: 26, height: 28)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(card.title).font(.body.weight(.semibold)).lineLimit(2)
                        if card.isFavorite {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(LifeOSTokens.accent)
                        }
                    }
                    if !card.excerpt.isEmpty {
                        Text(card.excerpt).font(.subheadline)
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text(card.folderName ?? card.bucket.title).lineLimit(1)
                        if card.taskCount > 0 {
                            Label("\(card.doneCount)/\(card.taskCount)", systemImage: "checkmark.circle")
                        }
                        Spacer(minLength: 0)
                        Text(card.updatedAt, style: .date).lineLimit(1)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(16)
            .background(isOpen ? LifeOSTokens.accent.opacity(0.09) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Trackpad and Magic Keyboard are the iPad's other input, and a grid
        // that gives a pointer no feedback feels dead under one.
        .hoverEffect(.highlight)
        // Filing is what PARA is, so a card has to be movable. The payload is
        // the page's id, and every drop target parses it back.
        .draggable(NoteDragPayload(id: card.id)) {
            NoteDragPreview(card: card)
        }
        .contextMenu {
            if !moveTargets.isEmpty {
                Menu("Move to", systemImage: "folder") {
                    ForEach(moveTargets) { target in
                        Button(target.title) { onMove(target) }
                            .disabled(target.isCurrentHome(of: card))
                    }
                }
                Divider()
            }
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


/// What a dragged card carries.
///
/// A typed payload rather than a bare string, so a folder row cannot accept a
/// paragraph of text dragged in from another app and try to file it.
struct NoteDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lifeOSNote)
    }
}

extension UTType {
    /// Same-process drags only, which is why this is `exportedAs` without a
    /// matching Info.plist declaration: nothing outside the app is ever asked
    /// to understand it.
    ///
    /// `nonisolated` because `Transferable.transferRepresentation` is, and the
    /// app target defaults to main-actor isolation.
    nonisolated static let lifeOSNote = UTType(exportedAs: "com.shivvyas.lifeos.note")
}

/// What travels under the finger. The card itself is too big to drag over a
/// sidebar row without hiding the row it is aimed at.
private struct NoteDragPreview: View {
    let card: NoteCardSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NoteAccentPalette.dot(card.accent, scheme))
                .frame(width: 8, height: 8)
            Text(card.title)
                .font(LifeOSType.label)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
    }
}


/// Somewhere a page can be filed: a shelf, or a folder on one.
struct NoteMoveTarget: Identifiable, Hashable {
    let bucket: NoteBucket
    /// Nil for the shelf itself, which files the page loose on it.
    let folderID: UUID?
    let title: String

    var id: String { "\(bucket.rawValue)-\(folderID?.uuidString ?? "root")" }

    /// Greys out the place the page already is, rather than offering a move
    /// that would do nothing.
    func isCurrentHome(of card: NoteCardSnapshot) -> Bool {
        card.bucket == bucket && card.folderID == folderID
    }
}
