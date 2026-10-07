import Foundation

/// Whether a drag across a to-do row is the tick gesture: at least 48pt to
/// the right, and more sideways than up or down, so a scroll that starts on
/// a to-do never ticks it. The same rule the calendar's day swipe uses to
/// tell a page turn from a scroll.
public enum TodoSwipe {
    public static let minimum: CGFloat = 48

    public static func ticks(dx: CGFloat, dy: CGFloat) -> Bool {
        dx >= minimum && abs(dx) > abs(dy)
    }
}
