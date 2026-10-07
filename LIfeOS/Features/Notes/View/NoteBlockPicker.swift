import SwiftUI
import DesignSystem
import Persistence

/// The row above the keyboard: six kinds as labelled chips, the rest behind
/// `More`, then Indent, Outdent and Draw. The current kind is the one filled
/// chip, so a person can see what the block they are in already is before
/// they change it. `Hide keyboard` stays outside, pinned by the bar.
struct NoteBlockPicker: View {
    let currentKind: NoteBlockKind
    var isInking: Bool
    var onPick: (NoteBlockKind) -> Void
    var onIndent: (Int) -> Void
    var onToggleInk: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.x1) {
                ForEach(NoteBlockKind.barOrder) { kind in
                    chip(kind)
                }
                Menu {
                    ForEach(NoteBlockKind.moreOrder) { kind in
                        Button(kind.title, systemImage: kind.systemImage) { onPick(kind) }
                    }
                } label: {
                    Label(NoteBlockKind.moreOrder.contains(currentKind) ? currentKind.chipTitle : "More",
                          systemImage: "ellipsis")
                }
                .buttonStyle(.editorial(NoteBlockKind.moreOrder.contains(currentKind) ? .primary : .secondary, size: .compact))
                .accessibilityLabel("More block types")
                Button { onIndent(1) } label: { Label("Indent", systemImage: "increase.indent") }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                Button { onIndent(-1) } label: { Label("Outdent", systemImage: "decrease.indent") }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                Button(action: onToggleInk) {
                    Label(isInking ? "Stop drawing" : "Draw", systemImage: "scribble.variable")
                }
                .buttonStyle(.editorial(isInking ? .primary : .secondary, size: .compact))
            }
            .font(LifeOSType.label)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ kind: NoteBlockKind) -> some View {
        Button { onPick(kind) } label: {
            Label(kind.chipTitle, systemImage: kind.systemImage)
        }
        .buttonStyle(.editorial(kind == currentKind ? .primary : .secondary, size: .compact))
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(kind == currentKind ? [.isSelected] : [])
    }
}
