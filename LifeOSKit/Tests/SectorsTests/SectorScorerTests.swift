import Testing
@testable import Sectors
@testable import Persistence

@Suite struct SectorScorerTests {
    @Test func conformingTypesProduceEvidence() {
        struct TestScorer: SectorScorer {
            var sector: LifeSector { .mind }
            func evidence() -> Evidence {
                Evidence([
                    EvidenceRow(label: "test", value: "pass", normalised: 1.0)
                ])
            }
        }

        let scorer = TestScorer()
        let evidence = scorer.evidence()
        #expect(evidence.proposedScore == 10)
    }
}
