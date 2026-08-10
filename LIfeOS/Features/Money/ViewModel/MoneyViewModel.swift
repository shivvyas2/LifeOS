import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class MoneyViewModel {
    private(set) var snapshot = MoneySnapshot()

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load() {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)

        do {
            let entries = try store.monthEntries()
            let accounts = try store.accounts()
            let summary = summarise(entries: entries, accounts: accounts)

            snapshot = MoneySnapshot(
                income: summary.income,
                expenses: summary.expenses,
                net: summary.net,
                savingsRate: summary.savingsRate,
                netWorth: summary.netWorth,
                recent: entries.prefix(8).map {
                    MoneyRow(id: $0.id, merchant: $0.merchant, category: $0.category,
                             amount: $0.amount, date: $0.date, pending: $0.pending)
                },
                monthLabel: Date.now.formatted(.dateTime.month(.wide).year()),
                isConnected: !entries.isEmpty || !accounts.isEmpty
            )
        } catch {
            assertionFailure("Money load failed: \(error)")
        }
    }

    /// Manual entry until Plaid is wired. `isIncome` decides the sign here so
    /// the rest of the app never has to guess at a bare number's direction.
    func add(merchant: String, amount: Double, isIncome: Bool, category: String?) {
        guard let context, !merchant.isEmpty, amount > 0 else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).add(
                date: .now,
                amount: isIncome ? amount : -amount,
                merchant: merchant,
                category: category
            )
            load()
        } catch {
            assertionFailure("Money add failed: \(error)")
        }
    }
}
