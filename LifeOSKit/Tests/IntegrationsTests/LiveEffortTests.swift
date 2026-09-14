import Foundation
import Testing
import AppSurfaces
@testable import Integrations

struct LiveEffortTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private var today: Date { day(2026, 9, 14) }
    private var thirtyYearsOld: Date { day(1996, 6, 1) }

    @Test func zonesFollowTanakaAndWhoopBands() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        #expect(zones.maxHeartRate == 187)
        #expect(zones.zone(for: 90) == 0)
        #expect(zones.zone(for: 94) == 1)
        #expect(zones.zone(for: 131) == 3)
        #expect(zones.zone(for: 169) == 5)
    }

    @Test func noBirthDateMeansNoZones() {
        #expect(HeartRateZones(birthDate: nil, on: today, calendar: calendar) == nil)
        #expect(HeartRateZones(birthDate: day(2025, 1, 1), on: today, calendar: calendar) == nil)
    }
}
