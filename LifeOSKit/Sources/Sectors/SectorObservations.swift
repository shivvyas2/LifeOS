import Foundation

/// Short computed remarks about a sector's history.
///
/// Deliberately rules rather than model prose, matching the spine's decision
/// that the rule owns what is asserted. That also keeps this screen free and
/// instant, with no model call at all.
///
/// Every rule needs three consecutive months. Two of anything is a
/// coincidence, and a remark that fires on a coincidence teaches the reader to
/// ignore remarks. "Consecutive" means calendar-adjacent, not merely the last
/// three entries in `months`: a partial close can leave a sector unscored for
/// a month, and three entries spread across a longer stretch of real time are
/// not three months running.
public enum SectorObservations {
    private static let run = 3

    public static func all(
        months: [MonthEntry], questions: [QuestionTrack], calendar: Calendar = .current
    ) -> [String] {
        guard isConsecutiveRun(months, calendar: calendar) else { return [] }
        return questions.compactMap(repeatedAnswer) + [standingGap(months)].compactMap { $0 }
    }

    /// Whether the last three months are calendar-adjacent.
    ///
    /// `SectorStore.history` keeps only months with a `userScore`, and a
    /// partial close that leaves a sector unscored one month is the ordinary
    /// shape of a partial close, not a rare failure state. Without this
    /// check, skipping a sector in the middle month would let three months
    /// spread across a longer stretch of calendar time read as "three months
    /// running". `QuestionTrack.answers` is index-aligned to `months`, so
    /// this single check on `months` gates both rules below.
    static func isConsecutiveRun(_ months: [MonthEntry], calendar: Calendar) -> Bool {
        let tail = months.suffix(run)
        guard tail.count == run else { return false }
        let dates = Array(tail.map(\.month))
        return zip(dates, dates.dropFirst()).allSatisfy { earlier, later in
            guard let next = calendar.date(byAdding: .month, value: 1, to: earlier) else {
                return false
            }
            return calendar.isDate(next, equalTo: later, toGranularity: .month)
        }
    }

    /// The same answer, three months running, ending at the most recent month.
    static func repeatedAnswer(_ track: QuestionTrack) -> String? {
        let tail = track.answers.suffix(run)
        guard tail.count == run,
              let first = tail.first ?? nil,
              tail.allSatisfy({ $0 == first })
        else { return nil }
        return "You have said \"\(first)\" three months running."
    }

    /// The person scoring themselves below the rule, three months running.
    ///
    /// This is the signal the spine kept `proposedScore` and `userScore` in
    /// separate columns to preserve: the rule is measuring something the person
    /// does not feel.
    static func standingGap(_ months: [MonthEntry]) -> String? {
        let tail = months.suffix(run)
        guard tail.count == run else { return nil }
        // A month the rule could not propose for is not evidence either way,
        // so it breaks the run rather than being skipped over.
        guard tail.allSatisfy({ entry in
            guard let proposed = entry.proposedScore else { return false }
            return entry.userScore < proposed
        }) else { return nil }
        return "You have scored this lower than the app for three months running."
    }
}
