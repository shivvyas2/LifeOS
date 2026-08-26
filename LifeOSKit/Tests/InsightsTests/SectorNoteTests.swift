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
        let prompt = SectorNoteTask(sectorTitle: "Soul").prompt(context, for: .onDevice)

        #expect(prompt.contains("days written"))
        #expect(prompt.contains("5/30"))
        #expect(prompt.contains("vs last month"))
        #expect(prompt.contains("Soul"))
    }

    /// The screen already shows "Last month you said N" on its own, and the
    /// instructions forbid the model from mentioning a score at all. Feeding
    /// it last month's number on the same 0-10 scale would work against that
    /// instruction, so the prompt never carries it, even when the context
    /// holds one.
    @Test func previousScoreNeverReachesThePrompt() {
        let context = SectorEvidenceContext(
            sectorTitle: "Soul", rows: evidence.rows, previousUserScore: 7
        )
        #expect(!context.promptLines.contains("7"))
        #expect(!context.promptLines.lowercased().contains("you scored"))
        #expect(!SectorNoteTask(sectorTitle: "Soul").prompt(context, for: .onDevice).lowercased().contains("you scored"))
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
        #expect(!SectorNoteTask(sectorTitle: "Romance").prompt(context, for: .onDevice).isEmpty)
    }
}
