import SwiftUI
import DesignSystem

/// One category or one merchant: what it cost this month, the six months
/// behind that, and every charge that makes it up.
///
/// Pushed from a category band, a donut slice, a recurring row or a ledger
/// row. Same bands as the tab it came from, so the push reads as the same
/// object opening rather than as arriving somewhere new.
struct MoneyDetailScreen: View {
    let filter: MoneyDetailFilter
    @Bindable var model: MoneyDetailViewModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    private var snapshot: MoneyDetailSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            MoneyBandStack {
                headline
                trend
                transactions
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .background(MoneyPalette.paper.resolve(scheme).ignoresSafeArea())
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.load(filter) }
    }

    private var headline: some View {
        MoneyBand {
            if let card = snapshot.card {
                CardFace(card: card, width: layout.isRegular ? 260 : 220)
                    .padding(.bottom, Space.x1)
            } else {
                merchantHeader
            }
            Text("This month").moneyEyebrow(scheme).padding(.top, Space.x1)
            MoneyFigure(amount: snapshot.monthTotal, size: 46)
            Text(snapshot.monthCount == 0
                 ? "Nothing in \(snapshot.monthLabel)"
                 : "\(snapshot.monthCount) charge\(snapshot.monthCount == 1 ? "" : "s") in \(snapshot.monthLabel)")
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(MoneyPalette.quietInk(scheme))
        }
    }

    private var merchantHeader: some View {
        HStack(spacing: Space.x2 - 4) {
            MerchantTile(logoURL: snapshot.logoURL,
                         glyph: MoneyLedgerSection.glyph(for: snapshot.category),
                         size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.title)
                    .font(LifeOSType.sectionTitle.weight(.bold))
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if case .merchant = filter, let category = snapshot.category {
                    Text(category).moneyEyebrow(scheme)
                }
            }
        }
    }

    private var trend: some View {
        PersistedMoneyCard(id: "trend", name: "Six months") {
            Text("Six months").moneyEyebrow(scheme)
        } content: {
            MoneyMonthsChart(months: snapshot.months, average: snapshot.average,
                             height: layout.isRegular ? 180 : 140)
                .padding(.top, Space.half)
            if let average = snapshot.average {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Averages")
                    MoneyFigure(amount: average, size: 15)
                    Text("a month before this one")
                }
                .font(LifeOSType.caption)
                .foregroundStyle(MoneyPalette.quietInk(scheme))
            } else {
                Text("First month with anything here")
                    .font(LifeOSType.caption)
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }
        }
    }

    @ViewBuilder
    private var transactions: some View {
        if snapshot.transactions.isEmpty {
            MoneyEmptyBand(line: "Nothing this month.")
        } else {
            // No tap on these rows: a merchant page opening a merchant page
            // is a loop, and two depths of the same list is one more than
            // anyone asked for.
            MoneyDayCards(rows: snapshot.transactions)
        }
    }
}
