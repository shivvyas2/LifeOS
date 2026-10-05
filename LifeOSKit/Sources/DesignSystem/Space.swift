import SwiftUI

/// The 8-point grid. Every margin, gap and inset in the app comes from here.
///
/// Named by multiples rather than by role (`small`/`medium`) because roles
/// drift (someone always needs a "medium-large") while multiples cannot.
public enum Space {
    /// 4pt. The only sub-grid value, for optical adjustments inside a control.
    public static let half: CGFloat = 4
    public static let x1: CGFloat = 8
    public static let x2: CGFloat = 16
    public static let x3: CGFloat = 24
    public static let x4: CGFloat = 32
    public static let x5: CGFloat = 40
    public static let x6: CGFloat = 48
    public static let x8: CGFloat = 64
    public static let x10: CGFloat = 80
}

/// Corner radii, also on the grid so cards nest without optical drift.
public enum Radius {
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 20
    public static let large: CGFloat = 28
    public static let pill: CGFloat = 999
}

/// A frosted panel for content sitting over a gradient.
///
/// One material layer and a hairline edge. The edge matters: without it the
/// panel dissolves into a light gradient and stops reading as a surface.
public struct GlassPanel<Content: View>: View {
    private let content: Content
    private let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(radius: CGFloat = Radius.large, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        // Liquid Glass, not a material imitation of it: the system renders
        // real refraction and highlights, and every panel in the app gets it
        // from this one place.
        content
            .padding(Space.x3)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The app's primary action. Solid, full width, one per screen. Drawn by
/// `EditorialButtonStyle` so it matches every other primary in the app.
public struct PrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(LifeOSTokens.canvas.resolve(scheme)) }
            }
        }
        .buttonStyle(.editorial(.primary, fullWidth: true))
        .disabled(isLoading)
    }
}

/// Quieter companion to `PrimaryButton`, for the way out of a step.
public struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action).buttonStyle(.editorial(.secondary, fullWidth: true))
    }
}
