import SwiftUI

/// A project's colour: the one place colour appears on the Projects tab
/// (card header band, contribution squares, progress, column badges).
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

/// The Projects tab's card: square corners, a 2pt ink border and an ink
/// shadow offset down and right; an optional colour band across the top.
public struct BrutalCard: ViewModifier {
    let header: Color?
    let padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(header: Color?, padding: CGFloat) {
        self.header = header
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        VStack(spacing: 0) {
            if let header {
                Rectangle().fill(header).frame(height: 10)
                Rectangle().fill(ink).frame(height: 2)
            }
            content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LifeOSTokens.cardSurface.resolve(scheme))
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
        .background(Rectangle().fill(ink).offset(x: 4, y: 4))
        .padding(.trailing, 4).padding(.bottom, 4)
    }
}

public extension View {
    /// `.brutalCard()`, or `.brutalCard(header: colour)` for a project's card.
    func brutalCard(header: Color? = nil, padding: CGFloat = Space.x2) -> some View {
        modifier(BrutalCard(header: header, padding: padding))
    }

    /// The tab's uppercase label: the label step, heavy, tracked.
    func brutalLabel() -> some View {
        self.font(LifeOSType.label.weight(.heavy)).tracking(1.2).textCase(.uppercase)
    }
}
