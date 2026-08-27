import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
import Persistence

/// One page on a shelf.
///
/// Drawn as a filled pastel tile rather than as a white card with a shadow: a
/// grid of two dozen shadowed cards is two dozen offscreen passes, and the
/// colour is doing the separating here anyway.
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

    private var ink: Color { NoteAccentPalette.ink(card.accent, scheme) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                title
                if !card.excerpt.isEmpty {
                    Text(card.excerpt)
                        .font(LifeOSType.label.weight(.regular))
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
                            // The open card is ringed in its own ink rather
                            // than the app accent: a grid of pastel cards with
                            // one orange ring reads as an error state.
                            .strokeBorder(
                                isOpen ? ink.opacity(0.55) : NoteAccentPalette.edge(scheme),
                                lineWidth: isOpen ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        // Trackpad and Magic Keyboard are the iPad's other input, and a grid
        // that gives a pointer no feedback feels dead under one.
        .hoverEffect(.lift)
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

    /// The reference this is drawn from puts a year chip and a category on one
    /// line above the title. The same two slots here carry whichever of date
    /// and folder the page actually has, so the row never collapses to nothing.
    private var header: some View {
        HStack(spacing: 8) {
            if let entryDate = card.entryDate {
                Text(entryDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(LifeOSType.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ink.opacity(0.10)))
                    .foregroundStyle(ink.opacity(0.85))
            }

            Text(card.folderName ?? card.bucket.title)
                .font(LifeOSType.caption.weight(.medium))
                .foregroundStyle(ink.opacity(0.6))
                .lineLimit(1)

            Spacer(minLength: 0)

            if card.isFavorite {
                Image(systemName: "star.fill")
                    .font(LifeOSType.eyebrow.weight(.regular))
                    .foregroundStyle(ink.opacity(0.7))
            }
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !card.icon.isEmpty {
                Text(card.icon).font(LifeOSType.body)
            }
            Text(card.title)
                .font(LifeOSType.sectionTitle)
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
        .font(LifeOSType.caption.weight(.medium))
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
