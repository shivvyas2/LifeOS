import SwiftUI
import DesignSystem

struct MoneyScreen: View {
    let snapshot: MoneySnapshot
    var onAdd: () -> Void = {}
    var onConnect: () -> Void = {}
    var onSync: () -> Void = {}
    var onEditBudgets: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        GradientCanvas(hue: .money) {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    if snapshot.reconnectPrompt != nil { reconnectBanner }

                    if snapshot.isFetchingHistory && snapshot.recent.isEmpty {
                        fetchingState
                    } else if snapshot.isConnected {
                        HStack(spacing: 10) {
                            MetricTile(label: "Income", value: Self.money(snapshot.income))
                            MetricTile(label: "Expenses", value: Self.money(snapshot.expenses))
                            MetricTile(
                                label: "Saved",
                                value: snapshot.savingsRate.map { "\(Int($0 * 100))" },
                                unit: "%"
                            )
                        }

                        if let netWorth = snapshot.netWorth {
                            SoftCard {
                                HStack {
                                    Text("Net worth").font(.system(size: 15, weight: .medium))
                                    Spacer()
                                    Text(Self.money(netWorth) ?? "—")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                        }

                        budgetsBand

                        transactions
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.bottom, layout.contentBottomInset)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            if snapshot.isSample { sampleBadge }

            if snapshot.isConnected {
                HeroNumeral(
                    value: Self.money(snapshot.net) ?? "—",
                    label: "Net · \(snapshot.monthLabel)"
                )
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.top, 26)

                Text(snapshot.verdict)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme)))
            }
        }
    }

    /// Above the numbers, not below them, and never dismissible. Every figure
    /// on this screen is invented while it shows, and a reader who scrolls
    /// straight to their net for the month must meet this first.
    private var sampleBadge: some View {
        HStack(spacing: Space.half + 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Sample data. These numbers are made up.")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.05))
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(scheme == .dark ? 0.22 : 0.5))
        )
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
    }

    private var transactions: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("RECENT")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button("Add", action: onAdd)
                        .font(.system(size: 13, weight: .semibold))
                        .tint(LifeOSTokens.accent)
                }

                ForEach(snapshot.recent) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.merchant).font(.system(size: 15, weight: .medium))
                            if let category = row.category {
                                Text(category).font(.system(size: 12)).opacity(0.5)
                            }
                        }
                        Spacer()
                        Text(Self.signed(row.amount))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(row.amount >= 0 ? Color.green : Color.primary)
                            .opacity(row.pending ? 0.45 : 1)
                    }
                }
            }
        }
    }

    private var budgetsBand: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("BUDGETS")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button(snapshot.budgets.isEmpty ? "Set budgets" : "Edit", action: onEditBudgets)
                        .font(.system(size: 13, weight: .semibold))
                        .tint(LifeOSTokens.accent)
                }

                if snapshot.budgets.isEmpty {
                    Text("Set a monthly limit for the spending you care about.")
                        .font(.footnote)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                ForEach(snapshot.budgets) { row in
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.name).font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("\(Self.money(row.spent) ?? "—") / \(Self.money(row.limit) ?? "—")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(row.isOver ? .orange : LifeOSTokens.primaryText.resolve(scheme))
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme))
                                Capsule()
                                    .fill(row.isOver ? Color.orange : LifeOSTokens.accent)
                                    .frame(width: proxy.size.width * row.progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                if !snapshot.unclaimed.isEmpty { unclaimedRows }
            }
        }
    }

    /// Spend no bucket claims. Always rendered when present: the point of
    /// buckets is that nothing stops counting quietly.
    private var unclaimedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UNCLAIMED")
                .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                .padding(.top, 4)
            ForEach(snapshot.unclaimed) { row in
                HStack {
                    Text(row.count > 1 ? "\(row.label) ×\(row.count)" : row.label)
                        .font(.system(size: 14))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    Spacer()
                    Text(Self.money(row.amount) ?? "—")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            Button("Assign to a bucket", action: onEditBudgets)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            HeroEmptyState(label: "Money", reason: "No transactions yet")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Button("Add a transaction", action: onAdd)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.vertical, 12)
                .padding(.horizontal, 22)
                .background(
                    Capsule()
                        .fill(LifeOSTokens.tileSurface.resolve(scheme))
                        .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 8, y: 2)
                )
            Button("Connect your bank", action: onConnect)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
        .padding(.top, 40)
    }

    /// Connected, but Plaid is still assembling the history.
    ///
    /// Plaid fetches transactions asynchronously after the login completes, so
    /// the first sync can honestly come back with nothing. Rendering that as an
    /// empty month would state, as fact, that the user spent nothing.
    private var fetchingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Fetching your transactions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text("Your bank is sending the last few months. This usually takes a minute.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Button("Check again", action: onSync)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.accent)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    private var reconnectBanner: some View {
        SoftCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.reconnectPrompt ?? "Your bank") needs you to sign in again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text("Numbers below are from your last sync.")
                        .font(.footnote)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                Spacer()
            }
        }
    }

    static func money(_ value: Double) -> String? {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static func signed(_ value: Double) -> String {
        let formatted = abs(value).formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return value >= 0 ? "+\(formatted)" : "-\(formatted)"
    }
}

#Preview("With data") {
    MoneyScreen(snapshot: MoneySnapshot(
        income: 5_200, expenses: 2_150, net: 3_050, savingsRate: 0.586, netWorth: 24_800,
        recent: [
            MoneyRow(id: UUID(), merchant: "Salary", category: "Income", amount: 5_200, date: .now, pending: false),
            MoneyRow(id: UUID(), merchant: "Rent", category: "Housing", amount: -1_500, date: .now, pending: false),
            MoneyRow(id: UUID(), merchant: "Groceries", category: "Food", amount: -650, date: .now, pending: true),
        ],
        budgets: [
            BudgetBandRow(id: UUID(), name: "Eating out", limit: 300, spent: 210),
            BudgetBandRow(id: UUID(), name: "Groceries", limit: 450, spent: 480),
        ],
        unclaimed: [UnclaimedBandRow(id: "GENERAL_MERCHANDISE", label: "Shopping", amount: 210, count: 4)],
        monthLabel: "August 2026", isConnected: true
    ))
}

#Preview("Empty") {
    MoneyScreen(snapshot: MoneySnapshot())
}
