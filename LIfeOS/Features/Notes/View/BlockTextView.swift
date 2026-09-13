import SwiftUI
import DesignSystem
import UIKit
import Persistence

/// Type and size for each block kind, in one place.
///
/// Both the UIKit text view and the SwiftUI chrome around it need these
/// numbers, and a heading whose bullet gutter is sized off a different font
/// than its text is a misalignment nobody can find later.
enum BlockStyle {
    /// Every step comes from `LifeOSType`, so a note's text is the same size as
    /// the same text anywhere else in the app. Three heading levels fit under
    /// the page title without inventing sizes: the third is reading text set
    /// bold, which is what a fourth-level heading is in any document.
    static func font(_ kind: NoteBlockKind) -> UIFont {
        let base: UIFont = switch kind {
        case .heading1: LifeOSType.UIKitScale.screenTitle
        case .heading2: LifeOSType.UIKitScale.sectionTitle
        case .heading3: LifeOSType.UIKitScale.bodyStrong
        case .code:     LifeOSType.UIKitScale.mono
        case .quote:    LifeOSType.UIKitScale.body
        default:        LifeOSType.UIKitScale.body
        }
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    /// Space above a block. Headings need air before them and none after, which
    /// is the difference between a document and a list of lines.
    static func topPadding(_ kind: NoteBlockKind, isFirst: Bool) -> CGFloat {
        guard !isFirst else { return 0 }
        switch kind {
        case .heading1: return 22
        case .heading2: return 18
        case .heading3: return 14
        case .divider:  return 10
        default:        return 2
        }
    }

    static func lineSpacing(_ kind: NoteBlockKind) -> CGFloat {
        switch kind {
        case .heading1, .heading2, .heading3: 2
        case .code: 3
        default: 5
        }
    }
}

/// A `UITextView` for one block.
///
/// UIKit rather than SwiftUI's `TextField`, for three things SwiftUI cannot do
/// here at all: intercept Return so it splits the block instead of inserting a
/// newline, intercept Backspace at offset zero so it merges with the block
/// above, and paint `[[links]]` as the person types. Apple Pencil Scribble
/// arrives free with `UITextView`, which is the fourth.
struct BlockTextView: UIViewRepresentable {
    @Binding var text: String
    let kind: NoteBlockKind
    let isFocused: Bool
    let placeholder: String
    let linkColor: UIColor
    let textColor: UIColor

    /// Split at the caret: everything before it stays, everything after it
    /// becomes the new block.
    var onReturn: (_ before: String, _ after: String) -> Void
    /// Backspace with the caret at the very start. Returns true if the editor
    /// handled it, in which case UIKit must not also delete a character.
    var onBackspaceAtStart: () -> Bool
    var onIndent: (Int) -> Void
    var onFocus: () -> Void
    /// A typed markdown prefix resolved to a block kind.
    var onTransform: (NoteBlockKind, String) -> Void
    /// The text after a leading "/", or nil when the slash menu should close.
    var onSlashQuery: (String?) -> Void
    /// The partial text inside an unclosed `[[`, or nil when there is none.
    var onLinkQuery: (String?) -> Void

    func makeUIView(context: Context) -> BlockUITextView {
        let view = BlockUITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false            // so it sizes to its content
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.autocorrectionType = kind == .code ? .no : .default
        view.autocapitalizationType = kind == .code ? .none : .sentences
        view.smartDashesType = kind == .code ? .no : .default
        view.smartQuotesType = kind == .code ? .no : .default
        // Scribble, on iPad with a Pencil. Writing straight into the block is
        // the whole point of the ink support, and it needs no code beyond
        // leaving the interaction enabled.
        view.isEditable = true
        view.adjustsFontForContentSizeCategory = true

        view.onDeleteBackwardAtStart = { onBackspaceAtStart() }
        view.onShiftTab = { onIndent(-1) }

        context.coordinator.apply(text: text, to: view, kind: kind, linkColor: linkColor, textColor: textColor)
        return view
    }

    func updateUIView(_ view: BlockUITextView, context: Context) {
        context.coordinator.parent = self

        // Only rewrite the buffer when it genuinely differs. Assigning the same
        // string resets the caret to the end, which turns editing mid-sentence
        // into a fight.
        if view.text != text {
            let selection = view.selectedRange
            context.coordinator.apply(text: text, to: view, kind: kind, linkColor: linkColor, textColor: textColor)
            view.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
        } else {
            context.coordinator.restyle(view, kind: kind, linkColor: linkColor, textColor: textColor)
        }

        view.placeholderLabel.text = placeholder
        view.placeholderLabel.isHidden = !text.isEmpty
        view.placeholderLabel.font = BlockStyle.font(kind)

        // Focus is driven by the editor's model, never by UIKit's own idea of
        // who is first responder, so that inserting a block can put the caret
        // in it without a round trip through the view layer.
        if isFocused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView

        init(_ parent: BlockTextView) { self.parent = parent }

        func apply(text: String, to view: BlockUITextView, kind: NoteBlockKind, linkColor: UIColor, textColor: UIColor) {
            view.attributedText = Coordinator.attributed(
                text, kind: kind, linkColor: linkColor, textColor: textColor
            )
        }

        func restyle(_ view: BlockUITextView, kind: NoteBlockKind, linkColor: UIColor, textColor: UIColor) {
            guard view.appliedKind != kind || view.appliedTextColor != textColor else { return }
            let selection = view.selectedRange
            view.attributedText = Coordinator.attributed(
                view.text, kind: kind, linkColor: linkColor, textColor: textColor
            )
            view.selectedRange = selection
            view.appliedKind = kind
            view.appliedTextColor = textColor
        }

        /// Body text plus the one piece of live syntax highlighting this editor
        /// does: `[[a link]]` in the accent colour, brackets included, so it is
        /// obvious the link is closed.
        static func attributed(
            _ text: String, kind: NoteBlockKind, linkColor: UIColor, textColor: UIColor
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = BlockStyle.lineSpacing(kind)

            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: BlockStyle.font(kind),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph,
                ]
            )

            let nsText = text as NSString
            for range in NoteLinkScanner.ranges(in: text) {
                let nsRange = NSRange(range, in: text)
                guard nsRange.location + nsRange.length <= nsText.length else { continue }
                attributed.addAttribute(.foregroundColor, value: linkColor, range: nsRange)
            }
            return attributed
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement == "\n" {
                let full = textView.text as NSString
                let before = full.substring(to: range.location)
                let after = full.substring(from: min(range.location + range.length, full.length))
                parent.onReturn(before, after)
                return false
            }
            if replacement == "\t" {
                parent.onIndent(1)
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let updated = textView.text ?? ""

            // A typed markdown prefix wins over everything else: it rewrites
            // the block, so there is no point evaluating the menus against text
            // that is about to be replaced.
            if let (kind, remainder) = NoteBlockParser.shortcut(in: updated),
               parent.kind == .paragraph || (parent.kind != kind && parent.kind.isTextual) {
                parent.onSlashQuery(nil)
                parent.onLinkQuery(nil)
                parent.onTransform(kind, remainder)
                return
            }

            parent.text = updated
            textView.invalidateIntrinsicContentSize()

            parent.onSlashQuery(NoteBlockEditor.slashQuery(in: updated))
            parent.onLinkQuery(NoteBlockEditor.linkQuery(in: updated, caret: textView.selectedRange.location))
        }

    }
}

/// The one behaviour a plain `UITextView` will not give up: what Backspace does
/// at offset zero.
///
/// `textView(_:shouldChangeTextIn:)` is not called at all when there is nothing
/// to delete, so an empty block would swallow the keystroke and the block above
/// would be unreachable. Overriding `deleteBackward` is the only place the
/// event is guaranteed to arrive.
final class BlockUITextView: UITextView {
    var onDeleteBackwardAtStart: (() -> Bool)?
    var onShiftTab: (() -> Void)?
    var appliedKind: NoteBlockKind?
    var appliedTextColor: UIColor?

    let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func deleteBackward() {
        if selectedRange.location == 0, selectedRange.length == 0,
           onDeleteBackwardAtStart?() == true {
            return
        }
        super.deleteBackward()
        placeholderLabel.isHidden = !(text ?? "").isEmpty
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdent))]
    }

    @objc private func outdent() { onShiftTab?() }
}
