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
        let created = SectorScore(
            sector: sector, month: month, proposedScore: proposed, calendar: calendar
        )
        created.archivedEvidence = evidence
        context.insert(created)
        try context.save()
        return created
    }

    /// Decides the sector, once.
    ///
    /// `record()` returns an existing decided row rather than refusing to
    /// hand it back, which is what makes this guard load-bearing: without it,
    /// any caller that re-records a committed sector and then commits again
    /// would silently overwrite the person's decision. `advance()` never
    /// re-offers a committed sector today, but that is a property of the view
    /// model, not of the store, and the store should not depend on a caller
    /// getting that right.
    public func commit(userScore: Int, to score: SectorScore) throws {
        guard !score.isScored else { return }
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

    /// How many sectors are scored in each month that has at least one
    /// `SectorScore` row, for months before `limit`.
    ///
    /// A row is created by `record()`, which runs as soon as a sector is
    /// *shown* during a close, well before it is decided. So a month with a
    /// nil `userScore` on some of its rows is the ordinary shape of a
    /// partial close, not a rare failure state: `CloseSchedule` is what turns
    /// this into "the oldest month with a gap worth offering". A month with
    /// no rows at all is not represented here; that is not a gap, it is a
    /// month nothing has touched yet, which `CloseSchedule`'s fallback to the
    /// previous month exists to handle.
    public func scoredCounts(before limit: Date) throws -> [Date: Int] {
        let key = Date.startOfMonth(limit, calendar: calendar)
        let rows = try context.fetch(
            FetchDescriptor<SectorScore>(predicate: #Predicate { $0.month < key })
        )
        return rows.reduce(into: [Date: Int]()) { counts, row in
            counts[row.month, default: 0] += row.isScored ? 1 : 0
        }
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
                sector: sector, month: month, questionID: questionID, answer: answer,
                calendar: calendar
            ))
        }
        try context.save()
    }
}
