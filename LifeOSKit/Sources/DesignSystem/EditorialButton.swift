import SwiftUI

/// The app's buttons, in the editorial style: capsules of ink and paper, a
/// hairline outline for the alternative, plain text with an arrow for a way
/// onward.
///
/// One style with five roles rather than a look per screen. The app had
/// grown system bordered buttons, glass, an orange rounded rectangle and
/// ninety-odd hand-drawn labels, so the same action looked different on
/// every tab. A role says what the button is for; the style decides what
/// that looks like, once.
public enum EditorialButtonRole: Sendable {
    /// The one thing the screen is for. Ink capsule, paper text. One per
    /// screen: two primaries are two answers to "what now?".
    case primary
    /// The alternative to the primary. A hairline ink outline.
    case secondary
    /// A way onward that is not a decision: "View more", "Details". Text, a
    /// trailing arrow, a rule underneath, the way the references set it.
    case quiet
    /// The action on something live or urgent: an activity in progress, a
    /// payment due. The accent fill, which nothing else in the app uses at
    /// this size, so it is unmistakable and used sparingly.
    case live
    /// Removes or throws something away. Alert ink on an outline; never
    /// filled, so it is never the most inviting thing on screen.
    case destructive
}

public enum EditorialButtonSize: Sendable {
    /// 52pt tall. The default for a screen's actions.
    case regular
    /// 36pt tall. For a button inside a row, a card header or a toolbar.
    case compact
}

public struct EditorialButtonStyle: ButtonStyle {
    let role: EditorialButtonRole
    let size: EditorialButtonSize
    let fullWidth: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ role: EditorialButtonRole = .primary, size: EditorialButtonSize = .regular, fullWidth: Bool = false) {
        self.role = role; self.size = size; self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return label(configuration)
            .font(size == .regular ? LifeOSType.rowTitle : LifeOSType.label.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, role == .quiet ? 0 : (size == .regular ? Space.x3 : 14))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size == .regular ? 52 : 36)
            .foregroundStyle(foreground)
            .background { background(pressed: pressed) }
            .overlay { outline }
            .overlay(alignment: .bottom) { if role == .quiet { Hairline() } }
            .contentShape(role == .quiet ? AnyShape(.rect) : AnyShape(.capsule))
            .opacity(isEnabled ? (pressed && role == .quiet ? 0.55 : 1) : 0.38)
            .scaleEffect(pressed && !reduceMotion && role != .quiet ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: pressed)
    }

    /// A quiet button always ends in an arrow: it is the sign that the text
    /// goes somewhere, which is otherwise the one thing plain text cannot say.
    @ViewBuilder private func label(_ configuration: Configuration) -> some View {
        if role == .quiet {
            HStack(spacing: Space.x1) {
                configuration.label
                Spacer(minLength: Space.x1)
                Image(systemName: "arrow.right").font(LifeOSType.label.weight(.semibold))
                    .accessibilityHidden(true)
            }
        } else {
            configuration.label
        }
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    private var foreground: Color {
        switch role {
        case .primary: LifeOSTokens.canvas.resolve(scheme)
        case .secondary, .quiet: ink
        case .live: .white
        case .destructive: LifeOSTokens.alertText.resolve(scheme)
        }
    }

    @ViewBuilder private func background(pressed: Bool) -> some View {
        switch role {
        case .primary: Capsule().fill(ink.opacity(pressed ? 0.82 : 1))
        case .live: Capsule().fill(LifeOSTokens.accent.opacity(pressed ? 0.85 : 1))
        case .secondary, .destructive: Capsule().fill(ink.opacity(pressed ? 0.06 : 0))
        case .quiet: EmptyView()
        }
    }

    @ViewBuilder private var outline: some View {
        switch role {
        case .secondary: Capsule().strokeBorder(ink.opacity(0.85), lineWidth: 1)
        case .destructive: Capsule().strokeBorder(LifeOSTokens.alertText.resolve(scheme).opacity(0.7), lineWidth: 1)
        default: EmptyView()
        }
    }
}

extension ButtonStyle where Self == EditorialButtonStyle {
    /// `.buttonStyle(.editorial(.secondary, size: .compact))`
    public static func editorial(_ role: EditorialButtonRole = .primary, size: EditorialButtonSize = .regular,
                                 fullWidth: Bool = false) -> EditorialButtonStyle {
        EditorialButtonStyle(role, size: size, fullWidth: fullWidth)
    }
}
