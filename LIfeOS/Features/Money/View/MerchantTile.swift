import SwiftUI
import DesignSystem

/// What a detail page is about. A category page and a merchant page are the
/// same page with a different predicate, so one type carries both.
enum MoneyDetailFilter: Hashable, Identifiable {
    case category(String)
    case merchant(String)

    var id: String {
        switch self {
        case .category(let name): "category:\(name)"
        case .merchant(let name): "merchant:\(name)"
        }
    }

    var title: String {
        switch self {
        case .category(let name), .merchant(let name): name
        }
    }
}

/// The mark beside a merchant: Plaid's logo in a paper-white circle, or the
/// category glyph when there is none.
///
/// A white circle on every band rather than the logo bare, because Plaid's
/// PNGs come on whatever background the merchant chose and a row of mixed
/// squares breaks the band. The circle also gives the glyph fallback the
/// same footprint, so a list with and without logos lines up.
struct MerchantTile: View {
    let logoURL: URL?
    let glyph: String
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(MoneyPalette.paper.resolve(scheme))
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(MoneyPalette.ink.resolve(scheme).opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: glyph)
            .font(LifeOSType.label.weight(.semibold))
            .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.75))
    }
}

/// One transaction, as the ledger and the detail page both draw it.
struct MoneyTransactionRow: View {
    let row: MoneyRow
    var onOpen: ((MoneyDetailFilter) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let onOpen {
            Button { onOpen(.merchant(row.merchant)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every charge from \(row.merchant)")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Space.x2 - 4) {
            MerchantTile(logoURL: row.logoURL, glyph: MoneyLedgerSection.glyph(for: row.category))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.merchant)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    .lineLimit(1)
                Text(detail).moneyEyebrow(scheme).lineLimit(1)
            }
            Spacer(minLength: Space.x1)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyFigure(amount: row.amount, size: 18, showsSign: true)
                    .opacity(row.pending ? 0.45 : 1)
                if row.pending {
                    Text("Pending").moneyEyebrow(scheme)
                }
            }
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x1 + 2)
        .frame(maxWidth: .infinity)
        .background(MoneyPalette.stone.resolve(scheme))
        .contentShape(Rectangle())
    }

    private var detail: String {
        [row.category ?? "Uncategorised", row.accountName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Rows grouped by day, most recent day first, with the label the header
/// shows: "Today", "Yesterday", then the weekday and date.
enum MoneyDayGroup {
    static func group(_ rows: [MoneyRow], calendar: Calendar = .current,
                      now: Date = .now) -> [(label: String, rows: [MoneyRow])] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let label: String
            if day == today {
                label = "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      day == yesterday {
                label = "Yesterday"
            } else {
                label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return (label, grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}
