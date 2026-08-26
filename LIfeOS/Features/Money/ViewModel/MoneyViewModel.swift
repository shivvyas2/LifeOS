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

    #if DEBUG
    /// Shared with the Settings toggle that writes it. Delete alongside
    /// `SampleMoneyData.swift` when Plaid lands.
    static let sampleDataKey = "useSampleFinanceData"
    #endif

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load(connection: PlaidConnectionViewModel? = nil) {
        #if DEBUG
        // Off unless deliberately switched on in Settings. Release builds do not
        // compile `SampleMoneyData` at all, so this branch cannot exist there.
        if UserDefaults.standard.bool(forKey: Self.sampleDataKey) {
            snapshot = .sample
            return
        }
        #endif
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)

        do {
            let entries = try store.monthEntries()
            let accounts = try store.accounts()
            let summary = summarise(entries: entries, accounts: accounts)

            let bankNames: [String]
            var reconnect: String?
            switch connection?.state {
            case .connected(let names): bankNames = names
            case .needsReconnect(let name): bankNames = [name]; reconnect = name
            default: bankNames = []
            }

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
                // A bank linked seconds ago has no transactions yet. Falling back
                // to the empty state there tells the user the connection failed
                // when it did not.
                isConnected: !entries.isEmpty || !accounts.isEmpty || !bankNames.isEmpty,
                hasConnectedBank: !bankNames.isEmpty,
                isFetchingHistory: connection?.isFetchingHistory ?? false,
                reconnectPrompt: reconnect,
                lastSyncedAt: connection?.lastSyncedAt
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
