import SwiftUI

/// How wide the surface is, in the only two sizes the app distinguishes.
///
/// Deliberately not `UserInterfaceSizeClass`. That type is UIKit-only, and this
/// package builds for macOS so `swift test` runs from a terminal with no
/// simulator. Mapping the platform's size class onto this enum happens once, in
/// the app target, behind a `canImport` check.
public enum LayoutWidth: Sendable, Equatable {
    case compact
    case regular
}

/// The spacing and sizing decisions that vary with available width.
///
/// Every number lives here rather than in the views, for the same reason `Space`
/// exists: values scattered across screens drift, and the drift is invisible
/// until two screens sit side by side.
public struct LayoutMetrics: Sendable, Equatable {
    public let gutter: CGFloat
    public let sectionSpacing: CGFloat
    /// Caps single-column content so a 1366pt pane does not produce a sprawling
    /// measure. Grids are exempt and fill the pane.
    ///
    /// Set above a portrait iPad's 1024pt on purpose: portrait is already close
    /// to one comfortable column, and capping it again only bought dead margin
    /// down both sides. The cap is there for landscape and for wide Stage
    /// Manager panes.
    public let maxContentWidth: CGFloat
    public let heroScale: CGFloat
    public let fabBottomInset: CGFloat
    /// Bottom padding for a screen's scrolling content. In compact width it
    /// clears the floating pill bar, which overlaps the scroll view rather than
    /// insetting it. In regular width the bar is a side rail, so the content has
    /// nothing to clear and the old inset left a band of dead space.
    public let contentBottomInset: CGFloat
    /// Extra leading room for the side rail. Zero in compact width, where the
    /// bar lies along the bottom and `contentBottomInset` already pays for it.
    ///
    /// Only the rail is paid for. The coach and quick-log buttons keep the
    /// bottom corner and float over the content on every size, exactly as they
    /// do on a phone, so nothing is reserved for them on the trailing side.
    ///
    /// Stated as a number the screens apply rather than as a safe area inset,
    /// because a safe area does not survive the trip through a
    /// `NavigationStack` into a `ScrollView` whose background ignores it: the
    /// rail ended up drawn over the first column of the month.
    ///
    /// It has to cover the rail's real footprint, which is the gutter it is
    /// padded by plus its own width: 32 + 64. At 80 it was 16pt short, so
    /// every regular-width screen had its leading edge tucked under the rail,
    /// and the Notes sidebar, being a real column rather than a wide canvas,
    /// showed it plainly with its folder rows disappearing behind the pill.
    /// The extra beyond 96 is breathing room, and the rail's shadow needs it.
    public let railInset: CGFloat
    /// Columns for a grid of stat tiles, and for the denser rows of small
    /// metric tiles. Derived from the width class rather than measured, because
    /// a measured count needs a GeometryReader and `GridItem(.adaptive)` cannot
    /// cap the count at all: a 1366pt pane would take eight tiles across.
    public let statColumns: Int
    public let tileColumns: Int
    /// Which width class produced these metrics. Screens that rearrange rather
    /// than merely resize — a column that becomes two side by side — need to ask
    /// the question directly; no single number answers it for them.
    public let isRegular: Bool

    public static func metrics(for width: LayoutWidth) -> LayoutMetrics {
        switch width {
        case .compact:
            LayoutMetrics(gutter: 20, sectionSpacing: 22,
                          maxContentWidth: .infinity, heroScale: 1.0,
                          fabBottomInset: 72, contentBottomInset: 130,
                          railInset: 0,
                          statColumns: 2, tileColumns: 3, isRegular: false)
        case .regular:
            // The floating button clears a sidebar rather than a bottom tab bar,
            // so it no longer needs to sit a tab bar's height off the floor.
            LayoutMetrics(gutter: 32, sectionSpacing: 30,
                          maxContentWidth: 1060, heroScale: 1.3,
                          fabBottomInset: 28, contentBottomInset: 32,
                          railInset: 112,
                          statColumns: 4, tileColumns: 6, isRegular: true)
        }
    }

}

public extension EnvironmentValues {
    /// Defaults to compact, so a view rendered without the shell's injection
    /// behaves like a phone rather than like nothing.
    @Entry var layout: LayoutMetrics = .metrics(for: .compact)
}
