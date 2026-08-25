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

    // MARK: - The window a chart is drawn over

    @Test func aWindowRunsOldestFirstAndEndsOnTheDayAsked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let end = Date(timeIntervalSince1970: 1_700_000_000)

        let days = TrendSeries.days(endingOn: end, count: 7, calendar: calendar)

        #expect(days.count == 7)
        #expect(days == days.sorted())
        #expect(calendar.isDate(days.last!, inSameDayAs: end))
    }

    /// Every slot is a day wide. A chart relies on this: neighbouring bars are
    /// only comparable if they are the same distance apart.
    @Test func everyDayInTheWindowIsOneDayAfterTheLast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let days = TrendSeries.days(endingOn: .now, count: 7, calendar: calendar)

        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: earlier, to: later).day == 1)
        }
    }

    /// Guards the range construction: a non-positive count must not trap.
    @Test func anEmptyWindowIsEmptyRatherThanACrash() {
        #expect(TrendSeries.days(endingOn: .now, count: 0, calendar: .current).isEmpty)
        #expect(TrendSeries.days(endingOn: .now, count: -3, calendar: .current).isEmpty)
    }

    @Test func aWindowOfNothingButGapsHoldsNoReading() {
        let gaps = TrendSeries(points: (0..<7).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0) * 86_400), value: nil)
        })
        #expect(gaps.hasAnyReading == false)

        let one = TrendSeries(points: gaps.points.dropLast() + [
            TrendPoint(date: Date(timeIntervalSince1970: 7 * 86_400), value: 61)
        ])
        #expect(one.hasAnyReading)
    }
}
