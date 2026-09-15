import Testing
@testable import AppSurfaces

struct SessionRingMathTests {
    @Test func heartRingFillsByZoneAgainstTodaysCeiling() {
        #expect(SessionRingMath.heartFill(zone: 2, ceilingMaxZone: 4) == 0.5)
        #expect(SessionRingMath.heartFill(zone: 5, ceilingMaxZone: 4) == 1)
        #expect(SessionRingMath.heartFill(zone: 3, ceilingMaxZone: nil) == 0.6)
        #expect(SessionRingMath.heartFill(zone: nil, ceilingMaxZone: 4) == 0)
    }

    @Test func effortRingFillsAgainstTheTopOfTheTargetBand() {
        #expect(SessionRingMath.effortFill(effort: 7, target: 10...14) == 0.5)
        #expect(SessionRingMath.effortFill(effort: 14, target: 10...14) == 1)
        #expect(SessionRingMath.effortFill(effort: 20, target: 10...14) == 1)
        #expect(SessionRingMath.effortFill(effort: 9, target: nil) == 0.5)
        #expect(SessionRingMath.effortFill(effort: nil, target: 10...14) == 0)
    }

    @Test func effortIsOverOnlyPastTheBand() {
        #expect(SessionRingMath.effortIsOver(effort: 14, target: 10...14) == false)
        #expect(SessionRingMath.effortIsOver(effort: 14.1, target: 10...14) == true)
        #expect(SessionRingMath.effortIsOver(effort: 30, target: nil) == false)
    }

    @Test func batteryRingIsThePercentage() {
        #expect(SessionRingMath.batteryFill(percent: 62) == 0.62)
        #expect(SessionRingMath.batteryFill(percent: 140) == 1)
        #expect(SessionRingMath.batteryFill(percent: nil) == 0)
    }

    @Test func aBeatLastsSixtyOverBPM() {
        #expect(SessionRingMath.beatPeriod(bpm: 120) == 0.5)
        #expect(SessionRingMath.beatPeriod(bpm: nil) == nil)
        #expect(SessionRingMath.beatPeriod(bpm: 0) == nil)
    }
}
