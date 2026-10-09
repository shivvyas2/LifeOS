import SwiftUI

/// A project's colour, kept small: the dot beside its name, its progress
/// fill and the contribution squares.
public enum ProjectColour: String, CaseIterable, Codable, Sendable {
    case tomato, marigold, moss, lagoon, iris, rose

    public init(named name: String) { self = ProjectColour(rawValue: name) ?? .tomato }

    private var rgb: (Double, Double, Double) {
        switch self {
        case .tomato: (0.93, 0.33, 0.20)
        case .marigold: (0.95, 0.67, 0.12)
        case .moss: (0.36, 0.60, 0.28)
        case .lagoon: (0.12, 0.55, 0.70)
        case .iris: (0.42, 0.36, 0.86)
        case .rose: (0.88, 0.33, 0.55)
        }
    }

    /// Full strength: header bands, progress fill, badges.
    public var fill: AdaptiveColor {
        let (r, g, b) = rgb
        return AdaptiveColor(light: Color(red: r, green: g, blue: b),
                             dark: Color(red: min(r + 0.05, 1), green: min(g + 0.05, 1), blue: min(b + 0.05, 1)))
    }

    /// Five steps for the contribution grid: level 0 is the shared empty
    /// square, 1 to 4 deepen toward the full colour.
    public func ramp(level: Int) -> AdaptiveColor {
        let clamped = min(max(level, 0), 4)
        guard clamped > 0 else {
            return AdaptiveColor(light: Color(white: 0.90), dark: Color(white: 0.20))
        }
        let (r, g, b) = rgb
        let strength = [0, 0.30, 0.52, 0.76, 1.0][clamped]
        func mix(_ c: Double, toward base: Double) -> Double { base + (c - base) * strength }
        return AdaptiveColor(
            light: Color(red: mix(r, toward: 0.97), green: mix(g, toward: 0.97), blue: mix(b, toward: 0.97)),
            dark: Color(red: mix(r, toward: 0.16), green: mix(g, toward: 0.16), blue: mix(b, toward: 0.16))
        )
    }
}
