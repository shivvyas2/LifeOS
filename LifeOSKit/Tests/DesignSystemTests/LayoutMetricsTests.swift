import Testing
import Foundation
@testable import DesignSystem

@Suite struct LayoutMetricsTests {
    // MARK: - Metrics per width class

    @Test func regularWidthIsRoomierThanCompact() {
        let compact = LayoutMetrics.metrics(for: .compact)
        let regular = LayoutMetrics.metrics(for: .regular)

        #expect(regular.gutter > compact.gutter)
        #expect(regular.sectionSpacing > compact.sectionSpacing)
        #expect(regular.heroScale > compact.heroScale)
    }

    /// Compact must not cap the content width. A phone has no room to spare and
    /// a cap there would shrink the only column there is.
    @Test func onlyRegularWidthCapsTheContentColumn() {
        #expect(LayoutMetrics.metrics(for: .compact).maxContentWidth == .infinity)
        #expect(LayoutMetrics.metrics(for: .regular).maxContentWidth < .infinity)
    }

    /// The floating button sits above a bottom tab bar on iPhone. In regular
    /// width the bar is a sidebar, so the old inset left it hovering above
    /// nothing.
    @Test func theFloatingButtonSitsLowerWhenThereIsNoBottomTabBar() {
        #expect(LayoutMetrics.metrics(for: .regular).fabBottomInset
                < LayoutMetrics.metrics(for: .compact).fabBottomInset)
    }

    /// A wide pane earns more columns, but a bounded number of them. Unbounded
    /// growth is how a 4-up grid becomes a row of postage stamps.
    @Test func regularWidthEarnsMoreColumnsButNotUnboundedly() {
        let compact = LayoutMetrics.metrics(for: .compact)
        let regular = LayoutMetrics.metrics(for: .regular)

        #expect(regular.statColumns > compact.statColumns)
        #expect(regular.tileColumns > compact.tileColumns)
        #expect(regular.statColumns <= 6)
        #expect(regular.tileColumns <= 8)
    }

    @Test func everyMetricIsPositive() {
        for width in [LayoutWidth.compact, .regular] {
            let metrics = LayoutMetrics.metrics(for: width)
            #expect(metrics.gutter > 0)
            #expect(metrics.sectionSpacing > 0)
            #expect(metrics.heroScale > 0)
            #expect(metrics.fabBottomInset > 0)
            #expect(metrics.statColumns >= 1)
            #expect(metrics.tileColumns >= 1)
        }
    }
}
