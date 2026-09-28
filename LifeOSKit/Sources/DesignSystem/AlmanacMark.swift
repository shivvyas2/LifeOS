import SwiftUI

/// The Almanac logo, drawn from shapes so it scales to any size.
///
/// Three isometric leaves, plum under red under glass, with a dark orb and a
/// small crescent ring on the top leaf. It is the same geometry as
/// `docs/brand/almanac-mark.svg`; the numbers in `AlmanacMarkGeometry` are the
/// SVG's, in a 1024-unit box, so the two never drift.
///
/// Use `.tile` where the logo stands alone (About, onboarding), `.mark` over a
/// photo or a coloured surface, and `.mono` wherever the mark must follow the
/// surrounding `foregroundStyle`, such as a watermark or a watch complication.
public struct AlmanacMark: View {
    public enum Style: Sendable {
        /// The full-colour stack on the orange gradient squircle. This is the app icon.
        case tile
        /// The full-colour stack on a transparent background.
        case mark
        /// One colour, taken from the view's foreground style.
        case mono
    }

    public var style: Style

    public init(style: Style = .tile) {
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let g = AlmanacMarkGeometry(side: side, inTile: style == .tile)
            ZStack {
                if style == .tile {
                    tileBackground(side: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
                }
                stack(g)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Almanac")
    }

    private func tileBackground(side: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 1.00, green: 0.82, blue: 0.25), location: 0),
                    .init(color: Color(red: 1.00, green: 0.42, blue: 0.06), location: 0.35),
                    .init(color: Color(red: 0.91, green: 0.22, blue: 0.02), location: 0.7),
                    .init(color: Color(red: 0.69, green: 0.30, blue: 0.08), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 1.00, green: 0.89, blue: 0.35).opacity(0.9), .clear],
                center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: side * 0.7
            )
            RadialGradient(
                colors: [Color(red: 1.00, green: 0.60, blue: 0.23).opacity(0.55), .clear],
                center: UnitPoint(x: 0.85, y: 0.9), startRadius: 0, endRadius: side * 0.5
            )
        }
    }

    @ViewBuilder
    private func stack(_ g: AlmanacMarkGeometry) -> some View {
        let s = g.scale
        switch style {
        case .mono:
            ZStack {
                g.leaf(.bottom).fill(.foreground).opacity(0.35)
                g.leaf(.middle).fill(.foreground).opacity(0.6)
                g.leaf(.top).fill(.foreground)
                Circle().strokeBorder(AlmanacMarkGeometry.ring, lineWidth: 12 * s)
                    .frame(width: 92 * s, height: 92 * s).position(g.crescentCenter)
                Ellipse().fill(.foreground).frame(width: 244 * s, height: 132 * s).position(g.orbCenter)
                Ellipse().fill(AlmanacMarkGeometry.ring).frame(width: 196 * s, height: 96 * s).position(g.orbCenter)
                Ellipse().fill(.foreground).frame(width: 160 * s, height: 72 * s).position(g.orbCenter)
            }
        case .tile, .mark:
            ZStack {
                g.leaf(.bottom).fill(AlmanacMarkGeometry.plum)
                g.leaf(.bottom).stroke(Color(red: 0.54, green: 0.16, blue: 0.23), lineWidth: 6 * s)
                g.leaf(.middle).fill(
                    LinearGradient(colors: [Color(red: 0.89, green: 0.27, blue: 0.23), Color(red: 0.72, green: 0.09, blue: 0.11)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                g.leaf(.middle).stroke(Color(red: 0.95, green: 0.54, blue: 0.50), lineWidth: 6 * s)
                g.leaf(.top).fill(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                )
                g.leaf(.top).stroke(.white.opacity(0.75), lineWidth: 5 * s)
                Circle().strokeBorder(AlmanacMarkGeometry.ring, lineWidth: 12 * s)
                    .frame(width: 104 * s, height: 104 * s).position(g.crescentCenter)
                Ellipse().fill(AlmanacMarkGeometry.ring).frame(width: 244 * s, height: 132 * s).position(g.orbCenter)
                Ellipse().fill(Color(red: 0.72, green: 0.19, blue: 0.17)).frame(width: 220 * s, height: 110 * s).position(g.orbCenter)
                Ellipse().fill(
                    RadialGradient(colors: [Color(red: 0.54, green: 0.23, blue: 0.27), Color(red: 0.35, green: 0.06, blue: 0.13), Color(red: 0.25, green: 0.03, blue: 0.09)],
                                   center: UnitPoint(x: 0.32, y: 0.3), startRadius: 0, endRadius: 102 * s)
                ).frame(width: 204 * s, height: 98 * s).position(g.orbCenter)
                Ellipse().fill(Color(red: 0.54, green: 0.23, blue: 0.27).opacity(0.9))
                    .frame(width: 56 * s, height: 30 * s).position(g.highlightCenter)
            }
        }
    }
}

/// The mark's layout in points for a given side length. Mirrors `docs/brand/source/gen.js`.
public struct AlmanacMarkGeometry: Sendable, Equatable {
    public enum Leaf: CaseIterable, Sendable { case top, middle, bottom }

    static let plum = Color(red: 0.39, green: 0.03, blue: 0.13)
    static let ring = Color(red: 1.00, green: 0.94, blue: 0.85)

    /// Points per SVG unit.
    public let scale: CGFloat
    /// Vertical offset in SVG units. The transparent mark sits 62 units lower than the tile's stack so it centres in its box.
    public let yOffset: CGFloat

    public init(side: CGFloat, inTile: Bool) {
        scale = side / 1024
        yOffset = inTile ? 0 : 62
    }

    /// Leaf centres in SVG units, before the offset.
    static func leafY(_ leaf: Leaf) -> CGFloat {
        switch leaf { case .top: 350; case .middle: 452; case .bottom: 554 }
    }

    public func leafCenter(_ leaf: Leaf) -> CGPoint {
        CGPoint(x: 512 * scale, y: (Self.leafY(leaf) + yOffset) * scale)
    }

    /// A rounded square rotated 45 degrees and squashed to the isometric ratio.
    public func leaf(_ leaf: Leaf) -> Path {
        let c = leafCenter(leaf)
        let side = 600 * scale, radius = 165 * scale
        let square = Path(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side), cornerRadius: radius)
        let t = CGAffineTransform(translationX: c.x, y: c.y)
            .scaledBy(x: 1, y: 0.53)
            .rotated(by: .pi / 4)
        return square.applying(t)
    }

    public var orbCenter: CGPoint { CGPoint(x: 512 * scale, y: (350 + yOffset) * scale) }
    public var highlightCenter: CGPoint { CGPoint(x: 468 * scale, y: (334 + yOffset) * scale) }
    public var crescentCenter: CGPoint { CGPoint(x: 604 * scale, y: (298 + yOffset) * scale) }
}

#Preview("Styles") {
    HStack(spacing: 24) {
        AlmanacMark(style: .tile).frame(width: 120)
        AlmanacMark(style: .mark).frame(width: 120)
        AlmanacMark(style: .mono).frame(width: 120).foregroundStyle(.primary)
        AlmanacMark(style: .mono).frame(width: 40).foregroundStyle(.orange)
    }
    .padding()
}
