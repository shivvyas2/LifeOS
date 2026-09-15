import Foundation
import CoreGraphics

/// Where a HUD the person can drag comes to rest, and how that is remembered.
///
/// A position is kept as an `Anchor`, a fraction of the free travel in each
/// axis, rather than as a point. The same anchor puts the rings in the same
/// relative place over a small player in portrait, a letterboxed one in full
/// screen and the whole screen in landscape, and it stays meaningful when the
/// HUD changes size, as it does when it collapses to the bar.
///
/// Pure, so that the corner cases, a HUD wider than its player or a drop onto
/// YouTube's control bar, are tests rather than thumbs on a device.
public enum HUDPlacement {

    /// (0, 0) is the top leading corner inside the inset; (1, 1) the bottom
    /// trailing one.
    public struct Anchor: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = min(max(x, 0), 1)
            self.y = min(max(y, 0), 1)
        }

        public static let topLeading = Anchor(x: 0, y: 0)

        /// The defaults representation: two numbers and a comma.
        public var stored: String { "\(x),\(y)" }

        public init?(stored: String) {
            let parts = stored.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            self.init(x: x, y: y)
        }
    }

    /// The HUD's top leading corner for an anchor, in the container's
    /// coordinates. A HUD with no room to travel sits at the inset.
    public static func origin(for anchor: Anchor, hud: CGSize, container: CGSize, inset: CGFloat) -> CGPoint {
        CGPoint(x: inset + travel(container.width, hud.width, inset) * anchor.x,
                y: inset + travel(container.height, hud.height, inset) * anchor.y)
    }

    /// The anchor an origin corresponds to, clamped into range.
    public static func anchor(for origin: CGPoint, hud: CGSize, container: CGSize, inset: CGFloat) -> Anchor {
        let width = travel(container.width, hud.width, inset)
        let height = travel(container.height, hud.height, inset)
        return Anchor(x: width > 0 ? (origin.x - inset) / width : 0,
                      y: height > 0 ? (origin.y - inset) / height : 0)
    }

    /// Where a dropped HUD settles: inside the container, and off the strip
    /// it is not allowed to cover, on whichever side of it is nearer and fits.
    ///
    /// The strip is YouTube's control bar and branding along the bottom of
    /// the player, which the layout notes keep the rings clear of. The HUD
    /// follows the finger freely while dragging; the rule is applied once, on
    /// release, so it reads as a snap rather than a wall.
    public static func settle(origin: CGPoint, hud: CGSize, container: CGSize, inset: CGFloat,
                              avoiding strip: CGRect?) -> CGPoint {
        let minY = inset
        let maxY = max(inset, container.height - inset - hud.height)
        var settled = CGPoint(
            x: min(max(origin.x, inset), max(inset, container.width - inset - hud.width)),
            y: min(max(origin.y, minY), maxY)
        )
        guard let strip else { return settled }
        let rect = CGRect(origin: settled, size: hud)
        guard rect.intersects(strip) else { return settled }

        let above = strip.minY - hud.height
        let below = strip.maxY
        let aboveFits = above >= minY
        let belowFits = below <= maxY
        switch (aboveFits, belowFits) {
        case (true, true):
            settled.y = abs(settled.y - above) <= abs(settled.y - below) ? above : below
        case (true, false):
            settled.y = above
        case (false, true):
            settled.y = below
        case (false, false):
            break
        }
        return settled
    }

    private static func travel(_ container: CGFloat, _ hud: CGFloat, _ inset: CGFloat) -> CGFloat {
        max(0, container - hud - inset * 2)
    }
}
