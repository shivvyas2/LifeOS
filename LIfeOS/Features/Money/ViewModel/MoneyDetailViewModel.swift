import Foundation
import SwiftData
import Persistence
import Insights

/// Six months of one category or one merchant.
///
/// Its own view model rather than more fields on `MoneyViewModel`, which
/// loads one month on every save in the app. Six months of rows for a page
/// nobody is looking at is the kind of work that makes a tab feel slow.
@MainActor @Observable
final class MoneyDetailViewModel {
    private(set) var snapshot = MoneyDetailSnapshot()

    private var context: ModelContext?
    private let calendar: Calendar

    static let monthCount = 6

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load(_ filter: MoneyDetailFilter, now: Date = .now) {
        guard let context,
              let month = calendar.dateInterval(of: .month, for: now),
              let start = calendar.date(byAdding: .month, value: -(Self.monthCount - 1), to: month.start)
        else { return }
        let store = MoneyStore(context: context, calendar: calendar)

        do {
            let all = try store.entries(from: start, to: now)
            let logos = MoneyViewModel.logoMap(from: all)
            let resolver = try store.cardResolver()
            let cards = MoneyViewModel.cardIndex(accounts: try store.accounts())
            let matching = all.filter { Self.matches($0, filter, resolver: resolver) }
            let spend = matching.filter(\.isSpending)
            let thisMonth = matching.filter { $0.date >= month.start }
            let spentThisMonth = spend.filter { $0.date >= month.start }

            let months = SpendSeries.months(
                endingIn: now, count: Self.monthCount,
                lines: spend.map { SpendSeries.Line(amount: $0.amount, date: $0.date) },
                calendar: calendar
            )
            let completed = months.dropLast().map(\.amount).filter { $0 > 0 }

            snapshot = MoneyDetailSnapshot(
                filter: filter,
                logoURL: matching.lazy.compactMap { MoneyViewModel.logo(for: $0, in: logos) }.first,
                category: thisMonth.first?.category ?? matching.first?.category,
                monthTotal: spentThisMonth.reduce(0) { $0 + abs($1.amount) },
                monthCount: spentThisMonth.count,
                months: months.enumerated().map { index, total in
                    MonthSpend(monthStart: total.monthStart, amount: total.amount,
                               isCurrent: index == months.count - 1)
                },
                average: completed.isEmpty ? nil : completed.reduce(0, +) / Double(completed.count),
                transactions: MoneyViewModel.rows(from: thisMonth, logos: logos,
                                                  resolver: resolver, cards: cards),
                monthLabel: now.formatted(.dateTime.month(.wide).year()),
                card: { if case .card(let key, _) = filter { cards[key] } else { nil } }()
            )
        } catch {
            assertionFailure("Money detail load failed: \(error)")
        }
    }

    /// A category page matches on the display label the list was grouped by,
    /// so "Uncategorised" opens the rows with no category. A merchant page
    /// matches the name, case-insensitively, since the ledger showed it. A
    /// card page matches the card after the person's choices are applied.
    static func matches(_ entry: MoneyEntry, _ filter: MoneyDetailFilter,
                        resolver: CardResolver = CardResolver()) -> Bool {
        switch filter {
        case .card(let key, _):
            resolver.cardKey(for: entry) == key
        case .category(let name):
            (entry.category ?? "Uncategorised") == name && entry.amount < 0
        case .merchant(let name):
            entry.merchant.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
