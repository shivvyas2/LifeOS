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
        #expect(EffortAccumulator.weights == [0, 0.15, 0.28, 0.35, 0.45, 0.63])
        #expect(EffortAccumulator.scale == 1500)

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

    private func recovery(_ date: Date, whoop: Double? = nil, calibrating: Bool? = nil, sleepPerf: Double? = nil,
                          hrv: Double? = nil, sleep: Int? = nil) -> RecoveryDay {
        RecoveryDay(date: calendar.startOfDay(for: date), whoopRecoveryPct: whoop, whoopIsCalibrating: calibrating,
                    sleepPerformancePct: sleepPerf, hrvMs: hrv, sleepMinutes: sleep)
    }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today)! }

    @Test func whoopRecoveryBlendsSleepAndSetsGreenCeiling() throws {
        let capacity = try #require(CapacityMath.capacity(days: [recovery(today, whoop: 80, sleepPerf: 90)], now: today, calendar: calendar))
        #expect(capacity.percent == 82)
        #expect(capacity.source == .whoop)
        #expect(capacity.ceiling == .green)
        #expect(capacity.measuredOn == calendar.startOfDay(for: today))
    }

    @Test func yesterdayRecoveryStandsInUntilTodaySyncs() throws {
        let capacity = try #require(CapacityMath.capacity(days: [recovery(daysAgo(1), whoop: 40)], now: today, calendar: calendar))
        #expect(capacity.percent == 40)
        #expect(capacity.ceiling == .yellow)
        #expect(CapacityMath.capacity(days: [recovery(daysAgo(2), whoop: 40)], now: today, calendar: calendar) == nil)
    }

    @Test func calibratingWhoopFallsThroughToHealth() throws {
        let days = [recovery(today, whoop: 80, calibrating: true, hrv: 60, sleep: 450)]
            + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        let capacity = try #require(CapacityMath.capacity(days: days, now: today, calendar: calendar))
        #expect(capacity.source == .health)
        #expect(capacity.percent == 65)
        #expect(capacity.ceiling == .yellow)
    }

    @Test func healthCapacityNeedsABaselineAndRespondsToSleep() throws {
        #expect(CapacityMath.capacity(days: [recovery(today, hrv: 60), recovery(daysAgo(1), hrv: 60)], now: today, calendar: calendar) == nil)
        let short = [recovery(today, hrv: 60, sleep: 300)] + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        #expect(try #require(CapacityMath.capacity(days: short, now: today, calendar: calendar)).percent == 55)
        let strong = [recovery(today, hrv: 72)] + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        #expect(try #require(CapacityMath.capacity(days: strong, now: today, calendar: calendar)).percent == 90)
        #expect(CapacityMath.capacity(days: [], now: today, calendar: calendar) == nil)
    }

    @Test func batteryDrainsAgainstTheTargetTop() {
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 7, ceiling: .yellow) == 30)
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 15, ceiling: .yellow) == 0)
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 0, ceiling: .yellow) == 60)
    }

    @Test func pushStateFollowsZoneAndEffort() {
        #expect(EffortMath.pushState(zone: 5, effort: 8, ceiling: .yellow) == .overLimit)
        #expect(EffortMath.pushState(zone: 3, effort: 15, ceiling: .yellow) == .overLimit)
        #expect(EffortMath.pushState(zone: 4, effort: 8, ceiling: .yellow) == .nearLimit)
        #expect(EffortMath.pushState(zone: 3, effort: 13, ceiling: .yellow) == .nearLimit)
        #expect(EffortMath.pushState(zone: 2, effort: 3, ceiling: .yellow) == .easy)
        #expect(EffortMath.pushState(zone: 3, effort: 3, ceiling: .yellow) == .onTrack)
        #expect(EffortMath.pushState(zone: nil, effort: 11, ceiling: .yellow) == .onTrack)
        #expect(EffortMath.pushState(zone: nil, effort: 3, ceiling: .yellow) == .easy)
    }

    @Test func ceilingBands() {
        #expect(EffortCeiling.forCapacity(67) == .green)
        #expect(EffortCeiling.forCapacity(66) == .yellow)
        #expect(EffortCeiling.forCapacity(34) == .yellow)
        #expect(EffortCeiling.forCapacity(33) == .red)
        #expect(EffortCeiling.conservative == .yellow)
    }

    @Test func builderJoinsEverythingAndKeepsAbsence() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        var effort = EffortAccumulator(); effort.add(zone: 3, seconds: 1800)
        let timer = ActivitySessionState(activity: "Run", at: today)
        let capacity = Capacity(percent: 60, source: .whoop, measuredOn: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 150, zones: zones, effort: effort,
                                                 capacity: capacity, energyKcal: 210.6, distanceMeters: 1234.9)
        #expect(readout.heartRate == 150)
        #expect(readout.zone == 4)
        #expect(readout.effort == 7.2)
        #expect(readout.calories == 211)
        #expect(readout.distanceMeters == 1235)
        #expect(readout.batteryPercent == 29)
        #expect(readout.capacitySource == "whoop")
        #expect(readout.ceilingMaxZone == 4)
        #expect(readout.ceilingTarget == 10...14)
        #expect(readout.push == .nearLimit)
        #expect(readout.runningSince == today)
    }

    @Test func builderWithoutZonesReportsBeatsOnly() {
        let timer = ActivitySessionState(activity: "Walk", at: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 120, zones: nil, effort: EffortAccumulator(load: 500),
                                                 capacity: nil, energyKcal: nil, distanceMeters: nil)
        #expect(readout.heartRate == 120)
        #expect(readout.zone == nil)
        #expect(readout.effort == nil)
        #expect(readout.batteryPercent == nil)
        #expect(readout.calories == nil)
        #expect(readout.ceilingMaxZone == nil)
        #expect(readout.push == .onTrack)
    }

    @Test func builderUsesConservativeCeilingWithoutCapacity() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        let timer = ActivitySessionState(activity: "Run", at: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 175, zones: zones, effort: EffortAccumulator(),
                                                 capacity: nil, energyKcal: nil, distanceMeters: nil)
        #expect(readout.batteryPercent == nil)
        #expect(readout.ceilingMaxZone == 4)
        #expect(readout.push == .overLimit)
    }

    @Test func autoPairPicksExactlyOneWhoop() {
        #expect(WhoopAutoPair.choice(among: []) == .none)
        #expect(WhoopAutoPair.choice(among: ["Polar H10"]) == .none)
        #expect(WhoopAutoPair.choice(among: ["Polar H10", "WHOOP 4A0B"]) == .one(1))
        #expect(WhoopAutoPair.choice(among: ["whoop", "WHOOP 4A0B"]) == .several)
    }
}
