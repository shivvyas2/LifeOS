import Testing
@testable import DesignSystem

/// Whoop's own thresholds, so the app agrees with the Whoop app about what a
/// number means. The boundaries are tested because an off-by-one in a band is
/// invisible until it is the wrong colour on someone's screen.
@Suite struct RecoveryBandTests {
    @Test func theLowToModerateBoundaryIsBetween33And34() {
        #expect(RecoveryBand.band(for: 33) == .low)
        #expect(RecoveryBand.band(for: 34) == .moderate)
    }

    @Test func theModerateToHighBoundaryIsBetween66And67() {
        #expect(RecoveryBand.band(for: 66) == .moderate)
        #expect(RecoveryBand.band(for: 67) == .high)
    }

    @Test func theEndsOfTheScaleBand() {
        #expect(RecoveryBand.band(for: 0) == .low)
        #expect(RecoveryBand.band(for: 100) == .high)
    }

    /// Whoop occasionally reports slightly outside the nominal range; a reading
    /// must still land in a band rather than crashing or falling through.
    @Test func readingsOutsideTheNominalRangeStillBand() {
        #expect(RecoveryBand.band(for: -5) == .low)
        #expect(RecoveryBand.band(for: 140) == .high)
    }

    @Test func eachBandIsNamed() {
        #expect(RecoveryBand.low.label == "Low")
        #expect(RecoveryBand.moderate.label == "Moderate")
        #expect(RecoveryBand.high.label == "High")
    }
}
