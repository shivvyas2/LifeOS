import Testing
import Foundation
import SwiftUI
@testable import DesignSystem

@Suite struct RoundedBarChartTests {
    private typealias Chart = RoundedBarChart

    // MARK: - Zero baseline

    /// A counter's bars are read against nought, so the week's best fills the
    /// track and half of it fills half.
    @Test func zeroBaselineScalesAgainstTheWeeksPeak() {
        let week = [2_000.0, 6_000, 10_000]

        #expect(Chart.fraction(of: 10_000, in: week, baseline: .zero) == 1)
        #expect(Chart.fraction(of: 5_000, in: week, baseline: .zero) == 0.5)
    }

    /// The peak is the week's, not the reading's, so a quiet day stays visibly
    /// quiet instead of being promoted to a full bar by being alone.
    @Test func zeroBaselineDoesNotLetAQuietDayFillTheTrack() {
        #expect(Chart.fraction(of: 1_000, in: [1_000, 20_000], baseline: .zero) < 0.1)
    }

    // MARK: - Window minimum baseline

    /// Weight against nought is seven identical bars. Against the week's low it
    /// is a shape.
    @Test func windowMinimumSpreadsAMetricThatNeverNearsZero() {
        let week = [77.4, 77.8, 78.0]

        #expect(Chart.fraction(of: 77.4, in: week, baseline: .windowMinimum) == 0)
        #expect(Chart.fraction(of: 78.0, in: week, baseline: .windowMinimum) == 1)

        // The same readings against nought are indistinguishable.
        let low = Chart.fraction(of: 77.4, in: week, baseline: .zero)
        let high = Chart.fraction(of: 78.0, in: week, baseline: .zero)
        #expect(high - low < 0.01)
    }

    /// Every reading is both the high and the low, so neither extreme is
    /// honest. Half reads as steady.
    @Test func aFlatWeekDrawsHalfBarsRatherThanFullOrEmptyOnes() {
        #expect(Chart.fraction(of: 78, in: [78, 78, 78], baseline: .windowMinimum) == 0.5)
    }

    @Test func aLoneReadingDrawsAHalfBarAgainstTheWindowMinimum() {
        #expect(Chart.fraction(of: 78, in: [78], baseline: .windowMinimum) == 0.5)
    }

    // MARK: - Bounds

    /// Bars are drawn by multiplying a track height by this, so a value outside
    /// the window must not produce a bar taller than its track.
    @Test func everyFractionStaysWithinTheTrack() {
        for baseline in [Chart.Baseline.zero, .windowMinimum] {
            for value in [-50.0, 0, 1, 9_999, 1_000_000] {
                let fraction = Chart.fraction(of: value, in: [100, 500], baseline: baseline)
                #expect(fraction >= 0)
                #expect(fraction <= 1)
            }
        }
    }

    /// An empty window is what a first launch looks like. It must not divide by
    /// nought or return something unrenderable.
    @Test func anEmptyWindowStillProducesADrawableFraction() {
        let fraction = Chart.fraction(of: 500, in: [], baseline: .zero)
        #expect(fraction >= 0)
        #expect(fraction <= 1)
        #expect(Chart.fraction(of: 500, in: [], baseline: .windowMinimum) == 0.5)
    }

    // MARK: - Styles

    /// Life draws its trends on the dusk field, where the only colours are ink
    /// and the rule.
    @Test func inkStyleDrawsBarsInInkAndTracksAsRules() {
        #expect(Chart.barFill(.ink, scheme: .light) == LifeOSTokens.primaryText.resolve(.light))
        #expect(Chart.barFill(.ink, scheme: .dark) == LifeOSTokens.primaryText.resolve(.dark))
        #expect(Chart.trackFill(.ink, scheme: .light) == Editorial.rule(.light))
    }

    @Test func hueStyleKeepsTheModuleColour() {
        #expect(Chart.barFill(.hue(.activity), scheme: .light) == ModuleHue.activity.top)
        #expect(Chart.trackFill(.hue(.activity), scheme: .dark) == ModuleHue.activity.pastelDark)
    }

    /// Nothing asked for is the accent, as every chart has been so far.
    @Test func accentIsTheDefault() {
        #expect(Chart.barFill(.accent, scheme: .light) == LifeOSTokens.accent)
        #expect(Chart.trackFill(.accent, scheme: .light) == LifeOSTokens.accentSoft.resolve(.light))
    }
}
