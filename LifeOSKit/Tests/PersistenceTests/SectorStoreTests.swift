import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SectorStoreTests {

    private func makeStore() throws -> SectorStore {
        SectorStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    @Test func recordingAProposalIsIdempotentPerSectorMonth() throws {
        let store = try makeStore()
        let august = month(2026, 8)

        _ = try store.record(sector: .body, month: august, proposed: 7, evidence: Evidence())
        _ = try store.record(sector: .body, month: august, proposed: 9, evidence: Evidence())

        let scores = try store.scores(forMonth: august)
        #expect(scores.count == 1)
        #expect(scores.first?.proposedScore == 9)
    }

    @Test func committingAUserScoreClosesTheSector() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        let score = try store.record(sector: .soul, month: august, proposed: 6, evidence: Evidence())

        try store.commit(userScore: 4, to: score)

        let stored = try store.score(.soul, month: august)
        #expect(stored?.userScore == 4)
        #expect(stored?.proposedScore == 6)
        #expect(stored?.closedAt != nil)
    }

    /// Once a sector is decided, its reasoning is history. Recomputing must
    /// not rewrite either the decision or the evidence behind it.
    @Test func rerecordingLeavesAClosedScoreEntirelyAlone() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        let original = Evidence([
            EvidenceRow(label: "kept of what came in", value: "40%", normalised: 0.8)
        ])
        let score = try store.record(
            sector: .money, month: august, proposed: 5, evidence: original
        )
        try store.commit(userScore: 8, to: score)

        _ = try store.record(
            sector: .money, month: august, proposed: 2, evidence: Evidence()
        )

        let stored = try store.score(.money, month: august)
        #expect(stored?.userScore == 8)
        #expect(stored?.proposedScore == 5)
        #expect(stored?.archivedEvidence == original)
    }

    @Test func historyIsNewestLastAndLimited() throws {
        let store = try makeStore()
        for m in 1...8 {
            let score = try store.record(
                sector: .body, month: month(2026, m), proposed: m, evidence: Evidence()
            )
            try store.commit(userScore: m, to: score)
        }

        let history = try store.history(sector: .body, months: 6)
        #expect(history.count == 6)
        #expect(history.first?.userScore == 3)
        #expect(history.last?.userScore == 8)
    }

    /// A month never closed stays offered rather than being replaced by a
    /// newer one, so a gap in the history is always visible and fillable.
    @Test func theOldestUnclosedMonthIsOfferedFirst() throws {
        let store = try makeStore()
        let july = month(2026, 7)
        let august = month(2026, 8)
        _ = try store.record(sector: .body, month: july, proposed: 5, evidence: Evidence())
        _ = try store.record(sector: .body, month: august, proposed: 5, evidence: Evidence())

        #expect(try store.oldestUnclosedMonth(before: month(2026, 9)) == july)
    }

    @Test func aFullyClosedMonthIsNotOffered() throws {
        let store = try makeStore()
        let july = month(2026, 7)
        for sector in LifeSector.allCases {
            let score = try store.record(
                sector: sector, month: july, proposed: 5, evidence: Evidence()
            )
            try store.commit(userScore: 5, to: score)
        }

        #expect(try store.oldestUnclosedMonth(before: month(2026, 8)) == nil)
    }

    @Test func answersAreKeptPerSectorMonth() throws {
        let store = try makeStore()
        let august = month(2026, 8)

        try store.saveAnswer(sector: .friends, month: august, questionID: "seen", answer: "3")
        try store.saveAnswer(sector: .friends, month: august, questionID: "seen", answer: "5")

        let answers = try store.answers(sector: .friends, month: august)
        #expect(answers.count == 1)
        #expect(answers.first?.answer == "5")
    }
}
