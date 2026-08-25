import Testing
import Foundation
@testable import DesignSystem

@Suite struct SleepCompositionTests {
    private let night = Date(timeIntervalSince1970: 1_786_000_000)

    @Test func segmentsCarryEveryStageThatWasRecorded() {
        let composition = SleepComposition(
            date: night, lightMinutes: 231, remMinutes: 103, swsMinutes: 98, awakeMinutes: 12
        )
        #expect(composition.segments.count == 4)
        #expect(composition.totalMinutes == 444)
        #expect(composition.asleepMinutes == 432)   // total less awake
    }

    /// A night Whoop scored but did not break down still has a duration. It is
    /// drawn from the stages it does have rather than dropped.
    @Test func aNightMissingOneStageStillRendersTheOthers() {
        let composition = SleepComposition(
            date: night, lightMinutes: 231, remMinutes: nil, swsMinutes: 98, awakeMinutes: 12
        )
        #expect(composition.segments.map(\.stage) == [.sws, .light, .awake])
        #expect(composition.totalMinutes == 341)
    }

    /// A night with no stage data at all must be excluded, not drawn as a
    /// zero-height bar that reads as "you did not sleep".
    @Test func aNightWithNoStagesIsNotRenderable() {
        let composition = SleepComposition(
            date: night, lightMinutes: nil, remMinutes: nil, swsMinutes: nil, awakeMinutes: nil
        )
        #expect(composition.isRenderable == false)
        #expect(composition.segments.isEmpty)
        #expect(composition.totalMinutes == 0)
    }

    /// Awake time counts toward the bar's height, because time in bed is the
    /// honest total, but never toward time asleep.
    @Test func awakeTimeCountsTowardTheBarButNotTowardSleep() {
        let composition = SleepComposition(
            date: night, lightMinutes: 100, remMinutes: nil, swsMinutes: nil, awakeMinutes: 20
        )
        #expect(composition.totalMinutes == 120)
        #expect(composition.asleepMinutes == 100)
    }

    /// Deep first, then REM, then light, then awake. A fixed order means two
    /// nights can be compared by eye; ordering by size could not.
    @Test func stagesAreStackedInAFixedOrder() {
        let composition = SleepComposition(
            date: night, lightMinutes: 1, remMinutes: 2, swsMinutes: 3, awakeMinutes: 4
        )
        #expect(composition.segments.map(\.stage) == [.sws, .rem, .light, .awake])
    }

    /// The score bar is sleep stages only, left to right, and never awake.
    @Test func scoreBarIsLightThenRemThenDeepAndOmitsAwake() {
        let composition = SleepComposition(
            date: night, lightMinutes: 231, remMinutes: 103, swsMinutes: 98, awakeMinutes: 12
        )
        #expect(composition.scoreBarSegments.map(\.stage) == [.light, .rem, .sws])
        #expect(composition.scoreBarSegments.map(\.minutes) == [231, 103, 98])
    }
}
