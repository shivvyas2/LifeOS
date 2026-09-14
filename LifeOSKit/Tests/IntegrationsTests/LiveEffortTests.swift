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

    @Test func effortCalibrationPoints() {
        var steadyZone3 = EffortAccumulator()
        steadyZone3.add(zone: 3, seconds: 3600)
        #expect(abs(steadyZone3.effort - 12) < 1)

        var easyZone2 = EffortAccumulator()
        easyZone2.add(zone: 2, seconds: 1800)
        #expect(abs(easyZone2.effort - 6) < 1)

        var hard = EffortAccumulator()
        hard.add(zone: 4, seconds: 2700); hard.add(zone: 5, seconds: 2700)
        #expect(abs(hard.effort - 18) < 1)

        #expect(EffortAccumulator().effort == 0)
    }

    @Test func effortIsBoundedAndMonotonic() {
        var effort = EffortAccumulator()
        var last = 0.0
        for _ in 0..<100 {
            effort.add(zone: 5, seconds: 600)
            #expect(effort.effort >= last)
            last = effort.effort
        }
        #expect(last < 21)
        effort.add(zone: 0, seconds: 3600)
        #expect(effort.effort == last)
        effort.add(zone: 9, seconds: 60); effort.add(zone: 3, seconds: -5)
        #expect(effort.effort == last)
    }

    @Test func creditCapsGapsAndStartsAtZero() {
        let now = today
        #expect(EffortAccumulator.credit(previous: nil, at: now) == 0)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(-40), at: now) == 5)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(-2), at: now) == 2)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(3), at: now) == 0)
    }
}
