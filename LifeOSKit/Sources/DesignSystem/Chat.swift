import SwiftUI

/// The pieces a conversation on paper is made of, shared by LIFO and the
/// calendar assistant so the two screens cannot drift apart.

/// The person's question: ink inside a hairline-outlined block, aligned
/// trailing. A transcript entry, not the loudest thing on the screen.
public struct ChatQuestion: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(LifeOSType.secondary)
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Editorial.rule(scheme)))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// One exchange: the question over the reply. A nil or empty question draws
/// no block, which is how a nudge LIFO opened with reads.
public struct ChatTurn<Reply: View>: View {
    let question: String?
    let reply: Reply
    public init(question: String?, @ViewBuilder reply: () -> Reply) {
        self.question = question; self.reply = reply()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let question, !question.isEmpty { ChatQuestion(question) }
            reply
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line that holds the place of a reply still being written.
public struct ChatThinking: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Text("Thinking…")
            .font(LifeOSType.secondary)
            .foregroundStyle(Editorial.quietInk(scheme))
            .accessibilityLabel("Thinking")
    }
}

/// The composer: a hairline-outlined bar with the field and an ink send
/// circle, and room for one accessory beside it (LIFO's voice toggle).
public struct ChatComposer<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    let isSending: Bool
    let focus: FocusState<Bool>.Binding?
    let onSend: () -> Void
    let accessory: Accessory
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String, isSending: Bool,
                focus: FocusState<Bool>.Binding? = nil,
                onSend: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory) {
        _text = text; self.placeholder = placeholder; self.isSending = isSending
        self.focus = focus; self.onSend = onSend; self.accessory = accessory()
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        let paper = LifeOSTokens.canvas.resolve(scheme)
        HStack(alignment: .bottom, spacing: Space.x1) {
            HStack(alignment: .bottom, spacing: Space.x1) {
                field
                    .font(LifeOSType.secondary)
                    .foregroundStyle(ink)
                    .lineLimit(1...4)
                    .padding(.vertical, 10)
                    .onSubmit { if canSend { onSend() } }
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(paper)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ink))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.38)
                .accessibilityLabel("Send")
                .padding(.bottom, Space.half)
            }
            .padding(.leading, Space.x2)
            .padding(.trailing, Space.half)
            .padding(.vertical, Space.half)
            .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(Editorial.rule(scheme)))
            accessory
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(placeholder, text: $text, axis: .vertical).focused(focus)
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
        }
    }
}

extension ChatComposer where Accessory == EmptyView {
    public init(text: Binding<String>, placeholder: String, isSending: Bool,
                focus: FocusState<Bool>.Binding? = nil, onSend: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, isSending: isSending,
                  focus: focus, onSend: onSend) { EmptyView() }
    }
}

/// A write the assistant wants to make, awaiting a yes or a no.
public struct ChatConfirmation: View {
    let lines: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(lines: [String], onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.lines = lines; self.onConfirm = onConfirm; self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: Space.half) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.x1) {
                Button("Confirm", action: onConfirm).buttonStyle(.editorial(.primary, size: .compact))
                Button("Cancel", action: onCancel).buttonStyle(.editorial(.secondary, size: .compact))
            }
        }
        .editorialCard()
    }
}

/// What a reply did, as tags: `Checked your calendar`, `Created an event`.
public struct ChatToolTags: View {
    let summaries: [String]
    public init(_ summaries: [String]) { self.summaries = summaries }
    public var body: some View {
        WrapLayout(spacing: Space.x1) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                EditorialTag(summary)
            }
        }
    }
}

/// Lays subviews out in rows, wrapping when the width runs out. For tags
/// and pills, which should read as words in a sentence, not as a grid.
public struct WrapLayout: Layout {
    let spacing: CGFloat
    public init(spacing: CGFloat = Space.x1) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
