import Testing
import Foundation
import Persistence
@testable import Insights

@Suite struct SectorNoteTests {

    private var evidence: Evidence {
        Evidence([
            EvidenceRow(label: "days written", value: "5/30", normalised: 0.16, weight: 2),
            EvidenceRow(label: "vs last month", value: "-58%", normalised: 0.2, weight: 1),
        ])
    }

    /// The model is shown only what the rule used, so it cannot cite a figure
    /// that played no part in the score.
    @Test func thePromptCarriesEveryEvidenceRow() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", rows: evidence.rows, previousUserScore: 7
        )
        let prompt = SectorNoteTask(sectorTitle: "Soul").prompt(context)

        #expect(prompt.contains("days written"))
        #expect(prompt.contains("5/30"))
        #expect(prompt.contains("vs last month"))
        #expect(prompt.contains("Soul"))
    }

    @Test func lastMonthsScoreIsOfferedForComparison() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", rows: evidence.rows, previousUserScore: 7
        )
        #expect(context.promptLines.contains("7"))
    }

    @Test func aFirstMonthMentionsNoPreviousScore() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", rows: evidence.rows, previousUserScore: nil
        )
        #expect(!context.promptLines.lowercased().contains("last month you scored"))
    }

    /// The number is the rule's job. The model describes and nothing more.
    @Test func theInstructionsForbidJudgingOrScoring() {
        let instructions = SectorNoteTask(sectorTitle: "Soul").instructions.lowercased()
        #expect(instructions.contains("never"))
        #expect(instructions.contains("score"))
    }

    @Test func theTaskRunsOnDevice() {
        #expect(SectorNoteTask(sectorTitle: "Soul").floor == .onDevice)
    }

    @Test func emptyEvidenceStillProducesAUsablePrompt() {
        let context = SectorEvidenceContext(
            sectorTitle: "Romance", rows: [], previousUserScore: nil
        )
        #expect(!SectorNoteTask(sectorTitle: "Romance").prompt(context).isEmpty)
    }
}
