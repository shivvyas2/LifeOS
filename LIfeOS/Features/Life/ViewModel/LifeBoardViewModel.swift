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

    struct Card: Identifiable {
        let sector: LifeSector
        let score: Int?
        let history: [MonthValue]
        var id: LifeSector { sector }
    }

    private(set) var cards: [Card] = []
    private(set) var summary = BoardSummary(scores: [:], previous: [:])
    private(set) var monthAwaitingClose: Date?

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// The month the board displays is the most recently completed one; the
    /// header and cards compare it against the month before that.
    func load(now: Date = .now) {
        guard let context else { return }
        let store = SectorStore(context: context, calendar: calendar)

        let thisMonth = Date.startOfMonth(now, calendar: calendar)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let monthBefore = calendar.date(byAdding: .month, value: -2, to: thisMonth) ?? thisMonth

        let current = scoreMap(store: store, month: lastMonth)
        let previous = scoreMap(store: store, month: monthBefore)
        summary = BoardSummary(scores: current, previous: previous)

        monthAwaitingClose = CloseSchedule.monthAwaitingClose(
            scoredCounts: (try? store.scoredCounts(before: thisMonth)) ?? [:],
            previousMonth: lastMonth,
            scoredSectorsInPreviousMonth: current.count,
            calendar: calendar
        )

        cards = LifeSector.boardOrder.map { sector in
            let history = (try? store.history(sector: sector, months: 6)) ?? []
            return Card(
                sector: sector,
                score: current[sector],
                history: history.map { MonthValue(id: $0.month, value: $0.userScore.map(Double.init)) }
            )
        }
    }

    private func scoreMap(store: SectorStore, month: Date) -> [LifeSector: Int] {
        let rows = (try? store.scores(forMonth: month)) ?? []
        return rows.reduce(into: [:]) { map, row in
            if let userScore = row.userScore { map[row.sector] = userScore }
        }
    }
}
