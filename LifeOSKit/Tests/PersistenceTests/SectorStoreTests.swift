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

    /// `commit` is a no-op once a sector is decided, however it is reached.
    /// `record()` already refuses to touch a decided row, but it hands the
    /// row back rather than refusing to return it, and that is exactly what
    /// let a second `commit` overwrite the first decision before this guard
    /// existed.
    @Test func committingTwiceLeavesTheFirstDecisionIntact() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        let score = try store.record(sector: .growth, month: august, proposed: 6, evidence: Evidence())

        try store.commit(userScore: 8, to: score)
        try store.commit(userScore: 3, to: score)

        let stored = try store.score(.growth, month: august)
        #expect(stored?.userScore == 8)
    }

    /// `record()` runs as soon as a sector is shown, well before it is
    /// decided, so a month sitting at less than nine scored sectors is the
    /// ordinary shape of a partial close, not a state only a save failure
    /// could produce. This is the state `CloseSchedule` actually has to
    /// reason about.
    @Test func scoredCountsReflectsAGenuinePartialClose() throws {
        let store = try makeStore()
        let july = month(2026, 7)

        let scored = try store.record(sector: .body, month: july, proposed: 8, evidence: Evidence())
        try store.commit(userScore: 8, to: scored)
        _ = try store.record(sector: .money, month: july, proposed: 4, evidence: Evidence())

        let counts = try store.scoredCounts(before: month(2026, 8))
        #expect(counts[july] == 1)
    }

    /// A month with no rows at all is not a gap: it has never been touched,
    /// which is a different thing from having been left half-scored.
    @Test func aMonthWithNoRowsIsAbsentFromScoredCounts() throws {
        let store = try makeStore()
        let counts = try store.scoredCounts(before: month(2026, 8))
        #expect(counts[month(2026, 7)] == nil)
    }

    /// Only months strictly before the limit are reported, matching the
    /// "before the previous month" boundary `CloseSchedule` relies on.
    @Test func scoredCountsExcludesMonthsAtOrAfterTheLimit() throws {
        let store = try makeStore()
        let august = month(2026, 8)
        _ = try store.record(sector: .body, month: august, proposed: 5, evidence: Evidence())

        let counts = try store.scoredCounts(before: august)
        #expect(counts[august] == nil)
    }

    /// `record` builds the row through the model initialiser while `score`
    /// looks it up through a fetch predicate. Both must key off the same
    /// calendar, or a store built with a non-default one writes under one
    /// "first of month" and reads under another, and idempotency silently
    /// breaks: the read misses, `record` thinks the row is new, and a second
    /// row gets created for what should be the same sector-month.
    @Test func recordAndScoreAgreeUnderAnInjectedCalendar() throws {
        var nonDefault = Calendar(identifier: .gregorian)
        nonDefault.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let store = SectorStore(
            context: ModelContext(try LifeOSContainer.make(inMemory: true)),
            calendar: nonDefault
        )
        let august = month(2026, 8)

        let created = try store.record(
            sector: .growth, month: august, proposed: 6, evidence: Evidence()
        )

        let found = try store.score(.growth, month: august)
        #expect(found?.month == created.month)
        #expect(found?.proposedScore == 6)

        _ = try store.record(
            sector: .growth, month: august, proposed: 9, evidence: Evidence()
        )
        let all = try store.scores(forMonth: august)
        #expect(all.count == 1)
        #expect(all.first?.proposedScore == 9)
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
