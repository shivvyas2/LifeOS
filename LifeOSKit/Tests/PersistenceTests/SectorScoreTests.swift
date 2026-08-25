import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SectorScoreTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    private var august: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    }

    @Test func aScoreRoundTripsThroughTheStore() throws {
        let context = try makeContext()
        let evidence = Evidence([
            EvidenceRow(label: "journal entries", value: "5", normalised: 0.42)
        ])
        let score = SectorScore(sector: .soul, month: august, proposedScore: 4)
        score.archivedEvidence = evidence
        context.insert(score)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SectorScore>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.sector == .soul)
        #expect(fetched.first?.archivedEvidence == evidence)
    }

    /// The gap between the two is the most interesting signal in the system.
    /// Collapsing them into one column would destroy it.
    @Test func theUserScoreIsSeparateFromTheProposal() throws {
        let context = try makeContext()
        let score = SectorScore(sector: .body, month: august, proposedScore: 8)
        score.userScore = 5
        context.insert(score)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SectorScore>()).first
        #expect(fetched?.proposedScore == 8)
        #expect(fetched?.userScore == 5)
    }

    @Test func anUnscoredSectorHasNoUserScore() throws {
        let score = SectorScore(sector: .romance, month: august, proposedScore: nil)
        #expect(score.userScore == nil)
        #expect(score.closedAt == nil)
    }

    /// A score recorded on 3 September for August must store 1 August.
    @Test func aMonthIsNormalisedToItsFirstDay() {
        let calendar = Calendar.current
        let thirdOfSeptember = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 3, hour: 14)
        )!
        let normalised = Date.startOfMonth(thirdOfSeptember)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: normalised)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 1)
        #expect(parts.hour == 0)
    }

    @Test func aCheckInAnswerRoundTrips() throws {
        let context = try makeContext()
        context.insert(CheckInAnswer(
            sector: .friends, month: august,
            questionID: "friends.seen", answer: "3"
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CheckInAnswer>()).first
        #expect(fetched?.sector == .friends)
        #expect(fetched?.questionID == "friends.seen")
        #expect(fetched?.answer == "3")
    }
}
