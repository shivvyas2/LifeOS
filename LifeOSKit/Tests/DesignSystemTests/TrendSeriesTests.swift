import Testing
import Foundation
@testable import DesignSystem

@Suite struct TrendSeriesTests {
    private let day = Date(timeIntervalSince1970: 1_786_000_000)

    private func series(_ values: [Double?]) -> TrendSeries {
        TrendSeries(points: values.enumerated().map { offset, value in
            TrendPoint(date: day.addingTimeInterval(Double(offset) * 86_400), value: value)
        })
    }

    @Test func averageIgnoresGapsRatherThanCountingThemAsZero() {
        // 6 and 10 average to 8. Counting the gap as a zero would give 5.33,
        // which is the false zero this app refuses.
        let trend = series([6, nil, 10])
        #expect(trend.average == 8)
    }

    /// A fortnight Whoop never reported has no average. Reporting 0 would claim
    /// a reading that does not exist.
    @Test func anAllGapSeriesHasNoAverage() {
        #expect(series([nil, nil, nil]).average == nil)
        #expect(series([]).average == nil)
    }

    @Test func latestIsTheMostRecentReadingNotTheLastSlot() {
        // The last slot is a gap, so the latest READING is 7, not nil.
        #expect(series([5, 7, nil]).latest == 7)
    }

    @Test func latestIsNilWhenNothingWasEverRecorded() {
        #expect(series([nil, nil]).latest == nil)
    }

    @Test func deltaIsTheLatestReadingAgainstTheAverage() {
        // average of 4 and 8 is 6; latest is 8; delta is +2.
        let trend = series([4, 8])
        #expect(trend.deltaFromAverage == 2)
    }

    @Test func deltaIsNegativeWhenTheLatestIsBelowBaseline() {
        #expect(series([10, 6]).deltaFromAverage == -2)
    }

    /// A single reading is its own average, so there is no baseline to compare
    /// against yet. Showing "0 above baseline" would imply a fortnight of
    /// history that does not exist.
    @Test func aSingleReadingHasNoMeaningfulDelta() {
        #expect(series([7]).deltaFromAverage == nil)
    }

    @Test func deltaIsNilWithNothingToCompare() {
        #expect(series([nil, nil]).deltaFromAverage == nil)
    }

    @Test func pointsKeepTheirGapsSoAChartCanDrawThem() {
        let trend = series([1, nil, 3])
        #expect(trend.points.count == 3)
        #expect(trend.points[1].value == nil)
    }
}
