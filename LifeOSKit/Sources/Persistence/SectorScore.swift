import Foundation
import SwiftData

public extension Date {
    /// The first instant of the month a date falls in.
    ///
    /// Every sector row is keyed by this, so closing August on 3 September
    /// files the score under 1 August rather than under the day it was typed.
    ///
    /// The primary path reconstructs the date from year and month components.
    /// The fallback preserves the invariant by calculating back from the day of month,
    /// since it should never actually be reached in practice.
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        if let reconstructed = calendar.date(from: parts) {
            return reconstructed
        }

        // Fallback: subtract (day - 1) from the start of the current day
        // to ensure we land on the first of the month even if date reconstruction fails.
        let dayOfMonth = calendar.component(.day, from: date)
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(dayOfMonth - 1), to: startOfDay) ?? startOfDay
    }
}

/// One sector, scored for one month.
///
/// `proposedScore` and `userScore` are both kept, permanently. The distance
/// between what the rule computed and what the person actually felt is the
/// most interesting number here, and averaging them would erase it.
@Model
public final class SectorScore {
    public var sectorRaw: String
    /// Always the first day of the month being scored.
    public private(set) var month: Date
    /// What the rule said, or nil when there was no evidence at all.
    public var proposedScore: Int?
    /// What the person said. Nil until they pass through this sector.
    public var userScore: Int?
    public var closedAt: Date?

    /// The rows behind the proposal, frozen at close time.
    ///
    /// Archived rather than recomputed: change a goal in March and February's
    /// reasoning must still read the way it did in February.
    public var evidenceData: Data?

    public var sector: LifeSector {
        get { LifeSector(rawValue: sectorRaw) ?? .body }
        set { sectorRaw = newValue.rawValue }
    }

    public var archivedEvidence: Evidence {
        get {
            guard let evidenceData,
                  let decoded = try? JSONDecoder().decode(Evidence.self, from: evidenceData)
            else { return Evidence() }
            return decoded
        }
        set { evidenceData = try? JSONEncoder().encode(newValue) }
    }

    /// A sector the person has actually passed through and answered.
    public var isScored: Bool { userScore != nil }

    public init(sector: LifeSector, month: Date, proposedScore: Int?) {
        self.sectorRaw = sector.rawValue
        self.month = Date.startOfMonth(month)
        self.proposedScore = proposedScore
        self.userScore = nil
        self.closedAt = nil
        self.evidenceData = nil
    }
}

/// One answer to one check-in question, for one sector-month.
///
/// Stored as text whatever the question's shape, because the value of these
/// is comparison against last month rather than arithmetic.
@Model
public final class CheckInAnswer {
    public var sectorRaw: String
    public private(set) var month: Date
    public var questionID: String
    public var answer: String
    public var createdAt: Date

    public var sector: LifeSector {
        get { LifeSector(rawValue: sectorRaw) ?? .body }
        set { sectorRaw = newValue.rawValue }
    }

    public init(sector: LifeSector, month: Date, questionID: String, answer: String) {
        self.sectorRaw = sector.rawValue
        self.month = Date.startOfMonth(month)
        self.questionID = questionID
        self.answer = answer
        self.createdAt = .now
    }
}
