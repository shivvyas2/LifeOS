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

    /// A portrait iPad is 1024pt wide, and the cap sits above that on purpose:
    /// portrait is already close to a single comfortable column, so capping it
    /// again only bought dead margin. The cap exists for landscape and for wide
    /// Stage Manager panes, where an uncapped column really would sprawl.
    @Test func theContentCapOnlyBitesWiderThanAPortraitIPad() {
        #expect(LayoutMetrics.metrics(for: .regular).maxContentWidth > 1024)
    }

    /// The floating button sits above a bottom tab bar on iPhone. In regular
    /// width the bar is a sidebar, so the old inset left it hovering above
    /// nothing.
    @Test func theFloatingButtonSitsLowerWhenThereIsNoBottomTabBar() {
        #expect(LayoutMetrics.metrics(for: .regular).fabBottomInset
                < LayoutMetrics.metrics(for: .compact).fabBottomInset)
    }

    /// The pill bar floats over the scroll view instead of insetting it, so
    /// compact content has to reserve a band for it. A side rail takes its space
    /// out of the width, so regular content reserves nothing but breathing room.
    @Test func onlyCompactContentReservesRoomForABottomBar() {
        let compact = LayoutMetrics.metrics(for: .compact)
        let regular = LayoutMetrics.metrics(for: .regular)

        #expect(compact.contentBottomInset > compact.fabBottomInset)
        #expect(regular.contentBottomInset < compact.contentBottomInset)
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

    /// The bar moves from the bottom to the side, so the room it needs moves
    /// with it. The action buttons never claim room on either width: they float
    /// over the bottom corner in both.
    @Test func onlyRegularWidthPaysForTheRailOnTheLeadingEdge() {
        #expect(LayoutMetrics.metrics(for: .compact).railInset == 0)
        #expect(LayoutMetrics.metrics(for: .regular).railInset > 0)
    }

    @Test func metricsReportTheWidthClassTheyCameFrom() {
        #expect(LayoutMetrics.metrics(for: .regular).isRegular)
        #expect(LayoutMetrics.metrics(for: .compact).isRegular == false)
    }

    @Test func everyMetricIsPositive() {
        for width in [LayoutWidth.compact, .regular] {
            let metrics = LayoutMetrics.metrics(for: width)
            #expect(metrics.gutter > 0)
            #expect(metrics.sectionSpacing > 0)
            #expect(metrics.heroScale > 0)
            #expect(metrics.fabBottomInset > 0)
            #expect(metrics.contentBottomInset > 0)
            #expect(metrics.railInset >= 0)
            #expect(metrics.statColumns >= 1)
            #expect(metrics.tileColumns >= 1)
        }
    }
}
