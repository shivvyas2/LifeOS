import Foundation
import SwiftData
import Persistence
import Sectors

/// Drives the Life board. Follows the same shape as `MoneyViewModel` and its
/// siblings: `attach(_:)` hands over the context once, `load()` refreshes from
/// it, and `RootView` owns the instance and calls both.
///
/// Deliberately thin. There is no test target for the app, so nothing put
/// here can be unit tested; the header math (`BoardSummary`) and the
/// cold-start fallback (`CloseSchedule`) both live in the `Sectors` package,
/// where they are.
@MainActor @Observable
final class LifeBoardViewModel {
    /// One month's score in a sector's history strip; nil is a gap, never zero.
    struct MonthValue: Equatable, Identifiable {
        let id: Date
        let value: Double?
    }

    /// Which month the board is showing. Closed is the month that has ended
    /// and been scored; in flight is the one being lived, where a sector has
    /// a range rather than a number.
    enum BoardMode: String, CaseIterable, Identifiable {
        case closed, inFlight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .closed:   "Last close"
            case .inFlight: "This month"
            }
        }
    }

    struct Card: Identifiable {
        let sector: LifeSector
        let score: Int?
        let history: [MonthValue]
        let band: SectorBand?
        var id: LifeSector { sector }
    }

    private(set) var cards: [Card] = []
    private(set) var summary = BoardSummary(scores: [:], previous: [:])
    private(set) var monthAwaitingClose: Date?
    /// The month the board is looking at, for the masthead.
    private(set) var month: Date = .now
    /// The month the last close belongs to, or nil when nothing was ever closed.
    private(set) var lastClosedMonth: Date?
    /// Opens on the month in progress: it is the mode with something to do.
    var mode: BoardMode = .inFlight {
        didSet { if mode != oldValue { load() } }
    }
    /// Nil in closed mode. Carries the days left the in-flight header shows.
    private(set) var progress: MonthProgress?

    private var context: ModelContext?
    private let calendar: Calendar

    /// The mean share of the board that can no longer move. Sectors with no
    /// band are left out rather than counted as undecided: a sector nobody
    /// has any evidence for says nothing about how settled the month is.
    var meanDecided: Double? {
        let decided = cards.compactMap { $0.band?.decided }
        guard !decided.isEmpty else { return nil }
        return decided.reduce(0, +) / Double(decided.count)
    }

    var headline: BoardHeadline {
        switch mode {
        case .closed:
            BoardHeadline.closed(month: month, lastClosed: lastClosedMonth, summary: summary)
        case .inFlight:
            BoardHeadline.inFlight(month: month, remainingDays: progress?.remainingDays ?? 0,
                                   meanDecided: meanDecided)
        }
    }

    /// Nothing closed and nothing read: the deck would be nine dashes.
    var isBlank: Bool {
        lastClosedMonth == nil && cards.allSatisfy { $0.score == nil && $0.band?.floor == nil }
    }

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// Closed shows the most recently completed month, comparing it against
    /// the one before that. In flight shows the month still being lived, as
    /// a band per sector rather than a single score. `mode` picks between
    /// them; both read from the same `thisMonth` anchor below.
    func load(now: Date = .now) {
        guard let context else { return }
        let store = SectorStore(context: context, calendar: calendar)

        let thisMonth = Date.startOfMonth(now, calendar: calendar)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let monthBefore = calendar.date(byAdding: .month, value: -2, to: thisMonth) ?? thisMonth

        let current = scoreMap(store: store, month: lastMonth)
        let previous = scoreMap(store: store, month: monthBefore)
        month = thisMonth
        lastClosedMonth = current.isEmpty ? nil : lastMonth
        summary = BoardSummary(scores: current, previous: previous)

        monthAwaitingClose = CloseSchedule.monthAwaitingClose(
            scoredCounts: (try? store.scoredCounts(before: thisMonth)) ?? [:],
            previousMonth: lastMonth,
            scoredSectorsInPreviousMonth: current.count,
            calendar: calendar
        )

        switch mode {
        case .closed:
            progress = nil
            cards = LifeSector.boardOrder.map { sector in
                let history = (try? store.history(sector: sector, months: 6)) ?? []
                return Card(
                    sector: sector,
                    score: current[sector],
                    history: history.map { MonthValue(id: $0.month, value: $0.userScore.map(Double.init)) },
                    band: nil
                )
            }

        case .inFlight:
            let window = MonthWindow(for: thisMonth, calendar: calendar)
            let inFlight = MonthProgress(window: window, now: now, calendar: calendar)
            progress = inFlight

            let inputs = (try? MonthInputsLoader.load(
                context: context, month: thisMonth, now: now, calendar: calendar
            )) ?? MonthInputs()

            cards = LifeSector.boardOrder.map { sector in
                var answers: [String: String] = [:]
                for stored in (try? store.answers(sector: sector, month: thisMonth)) ?? [] {
                    answers[stored.questionID] = stored.answer
                }
                let history = (try? store.history(sector: sector, months: 6)) ?? []
                return Card(
                    sector: sector,
                    score: nil,
                    history: history.map { MonthValue(id: $0.month, value: $0.userScore.map(Double.init)) },
                    band: SectorBand.band(
                        for: sector, inputs: inputs, progress: inFlight,
                        answers: answers, calendar: calendar
                    )
                )
            }
        }
    }

    private func scoreMap(store: SectorStore, month: Date) -> [LifeSector: Int] {
        let rows = (try? store.scores(forMonth: month)) ?? []
        return rows.reduce(into: [:]) { map, row in
            if let userScore = row.userScore { map[row.sector] = userScore }
        }
    }
}
