#if DEBUG
import SwiftUI
import DesignSystem

/// Fixture pages for the editorial theme, mounted by `--design-preview` with
/// `--page=money` or `--page=nav`. Nothing here touches a store or a network:
/// every figure is invented, which is exactly why it never ships.
struct EditorialDesignPreview: View {
    let page: String
    @State private var tab = 2

    var body: some View {
        switch page {
        case "nav":
            ZStack(alignment: .bottom) {
                LifeOSTokens.canvas.resolve(.light).ignoresSafeArea()
                PillNavBar(selection: $tab, items: [
                    PillNavItem(value: 0, systemImage: "sun.max.fill", label: "Today"),
                    PillNavItem(value: 1, systemImage: "heart.fill", label: "Health"),
                    PillNavItem(value: 2, systemImage: "dollarsign", label: "Money"),
                    PillNavItem(value: 3, systemImage: "text.book.closed.fill", label: "Notes"),
                    PillNavItem(value: 4, systemImage: "square.grid.2x2.fill", label: "Life"),
                ])
                .padding(.bottom, 24)
            }
        // The phone shell with a field focused, so the keyboard is up: the
        // bar must not sit on top of it.
        case "nav-keyboard":
            ZStack(alignment: .bottomTrailing) {
                KeyboardFixture()
                PillNavBar(selection: $tab, items: [
                    PillNavItem(value: 0, systemImage: "sun.max.fill", label: "Today"),
                    PillNavItem(value: 1, systemImage: "heart.fill", label: "Health"),
                    PillNavItem(value: 2, systemImage: "dollarsign", label: "Money"),
                    PillNavItem(value: 3, systemImage: "text.book.closed.fill", label: "Notes"),
                    PillNavItem(value: 4, systemImage: "square.grid.2x2.fill", label: "Life"),
                ])
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .tucksUnderKeyboard()
            }
        default:
            NavigationStack { MoneyScreen(snapshot: Self.money) }
        }
    }

    /// A page of writing with the field focused on appear.
    private struct KeyboardFixture: View {
        @State private var text = "Groceries for the week, and a call to the dentist before Friday."
        @FocusState private var focused: Bool
        var body: some View {
            ZStack {
                LifeOSTokens.canvas.resolve(.light).ignoresSafeArea()
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(22)
            }
            .task { try? await Task.sleep(for: .milliseconds(400)); focused = true }
        }
    }

    static var money: MoneySnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let rows: [(String, String?, Double, Int)] = [
            ("Whole Foods", "Groceries", -86.42, 0), ("Payroll", "Income", 3120.00, 1),
            ("Spotify", "Subscriptions", -11.99, 2), ("Uber", "Transport", -23.18, 2),
            ("Blue Bottle", "Coffee", -6.75, 3), ("Con Edison", "Utilities", -94.30, 4),
            ("Trader Joe's", "Groceries", -54.10, 5), ("Netflix", "Subscriptions", -15.49, 6),
        ]
        let recent = rows.map { merchant, category, amount, daysAgo in
            MoneyRow(id: UUID(), merchant: merchant, category: category, amount: amount,
                     date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, pending: daysAgo == 0,
                     accountName: "Everyday Checking")
        }
        let categories = [
            CategoryRow(id: "rent", name: "Rent", amount: 1450, share: 0.58, count: 1),
            CategoryRow(id: "groceries", name: "Groceries", amount: 412.36, share: 0.16, count: 9),
            CategoryRow(id: "transport", name: "Transport", amount: 188.40, share: 0.08, count: 12),
            CategoryRow(id: "subscriptions", name: "Subscriptions", amount: 96.45, share: 0.04, count: 6),
            CategoryRow(id: "coffee", name: "Coffee", amount: 61.25, share: 0.02, count: 11),
        ]
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let week = (0..<7).map { offset -> DaySpend in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            return DaySpend(date: date, amount: [42, 118, 16, 74, 9, 0, 0][offset],
                            isFuture: date > today, isToday: calendar.isDate(date, inSameDayAs: today))
        }
        var snapshot = MoneySnapshot(
            income: 5240.00, expenses: 2496.31, net: 2743.69, savingsRate: 0.52, netWorth: 18420.77,
            recent: recent,
            budgets: [
                BudgetBandRow(id: UUID(), name: "Groceries", limit: 450, spent: 412.36),
                BudgetBandRow(id: UUID(), name: "Eating out", limit: 200, spent: 236.80),
            ],
            unclaimed: [UnclaimedBandRow(id: "coffee", label: "Coffee", amount: 61.25, count: 11)],
            categories: categories,
            recurring: [
                RecurringRow(id: "spotify", merchant: "Spotify", category: "Subscriptions", amount: 11.99, months: 14),
                RecurringRow(id: "netflix", merchant: "Netflix", category: "Subscriptions", amount: 15.49, months: 9),
                RecurringRow(id: "gym", merchant: "Equinox", category: "Fitness", amount: 68.00, months: 6),
            ],
            week: week,
            spendCount: 41,
            goal: SavingsGoal(name: "Japan trip", target: 4000, saved: 2650),
            monthLabel: today.formatted(.dateTime.month(.wide)),
            isConnected: true, hasConnectedBank: true, lastSyncedAt: .now.addingTimeInterval(-900)
        )
        snapshot.slices = categories.enumerated().map { index, row in
            CategorySlice(id: row.id, name: row.name, amount: row.amount, share: row.share,
                          opacity: CategorySlice.steps[index], isOther: false)
        }
        return snapshot
    }
}
#endif
