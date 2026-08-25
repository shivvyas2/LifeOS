import SwiftUI

/// A module's identity colour. Each screen owns exactly one.
/// Nutrition, money and habits are declared now but unused until later slices.
/// Declaring them proves the gradient primitive generalises.
public enum ModuleHue: String, CaseIterable, Sendable {
    case body, activity, recovery, nutrition, money, habits

    /// Saturated colour at the top of the canvas.
    public var top: Color {
        switch self {
        case .body:      Color(red: 0.06, green: 0.55, blue: 0.53)
        case .activity:  Color(red: 0.92, green: 0.68, blue: 0.16)
        case .recovery:  Color(red: 0.23, green: 0.51, blue: 0.93)
        case .nutrition: Color(red: 0.49, green: 0.36, blue: 0.92)
        case .money:     Color(red: 0.18, green: 0.62, blue: 0.36)
        case .habits:    Color(red: 0.94, green: 0.42, blue: 0.20)
        }
    }

    /// Near-white bottom of the canvas in light mode.
    public var bottom: Color { Color(white: 0.98) }

    /// Deep top / near-black bottom for dark mode. Defined now because
    /// retrofitting a gradient system to dark mode later is miserable.
    public var darkTop: Color {
        switch self {
        case .body:      Color(red: 0.02, green: 0.22, blue: 0.21)
        case .activity:  Color(red: 0.35, green: 0.25, blue: 0.04)
        case .recovery:  Color(red: 0.07, green: 0.17, blue: 0.35)
        case .nutrition: Color(red: 0.18, green: 0.13, blue: 0.36)
        case .money:     Color(red: 0.05, green: 0.23, blue: 0.13)
        case .habits:    Color(red: 0.36, green: 0.15, blue: 0.06)
        }
    }

    public var darkBottom: Color { Color(white: 0.06) }

    /// Soft tint of the hue for icon bubbles, chart fills and canvas washes.
    /// The saturated `top` colours survive only as chart/accent ink; pastel
    /// carries the module identity on the light canvas.
    public var pastel: Color {
        switch self {
        case .body:      Color(red: 0.84, green: 0.92, blue: 0.90)
        case .activity:  Color(red: 0.98, green: 0.89, blue: 0.78)
        case .recovery:  Color(red: 0.85, green: 0.90, blue: 0.98)
        case .nutrition: Color(red: 0.90, green: 0.87, blue: 0.98)
        case .money:     Color(red: 0.85, green: 0.93, blue: 0.87)
        case .habits:    Color(red: 0.99, green: 0.88, blue: 0.82)
        }
    }

    /// Deep muted counterpart for dark mode bubbles and washes.
    public var pastelDark: Color {
        switch self {
        case .body:      Color(red: 0.10, green: 0.18, blue: 0.17)
        case .activity:  Color(red: 0.24, green: 0.18, blue: 0.09)
        case .recovery:  Color(red: 0.10, green: 0.15, blue: 0.26)
        case .nutrition: Color(red: 0.16, green: 0.13, blue: 0.27)
        case .money:     Color(red: 0.09, green: 0.18, blue: 0.12)
        case .habits:    Color(red: 0.26, green: 0.14, blue: 0.09)
        }
    }
}

/// A light/dark colour pair, resolved explicitly by the consuming view.
///
/// UIKit's dynamic colours (`Color(.systemGroupedBackground)`) would be simpler
/// but are iOS-only, and this package also builds for macOS so that tests run
/// from the terminal without a simulator. Explicit resolution is the price of
/// keeping `swift test` fast.
public struct AdaptiveColor: Sendable {
    public let light: Color
    public let dark: Color

    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    public func resolve(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}

public enum LifeOSTokens {
    /// The single accent. Means "today" and "act". Never varies by module,
    /// and is identical in both schemes so it reads the same everywhere.
    public static let accent = Color(red: 0.94, green: 0.34, blue: 0.18)

    /// Warm off-white canvas for the neutral hub.
    public static let canvas = AdaptiveColor(
        light: Color(red: 0.949, green: 0.945, blue: 0.933),
        dark: Color(white: 0.07)
    )

    public static let cardSurface = AdaptiveColor(
        light: .white,
        dark: Color(white: 0.13)
    )

    public static let primaryText = AdaptiveColor(
        light: Color(white: 0.08),
        dark: Color(white: 0.95)
    )

    public static let secondaryText = AdaptiveColor(
        light: Color(white: 0.45),
        dark: Color(white: 0.62)
    )

    /// Dot grid fills for days that were logged but missed, and days not yet reached.
    public static let dotMissed = AdaptiveColor(light: Color(white: 0.86), dark: Color(white: 0.28))
    public static let dotFuture = AdaptiveColor(light: Color(white: 0.93), dark: Color(white: 0.18))
    public static let dotOutline = AdaptiveColor(light: Color(white: 0.85), dark: Color(white: 0.30))

    /// Tile surface for cards sitting on a saturated gradient.
    ///
    /// Light and opaque enough to carry dark text: white-on-translucent over a
    /// mid-saturation hue is the low-contrast failure the reference designs
    /// avoid by keeping the tile light and the text dark.
    public static let tileSurface = AdaptiveColor(
        light: Color.white.opacity(0.58),
        dark: Color.white.opacity(0.14)
    )

    /// Text sitting directly on a gradient, where the backdrop is saturated in
    /// light mode and near-black in dark mode, and white reads in both.
    public static let onGradient = Color.white

    /// Leading and trailing cells that belong to no day. Faint rather than
    /// invisible so the month reads as one solid block of dots. The grid is
    /// the app's central visual claim and a ragged edge weakens it.
    public static let dotPadding = AdaptiveColor(light: Color(white: 0.965), dark: Color(white: 0.11))

    /// Soft companion to `accent`: the track behind a filled bar, the wash
    /// behind an accent icon.
    public static let accentSoft = AdaptiveColor(
        light: Color(red: 0.99, green: 0.88, blue: 0.82),
        dark: Color(red: 0.33, green: 0.16, blue: 0.10)
    )

    /// Anomaly banner surfaces. Red enough to interrupt, soft enough to live
    /// on the cream canvas.
    public static let alertBackground = AdaptiveColor(
        light: Color(red: 1.00, green: 0.92, blue: 0.92),
        dark: Color(red: 0.28, green: 0.09, blue: 0.09)
    )
    public static let alertText = AdaptiveColor(
        light: Color(red: 0.78, green: 0.16, blue: 0.16),
        dark: Color(red: 1.00, green: 0.58, blue: 0.55)
    )

    /// The one card shadow. Light mode only; dark mode separates surfaces by
    /// tone, and a black shadow on a black canvas is invisible cost.
    public static let cardShadow = Color.black.opacity(0.06)
}
