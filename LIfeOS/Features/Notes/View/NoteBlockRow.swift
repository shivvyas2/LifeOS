import SwiftUI
import DesignSystem
import Persistence

/// One block: its gutter mark, its text, and the ground it sits on.
///
/// The gutter is drawn in SwiftUI and the text in UIKit. Putting the bullet
/// inside the text view as a literal character was the alternative, and it
/// makes the bullet editable, which means it can be deleted, which means a list
/// item can silently stop being one.
struct NoteBlockRow: View {
    let block: NoteBlock
    let index: Int
    /// The number this row shows when it is part of a numbered run. Computed by
    /// the editor across the whole document, because a run restarts after any
    /// other kind of block and a row cannot see its neighbours.
    let ordinal: Int?
    let isFocused: Bool

    var onChangeText: (String) -> Void
    var onToggleCheck: () -> Void
    var onReturn: (String, String) -> Void
    var onBackspaceAtStart: () -> Bool
    var onIndent: (Int) -> Void
    var onFocus: () -> Void
    var onTransform: (NoteBlockKind, String) -> Void
    var onSlashQuery: (String?) -> Void
    var onLinkQuery: (String?) -> Void

    @Environment(\.colorScheme) private var scheme

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    /// Done to-dos go grey. Deliberately no strikethrough: a page of struck
    /// text is unreadable, and the checkbox already says the same thing.
    private var textColor: Color {
        block.kind == .todo && block.isChecked ? secondary : primary
    }

    var body: some View {
        if block.kind == .divider {
            Rectangle()
                .fill(primary.opacity(scheme == .dark ? 0.18 : 0.10))
                .frame(height: 1)
                .padding(.vertical, 12)
                .padding(.leading, indentWidth)
        } else {
            HStack(alignment: .top, spacing: 8) {
                gutter
                textView
            }
            .padding(.leading, indentWidth)
            .padding(.top, BlockStyle.topPadding(block.kind, isFirst: index == 0))
            .padding(.vertical, block.kind == .callout || block.kind == .code ? 10 : 3)
            .padding(.horizontal, block.kind == .callout || block.kind == .code ? 12 : 0)
            .background(ground)
        }
    }

    private var indentWidth: CGFloat { CGFloat(block.indent) * 22 }

    @ViewBuilder
    private var gutter: some View {
        switch block.kind {
        case .bulleted:
            Circle()
                .fill(primary.opacity(0.7))
                .frame(width: 5, height: 5)
                .frame(width: 18, height: lineHeight, alignment: .center)
        case .numbered:
            Text("\(ordinal ?? 1).")
                .font(.system(size: 16))
                .foregroundStyle(secondary)
                .frame(width: 18, height: lineHeight, alignment: .trailing)
        case .todo:
            Button(action: onToggleCheck) {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(block.isChecked ? LifeOSTokens.accent : secondary)
                    .frame(width: 18, height: lineHeight, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isChecked ? "Completed" : "Not completed")
        case .quote:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(primary.opacity(0.35))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.trailing, 4)
        case .callout:
            Text("\u{1F4A1}")
                .font(.system(size: 15))
                .frame(width: 18, height: lineHeight, alignment: .center)
        default:
            EmptyView()
        }
    }

    /// The gutter mark aligns with the first line of text, not with the middle
    /// of the block, so a three-line bullet keeps its dot at the top.
    private var lineHeight: CGFloat {
        BlockStyle.font(block.kind).lineHeight + BlockStyle.lineSpacing(block.kind)
    }

    @ViewBuilder
    private var ground: some View {
        switch block.kind {
        case .callout:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LifeOSTokens.accentSoft.resolve(scheme))
        case .code:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.12 : 0.045))
        default:
            EmptyView()
        }
    }

    private var textView: some View {
        BlockTextView(
            text: Binding(get: { block.text }, set: onChangeText),
            kind: block.kind,
            isFocused: isFocused,
            placeholder: placeholder,
            linkColor: UIColor(LifeOSTokens.accent),
            textColor: UIColor(textColor),
            onReturn: onReturn,
            onBackspaceAtStart: onBackspaceAtStart,
            onIndent: onIndent,
            onFocus: onFocus,
            onTransform: onTransform,
            onSlashQuery: onSlashQuery,
            onLinkQuery: onLinkQuery
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only the focused empty block explains itself. Placeholders on every
    /// empty row at once is what makes a fresh page look like a form.
    private var placeholder: String {
        guard isFocused, block.isEmpty else { return "" }
        switch block.kind {
        case .heading1, .heading2, .heading3: return "Heading"
        case .todo:     return "To-do"
        case .quote:    return "Quote"
        case .code:     return "Code"
        case .callout:  return "Callout"
        case .bulleted, .numbered: return "List"
        default:        return "Type '/' for blocks, '[[' to link a page"
        }
    }
}
