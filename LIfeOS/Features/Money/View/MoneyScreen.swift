import SwiftUI
import DesignSystem

struct MoneyScreen: View {
    let snapshot: MoneySnapshot
    var onAdd: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        GradientCanvas(hue: .money) {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    if snapshot.isConnected {
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
            Text("Plaid sync arrives in a later slice.")
                .font(.footnote)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
        .padding(.top, 40)
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
        monthLabel: "August 2026", isConnected: true
    ))
}

#Preview("Empty") {
    MoneyScreen(snapshot: MoneySnapshot())
}
