import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorBandTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func progress(on day: Int) -> MonthProgress {
        MonthProgress(
            window: MonthWindow(for: date(2026, 8, 1), calendar: calendar),
            now: date(2026, 8, day), calendar: calendar
        )
    }

    func poorMonth(days: Int = 27) -> MonthInputs {
        MonthInputs(
            readings: Array(
                repeating: DayReading(steps: 200, sleepMinutes: 200, exerciseMinutes: 0, waterML: 100),
                count: days
            ),
            targets: .default, daysInMonth: 31
        )
    }

    func band(_ sector: LifeSector, _ inputs: MonthInputs, on day: Int = 27,
              answers: [String: String] = [:]) -> SectorBand {
        SectorBand.band(
            for: sector, inputs: inputs, progress: progress(on: day),
            answers: answers, calendar: calendar
        )
    }

    @Test func aMonthWithRoomToMoveHasACeilingAboveItsFloor() {
        let body = band(.body, poorMonth())
        let floor = try! #require(body.floor)
        let ceiling = try! #require(body.ceiling)
        #expect(ceiling > floor)
    }

    @Test func theCeilingIsNeverBelowTheFloor() {
        for sector in LifeSector.boardOrder {
            let result = band(sector, poorMonth())
            if let floor = result.floor, let ceiling = result.ceiling {
                #expect(ceiling >= floor, "\(sector.title) inverted")
            }
        }
    }

    /// On the last day nothing is left to change, so the band is a point.
    @Test func theBandCollapsesOnTheLastDayOfTheMonth() {
        let result = band(.body, poorMonth(days: 31), on: 31)
        #expect(result.floor == result.ceiling)
        #expect(result.decided == 1)
    }

    @Test func aSectorWithNoEvidenceIsNotJudgedAtAll() {
        let result = band(.family, MonthInputs(daysInMonth: 31))
        #expect(result.floor == nil)
        #expect(result.ceiling == nil)
        #expect(result.decided == nil)
    }

    /// With no buckets there is no defensible best remaining spend. Zero is
    /// fantasy and any other number is invented, so Money shows a floor alone.
    @Test func moneyHasNoCeilingWithoutBuckets() {
        let inputs = MonthInputs(amounts: [3000, -1500], daysInMonth: 31)
        let result = band(.money, inputs)
        #expect(result.floor != nil)
        #expect(result.ceiling == nil)
        #expect(result.decided == nil)
    }

    @Test func moneyHasACeilingOnceBucketsExist() {
        let row = BudgetReport.Row(
            id: UUID(), name: "Eating out", limit: 300, spent: 200,
            adherence: BudgetPeriod.adherence(spent: 200, limit: 300)
        )
        let inputs = MonthInputs(
            amounts: [3000, -1500], budget: BudgetReport(rows: [row], unclaimed: []),
            daysInMonth: 31
        )
        #expect(band(.money, inputs).ceiling != nil)
    }

    @Test func decidedIsTheShareOfTheScoreThatCanNoLongerMove() {
        let result = band(.body, poorMonth())
        let floor = try! #require(result.floor)
        let ceiling = try! #require(result.ceiling)
        let decided = try! #require(result.decided)
        #expect(abs(decided - (1 - Double(ceiling - floor) / 10)) < 0.001)
    }

    /// The evidence behind each end is kept, because a number nobody can
    /// audit is exactly what this app refuses to show.
    @Test func bothEndsCarryTheirEvidence() {
        let result = band(.body, poorMonth())
        #expect(result.floorEvidence.isEmpty == false)
        #expect(result.ceilingEvidence.isEmpty == false)
    }

    /// An answer given mid-month scores immediately, which is what makes the
    /// relational cards live at all.
    @Test func anAnsweredCheckInGivesARelationalSectorABand() {
        let answers = ["friends.seen": "a lot", "friends.depth": "more than once"]
        let result = band(.friends, MonthInputs(daysInMonth: 31), answers: answers)
        #expect(result.floor != nil)
    }

    /// One rule renders every band as text: nil floor is nil text, a
    /// collapsed or ceiling-less band is a single number, and a true range
    /// is floor–ceiling with an en dash.
    @Test func rangeTextCoversTheThreeShapesABandCanTake() {
        let noEvidence = band(.family, MonthInputs(daysInMonth: 31))
        #expect(noEvidence.rangeText == nil)

        let collapsed = band(.body, poorMonth(days: 31), on: 31)
        #expect(collapsed.rangeText == String(try! #require(collapsed.floor)))

        let inFlight = band(.body, poorMonth())
        let floor = try! #require(inFlight.floor)
        let ceiling = try! #require(inFlight.ceiling)
        #expect(inFlight.rangeText == "\(floor)–\(ceiling)")
    }
}
