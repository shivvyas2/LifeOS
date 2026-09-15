import Testing
import CoreGraphics
@testable import AppSurfaces

/// Where a dragged HUD comes to rest. The maths is pure so that a corner
/// case, a HUD wider than its player or a drop onto the control bar, is a
/// test rather than a thumb on a device.
@Suite struct HUDPlacementTests {
    let hud = CGSize(width: 200, height: 100)
    let container = CGSize(width: 400, height: 300)

    @Test func theDefaultAnchorIsTheTopLeadingCornerInsideTheInset() {
        let origin = HUDPlacement.origin(for: .topLeading, hud: hud, container: container, inset: 16)
        #expect(origin == CGPoint(x: 16, y: 16))
    }

    @Test func anAnchorOfOneIsTheBottomTrailingCornerInsideTheInset() {
        let origin = HUDPlacement.origin(for: .init(x: 1, y: 1), hud: hud, container: container, inset: 16)
        #expect(origin == CGPoint(x: 184, y: 184))
    }

    @Test func anOriginRoundTripsThroughItsAnchor() {
        let origin = CGPoint(x: 100, y: 58)
        let anchor = HUDPlacement.anchor(for: origin, hud: hud, container: container, inset: 16)
        let back = HUDPlacement.origin(for: anchor, hud: hud, container: container, inset: 16)
        #expect(abs(back.x - origin.x) < 0.001)
        #expect(abs(back.y - origin.y) < 0.001)
    }

    @Test func aDropOutsideTheContainerIsPulledBackInside() {
        let settled = HUDPlacement.settle(origin: CGPoint(x: -80, y: 900), hud: hud,
                                          container: container, inset: 16, avoiding: nil)
        #expect(settled == CGPoint(x: 16, y: 184))
    }

    @Test func aHUDWiderThanItsContainerSitsAtTheInset() {
        let wide = CGSize(width: 500, height: 100)
        let origin = HUDPlacement.origin(for: .init(x: 1, y: 0), hud: wide, container: container, inset: 16)
        #expect(origin.x == 16)
        let anchor = HUDPlacement.anchor(for: origin, hud: wide, container: container, inset: 16)
        #expect(anchor.x == 0)
    }

    /// The bottom strip is YouTube's control bar and branding, which the
    /// layout notes keep the rings off. A drop onto it is moved off it,
    /// to whichever side is nearer.
    @Test func aDropOntoTheControlStripIsMovedToTheNearerSide() {
        let strip = CGRect(x: 0, y: 200, width: 400, height: 56)
        // Slightly over the top edge of the strip: nearer to sit above it.
        let above = HUDPlacement.settle(origin: CGPoint(x: 50, y: 120), hud: hud,
                                        container: CGSize(width: 400, height: 420), inset: 16, avoiding: strip)
        #expect(above == CGPoint(x: 50, y: 100))
        // Mostly past the strip: nearer to sit below it.
        let below = HUDPlacement.settle(origin: CGPoint(x: 50, y: 230), hud: hud,
                                        container: CGSize(width: 400, height: 420), inset: 16, avoiding: strip)
        #expect(below == CGPoint(x: 50, y: 256))
    }

    @Test func whenOnlyOneSideOfTheStripFitsThatSideWins() {
        // Container ends at the strip's bottom, so below never fits.
        let strip = CGRect(x: 0, y: 244, width: 400, height: 56)
        let settled = HUDPlacement.settle(origin: CGPoint(x: 50, y: 230), hud: hud,
                                          container: container, inset: 16, avoiding: strip)
        #expect(settled == CGPoint(x: 50, y: 144))
    }

    @Test func aDropClearOfTheStripIsLeftWhereItLanded() {
        let strip = CGRect(x: 0, y: 244, width: 400, height: 56)
        let settled = HUDPlacement.settle(origin: CGPoint(x: 50, y: 40), hud: hud,
                                          container: container, inset: 16, avoiding: strip)
        #expect(settled == CGPoint(x: 50, y: 40))
    }

    @Test func anAnchorSurvivesDefaultsAsText() {
        let anchor = HUDPlacement.Anchor(x: 0.25, y: 0.75)
        #expect(HUDPlacement.Anchor(stored: anchor.stored) == anchor)
        #expect(HUDPlacement.Anchor(stored: "") == nil)
        #expect(HUDPlacement.Anchor(stored: "nope") == nil)
        // A stored value from a bigger screen still lands inside the range.
        #expect(HUDPlacement.Anchor(stored: "1.7,-2") == HUDPlacement.Anchor(x: 1, y: 0))
    }
}
