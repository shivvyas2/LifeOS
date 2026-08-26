import SwiftUI
import DesignSystem
import Persistence

/// The strip above the keyboard.
///
/// One area with three states rather than three floating panels: a slash menu
/// anchored to the caret, a link picker anchored somewhere else and a
/// formatting bar pinned to the keyboard would be three things competing for
/// the same corner of a phone screen. Here they take turns.
struct NoteAccessoryBar: View {
    let slashQuery: String?
    let linkSuggestions: [String]
    let linkQuery: String?
    let currentKind: NoteBlockKind

    var onPickBlock: (NoteBlockKind) -> Void
    var onPickLink: (String) -> Void
    var onIndent: (Int) -> Void
    var onToggleInk: () -> Void
    var isInking: Bool
    var onDismissKeyboard: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    /// Blocks whose title or subtitle matches what was typed after the slash.
    private var matches: [NoteBlockKind] {
        guard let slashQuery else { return [] }
        let trimmed = slashQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return NoteBlockKind.menuOrder }
        return NoteBlockKind.menuOrder.filter {
            $0.title.range(of: trimmed, options: .caseInsensitive) != nil
                || $0.subtitle.range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        Group {
            if slashQuery != nil {
                slashMenu
            } else if linkQuery != nil {
                linkPicker
            } else {
                formattingBar
            }
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(primary.opacity(scheme == .dark ? 0.16 : 0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Slash menu

    private var slashMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No block matches that")
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches) { kind in
                            Button { onPickBlock(kind) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: kind.systemImage)
                                        .font(LifeOSType.secondary.weight(.medium))
                                        .foregroundStyle(primary)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(primary.opacity(scheme == .dark ? 0.12 : 0.05))
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(kind.title)
                                            .font(LifeOSType.secondary.weight(.medium))
                                            .foregroundStyle(primary)
                                        Text(kind.subtitle)
                                            .font(LifeOSType.caption)
                                            .foregroundStyle(secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                // Tall enough for four rows, which is as much as a phone can
                // give up without hiding the line being typed.
                .frame(maxHeight: 208)
            }
        }
    }

    // MARK: - Link picker

    private var linkPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Text("Link to")
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(secondary)

                if linkSuggestions.isEmpty {
                    Text("no page by that name yet, keep typing to make one")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(secondary.opacity(0.8))
                } else {
                    ForEach(linkSuggestions, id: \.self) { title in
                        Button { onPickLink(title) } label: {
                            Text(title)
                                .font(LifeOSType.label)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(primary.opacity(scheme == .dark ? 0.14 : 0.06)))
                                .foregroundStyle(primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Formatting bar

    private var formattingBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(NoteBlockKind.menuOrder) { kind in
                        Button { onPickBlock(kind) } label: {
                            Image(systemName: kind.systemImage)
                                .font(LifeOSType.secondary.weight(.medium))
                                .foregroundStyle(kind == currentKind ? LifeOSTokens.accent : primary)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(kind == currentKind
                                              ? LifeOSTokens.accent.opacity(0.14)
                                              : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kind.title)
                    }

                    Divider().frame(height: 20).padding(.horizontal, 4)

                    Button { onIndent(-1) } label: {
                        Image(systemName: "decrease.indent").frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Outdent")

                    Button { onIndent(1) } label: {
                        Image(systemName: "increase.indent").frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Indent")

                    Button(action: onToggleInk) {
                        Image(systemName: "scribble.variable")
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isInking ? LifeOSTokens.accent.opacity(0.14) : .clear)
                            )
                    }
                    .accessibilityLabel(isInking ? "Stop drawing" : "Draw")
                }
                .font(LifeOSType.secondary.weight(.medium))
                .foregroundStyle(primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Hide keyboard")
        }
    }
}
