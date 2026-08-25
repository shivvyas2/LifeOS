import Foundation
import SwiftData

/// Reads and writes sector scores and their check-in answers.
///
/// Follows `PlanStore` and `MoneyStore`: a `@MainActor` value type over a
/// context, with the calendar injected so tests are not at the mercy of the
/// machine's locale.
@MainActor
public struct SectorStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func scores(forMonth month: Date) throws -> [SectorScore] {
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<SectorScore>(predicate: #Predicate { $0.month == key })
        )
    }

    public func score(_ sector: LifeSector, month: Date) throws -> SectorScore? {
        let raw = sector.rawValue
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.month == key }
            )
        ).first
    }

    /// Writes a proposal, creating the row if it is new.
    ///
    /// A sector already decided is returned untouched. Recomputing is routine,
    /// and once a person has scored a month both their number and the reasoning
    /// they saw are history: rewriting either would make the archive lie.
    @discardableResult
    public func record(
        sector: LifeSector, month: Date, proposed: Int?, evidence: Evidence
    ) throws -> SectorScore {
        if let existing = try score(sector, month: month) {
            guard !existing.isScored else { return existing }
            existing.proposedScore = proposed
            existing.archivedEvidence = evidence
            try context.save()
            return existing
        }
        let created = SectorScore(sector: sector, month: month, proposedScore: proposed)
        created.archivedEvidence = evidence
        context.insert(created)
        try context.save()
        return created
    }

    public func commit(userScore: Int, to score: SectorScore) throws {
        score.userScore = userScore
        score.closedAt = .now
        try context.save()
    }

    /// The last `months` scored entries for a sector, oldest first, for the
    /// board sparkline.
    public func history(sector: LifeSector, months: Int) throws -> [SectorScore] {
        let raw = sector.rawValue
        let all = try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.userScore != nil },
                sortBy: [SortDescriptor(\.month)]
            )
        )
        return Array(all.suffix(months))
    }

    /// The earliest month that still has an unscored sector.
    ///
    /// Deliberately the oldest rather than the most recent: skipping August
    /// must not bury it under September, or the gap is lost silently.
    public func oldestUnclosedMonth(before limit: Date) throws -> Date? {
        let key = Date.startOfMonth(limit, calendar: calendar)
        let open = try context.fetch(
            FetchDescriptor<SectorScore>(
                predicate: #Predicate { $0.month < key && $0.userScore == nil },
                sortBy: [SortDescriptor(\.month)]
            )
        )
        return open.first?.month
    }

    public func answers(sector: LifeSector, month: Date) throws -> [CheckInAnswer] {
        let raw = sector.rawValue
        let key = Date.startOfMonth(month, calendar: calendar)
        return try context.fetch(
            FetchDescriptor<CheckInAnswer>(
                predicate: #Predicate { $0.sectorRaw == raw && $0.month == key },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    /// One answer per question per sector-month. Answering again replaces.
    public func saveAnswer(
        sector: LifeSector, month: Date, questionID: String, answer: String
    ) throws {
        let existing = try answers(sector: sector, month: month)
            .first { $0.questionID == questionID }
        if let existing {
            existing.answer = answer
        } else {
            context.insert(CheckInAnswer(
                sector: sector, month: month, questionID: questionID, answer: answer
            ))
        }
        try context.save()
    }
}
