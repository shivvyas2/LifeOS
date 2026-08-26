import SwiftUI

// MARK: - Inline status

public enum StatusSeverity: Equatable, Sendable {
    case error
    case warning
}

/// The one thing the screen is complaining about.
///
/// A screen that shows a validation error, a channel note and a configuration
/// warning at the same time has told the user three things and helped with
/// none. `resolve` picks the single most actionable one.
public struct InlineStatus: Equatable, Sendable {
    public let message: String
    public let severity: StatusSeverity

    public init(message: String, severity: StatusSeverity) {
        self.message = message
        self.severity = severity
    }

    /// Precedence: what the user just did, then what is broken for everyone,
    /// then what is merely unavailable on this channel.
    public static func resolve(
        error: String?,
        configuration: String?,
        warning: String?
    ) -> InlineStatus? {
        if let error = present(error) { return InlineStatus(message: error, severity: .error) }
        if let configuration = present(configuration) {
            return InlineStatus(message: configuration, severity: .error)
        }
        if let warning = present(warning) { return InlineStatus(message: warning, severity: .warning) }
        return nil
    }

    /// Whitespace is absence. A `""` error would otherwise paint a red gap.
    private static func present(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// One line of complaint under a field, with an icon that says which kind.
public struct InlineStatusView: View {
    private let status: InlineStatus
    @Environment(\.colorScheme) private var scheme

    public init(_ status: InlineStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.half + 2) {
            Image(systemName: status.severity == .error
                  ? "exclamationmark.circle.fill"
                  : "info.circle.fill")
                .font(LifeOSType.caption.weight(.semibold))
            Text(status.message)
                .font(LifeOSType.label.weight(.regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch status.severity {
        case .error:   Color(red: 0.86, green: 0.22, blue: 0.18)
        case .warning: LifeOSTokens.secondaryText.resolve(scheme)
        }
    }
}

// MARK: - Segmented pills

/// A two-or-more way switch in the app's own vocabulary.
///
/// Replaces `.pickerStyle(.segmented)` on the sign-in screen, which was the one
/// piece of stock iOS chrome left in an app that draws everything else itself.
public struct SegmentedPills<Value: Hashable>: View {
    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value
    @Environment(\.colorScheme) private var scheme
    @Namespace private var slider

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(LifeOSType.rowTitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: Space.x5)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(LifeOSTokens.canvas.resolve(scheme))
                                    // One shared id means the selected capsule
                                    // slides between options instead of
                                    // cross-fading in place.
                                    .matchedGeometryEffect(id: "selected", in: slider)
                            }
                        }
                        .foregroundStyle(isSelected
                                         ? LifeOSTokens.primaryText.resolve(scheme)
                                         : LifeOSTokens.secondaryText.resolve(scheme))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme)))
    }
}

// MARK: - Code field

/// What each box in a code field shows.
///
/// A free function rather than a static on `CodeField`, because a test that
/// touches a SwiftUI `View` type forces its metadata, and the test binary runs
/// on an older platform than the package targets. Keeping the logic off the
/// view is also the same split used everywhere else here: the decidable part
/// stays where a test can reach it without a screen.
public enum CodeDigits {

    /// Non-digits are dropped rather than displayed, because autofill and paste
    /// both deliver spaces and dashes.
    public static func digits(from text: String, count: Int) -> [Character?] {
        guard count > 0 else { return [] }
        let numbers = Array(text.filter { $0.isNumber }.prefix(count))
        return (0..<count).map { index in
            index < numbers.count ? numbers[index] : nil
        }
    }
}

/// Six boxes for a one-time code.
///
/// One real text field, hidden behind the boxes, so the system keyboard,
/// `.oneTimeCode` autofill and paste all keep working. The boxes are a
/// rendering of that field's text and hold no state of their own, which is what
/// stops them drifting out of step with it.
public struct CodeField: View {
    private let count: Int
    @Binding private var text: String
    private let onComplete: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, count: Int = 6, onComplete: @escaping () -> Void = {}) {
        self._text = text
        self.count = count
        self.onComplete = onComplete
    }

    public var body: some View {
        let digits = CodeDigits.digits(from: text, count: count)
        let filled = digits.compactMap { $0 }.count

        ZStack {
            // The real field: focusable and typable, but invisible. Opacity
            // rather than `.hidden()`, which would take it out of the hierarchy
            // and with it the keyboard.
            TextField("", text: $text)
                .oneTimeCodeEntry()
                .focused($focused)
                .opacity(0.001)
                .onChange(of: text) { _, newValue in
                    let numbers = newValue.filter { $0.isNumber }
                    // Trim here rather than in the view model: a paste of ten
                    // digits must not leave four invisible characters that the
                    // boxes never showed but the request would send.
                    if numbers != newValue || numbers.count > count {
                        text = String(numbers.prefix(count))
                    }
                    if text.count == count { onComplete() }
                }

            HStack(spacing: Space.x1) {
                ForEach(0..<count, id: \.self) { index in
                    box(digit: digits[index], isNext: index == filled)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .accessibilityElement()
        .accessibilityLabel("Verification code")
        .accessibilityValue(filled == 0 ? "empty" : "\(filled) of \(count) digits entered")
    }

    private func box(digit: Character?, isNext: Bool) -> some View {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(LifeOSTokens.cardSurface.resolve(scheme))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(
                        isNext && focused
                            ? LifeOSTokens.accent
                            : LifeOSTokens.dotOutline.resolve(scheme),
                        lineWidth: isNext && focused ? 2 : 1
                    )
            }
            .overlay {
                if let digit {
                    Text(String(digit))
                        .font(LifeOSType.numeral(24, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(height: Space.x8)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: digit)
    }
}

// MARK: - Field focus

/// The app's text-field look, with a focus ring.
///
/// The sign-in fields previously had no focus state at all: tapping between
/// them changed nothing on screen except the caret.
public struct FocusableField: ViewModifier {
    private let isFocused: Bool
    @Environment(\.colorScheme) private var scheme

    public init(isFocused: Bool) {
        self.isFocused = isFocused
    }

    public func body(content: Content) -> some View {
        content
            .font(LifeOSType.body)
            .padding(.horizontal, Space.x2)
            .frame(height: Space.x6 + Space.half)
            .background {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(
                                isFocused ? LifeOSTokens.accent : .clear,
                                lineWidth: 2
                            )
                    }
            }
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

public extension View {
    func focusableField(isFocused: Bool) -> some View {
        modifier(FocusableField(isFocused: isFocused))
    }

    /// A short horizontal shake, for a code that came back wrong.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(trigger)))
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Three cycles over the animation, decaying to zero so it settles
        // rather than stopping mid-swing.
        let travel = 7 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: travel, y: 0))
    }
}

/// Keyboard configuration for a one-time code.
///
/// Behind a platform check because this module builds for macOS as well as
/// iOS, and `keyboardType` / `textContentType` do not exist there. Without the
/// check the whole design system stops compiling for the test target.
private extension View {
    func oneTimeCodeEntry() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .writingToolsBehavior(.disabled)
        #else
        self
        #endif
    }
}
