import Foundation
import Persistence

/// The Life board's masthead, worked out once from what the board knows.
///
/// A value rather than view code so the wording is tested: the singular
/// "1 day left", the missing fact that is left out rather than rendered as
/// "Lowest: " with nothing after it.
public struct BoardHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String?

    public init(eyebrow: String, title: String, detail: String?) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    /// Closed mode: which month was closed last, and the two board facts.
    public static func closed(
        month: Date, lastClosed: Date?, summary: BoardSummary, locale: Locale = .current
    ) -> BoardHeadline {
        let title = lastClosed.map { "\(monthName($0, locale: locale)) closed" } ?? "Nothing closed yet"
        var facts: [String] = []
        if let lowest = summary.lowest { facts.append("Lowest: \(lowest.title)") }
        if let mover = summary.biggestMover {
            facts.append("Biggest move: \(mover.sector.title) \(mover.delta > 0 ? "+" : "")\(mover.delta)")
        }
        return BoardHeadline(eyebrow: eyebrow(month, locale: locale), title: title,
                             detail: facts.isEmpty ? nil : facts.joined(separator: " · "))
    }

    /// In flight: how much of the month is left, and how much is settled.
    public static func inFlight(
        month: Date, remainingDays: Int, meanDecided: Double?, locale: Locale = .current
    ) -> BoardHeadline {
        let title = remainingDays == 1 ? "1 day left" : "\(remainingDays) days left"
        let detail = meanDecided.map { "\(Int(($0 * 100).rounded()))% of this month is decided" }
        return BoardHeadline(eyebrow: eyebrow(month, locale: locale), title: title, detail: detail)
    }

    private static func eyebrow(_ month: Date, locale: Locale) -> String {
        "Life · \(monthName(month, locale: locale))"
    }

    private static func monthName(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale).month(.wide))
    }
}
