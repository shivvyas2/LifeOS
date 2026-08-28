import Testing
import Foundation
@testable import Persistence

@Suite struct EvidenceTests {

    /// The whole reason the rule is shared: one arithmetic path to verify.
    @Test func aWeightedMeanScalesToTen() {
        let evidence = Evidence([
            EvidenceRow(label: "a", value: "1", normalised: 1.0, weight: 1),
            EvidenceRow(label: "b", value: "0", normalised: 0.0, weight: 1),
        ])
        #expect(evidence.proposedScore == 5)
    }

    @Test func weightsActuallyWeigh() {
        let evidence = Evidence([
            EvidenceRow(label: "heavy", value: "1", normalised: 1.0, weight: 3),
            EvidenceRow(label: "light", value: "0", normalised: 0.0, weight: 1),
        ])
        // (1*3 + 0*1) / 4 = 0.75 -> 7.5 -> 8
        #expect(evidence.proposedScore == 8)
    }

    /// A sector with nothing to say must not claim the person scored zero.
    @Test func noRowsProposesNothingRatherThanZero() {
        #expect(Evidence([]).proposedScore == nil)
    }

    @Test func zeroTotalWeightProposesNothing() {
        let evidence = Evidence([
            EvidenceRow(label: "ignored", value: "0", normalised: 1.0, weight: 0)
        ])
        #expect(evidence.proposedScore == nil)
    }

    @Test func normalisedValuesAreClampedIntoRange() {
        let high = EvidenceRow(label: "over", value: "x", normalised: 4.2, weight: 1)
        let low = EvidenceRow(label: "under", value: "x", normalised: -1.0, weight: 1)
        #expect(high.normalised == 1.0)
        #expect(low.normalised == 0.0)
    }

    @Test func aNegativeWeightIsTreatedAsZero() {
        let row = EvidenceRow(label: "bad", value: "x", normalised: 1.0, weight: -5)
        #expect(row.weight == 0)
    }

    @Test func scoresAreBoundedByTheScale() {
        let perfect = Evidence([EvidenceRow(label: "a", value: "1", normalised: 1.0)])
        let empty = Evidence([EvidenceRow(label: "a", value: "0", normalised: 0.0)])
        #expect(perfect.proposedScore == 10)
        #expect(empty.proposedScore == 0)
    }

    /// Archived onto a score, so it has to survive a round trip unchanged.
    @Test func evidenceRoundTripsThroughCoding() throws {
        let original = Evidence([
            EvidenceRow(label: "journal entries", value: "5", normalised: 0.42, weight: 2)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Evidence.self, from: data)
        #expect(decoded == original)
    }

    @Test func proposedValueKeepsTheFractionThatProposedScoreRounds() {
        let evidence = Evidence([
            EvidenceRow(label: "a", value: "a", normalised: 0.64, weight: 1)
        ])
        #expect(evidence.proposedValue == 6.4)
        #expect(evidence.proposedScore == 6)
    }

    @Test func proposedScoreIsAlwaysTheRoundedProposedValue() {
        let evidence = Evidence([
            EvidenceRow(label: "a", value: "a", normalised: 0.25, weight: 3),
            EvidenceRow(label: "b", value: "b", normalised: 0.9, weight: 1),
        ])
        let value = try! #require(evidence.proposedValue)
        #expect(evidence.proposedScore == Int(value.rounded()))
    }

    @Test func evidenceWithNoRowsHasNoProposedValue() {
        #expect(Evidence().proposedValue == nil)
    }

    @Test func rowsWithNoWeightHaveNoProposedValue() {
        let evidence = Evidence([
            EvidenceRow(label: "context", value: "note", normalised: 0.8, weight: 0)
        ])
        #expect(evidence.proposedValue == nil)
    }
}
