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
    /// Caps prose and single-column content so a 1366pt pane does not produce a
    /// 90 character measure. Grids are exempt and fill the pane.
    public let maxContentWidth: CGFloat
    public let heroScale: CGFloat
    public let fabBottomInset: CGFloat
    /// Columns for a grid of stat tiles, and for the denser rows of small
    /// metric tiles. Derived from the width class rather than measured, because
    /// a measured count needs a GeometryReader and `GridItem(.adaptive)` cannot
    /// cap the count at all: a 1366pt pane would take eight tiles across.
    public let statColumns: Int
    public let tileColumns: Int

    public static func metrics(for width: LayoutWidth) -> LayoutMetrics {
        switch width {
        case .compact:
            LayoutMetrics(gutter: 20, sectionSpacing: 22,
                          maxContentWidth: .infinity, heroScale: 1.0,
                          fabBottomInset: 72, statColumns: 2, tileColumns: 3)
        case .regular:
            // The floating button clears a sidebar rather than a bottom tab bar,
            // so it no longer needs to sit a tab bar's height off the floor.
            LayoutMetrics(gutter: 32, sectionSpacing: 30,
                          maxContentWidth: 860, heroScale: 1.3,
                          fabBottomInset: 28, statColumns: 4, tileColumns: 6)
        }
    }

}

public extension EnvironmentValues {
    /// Defaults to compact, so a view rendered without the shell's injection
    /// behaves like a phone rather than like nothing.
    @Entry var layout: LayoutMetrics = .metrics(for: .compact)
}
