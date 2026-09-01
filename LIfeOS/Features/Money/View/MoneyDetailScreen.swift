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

    private var tone: AdaptiveColor {
        switch filter {
        case .category: MoneyPalette.mist
        case .merchant: MoneyPalette.mint
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headline
                trend
                transactions
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
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
        MoneyBand(tone: tone) {
            HStack(spacing: Space.x2 - 4) {
                MerchantTile(logoURL: snapshot.logoURL,
                             glyph: MoneyLedgerSection.glyph(for: snapshot.category),
                             size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.title)
                        .font(LifeOSType.sectionTitle.weight(.bold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        .lineLimit(2)
                    if case .merchant = filter, let category = snapshot.category {
                        Text(category).moneyEyebrow(scheme)
                    }
                }
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

    private var trend: some View {
        MoneyBand(tone: MoneyPalette.stone) {
            Text("Six months").moneyEyebrow(scheme)
            MoneyMonthsChart(months: snapshot.months, average: snapshot.average)
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
            MoneyEmptyBand(tone: MoneyPalette.stone, line: "Nothing this month.")
        } else {
            ForEach(MoneyDayGroup.group(snapshot.transactions), id: \.label) { day in
                Text(day.label)
                    .moneyEyebrow(scheme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.x2)
                    .padding(.top, Space.x2)
                    .padding(.bottom, Space.half)
                    .background(MoneyPalette.stone.resolve(scheme))
                ForEach(day.rows) { row in
                    // No tap: a merchant page opening a merchant page is a loop.
                    // A category page could open a merchant, but two depths of
                    // the same list is one more than anyone asked for.
                    MoneyTransactionRow(row: row)
                }
            }
            Color.clear.frame(height: Space.x1).background(MoneyPalette.stone.resolve(scheme))
        }
    }
}
