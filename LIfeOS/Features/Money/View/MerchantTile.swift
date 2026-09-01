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

/// One transaction, as the ledger and the detail page both draw it. Sits
/// inside a day card, which supplies the background and the side padding.
///
/// No line limit on the merchant: a bank descriptor that needs two lines
/// gets two lines. Clipping it would be the row hiding what it is for.
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

            // One line each, never two and never a word cut in half. The
            // amount is drawn at its full size first; the name takes what is
            // left, shrinks a little, and only then trails off.
            VStack(alignment: .leading, spacing: 2) {
                Text(row.merchant)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .moneyEyebrow(scheme)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: Space.x1)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyFigure(amount: row.amount, size: 18, showsSign: true)
                    .fixedSize()
                    .opacity(row.pending ? 0.45 : 1)
                if row.pending {
                    Text("Pending").moneyEyebrow(scheme).fixedSize()
                }
            }
            if onOpen != nil {
                Image(systemName: "chevron.right")
                    .font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }
        }
        .padding(.vertical, Space.x1 + 2)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var detail: String {
        [row.category ?? "Uncategorised", row.accountName].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Rows grouped by day, most recent day first, with the label the header
/// shows: "Today", "Yesterday", then the weekday and date.
enum MoneyDayGroup {
    struct Day: Identifiable {
        let date: Date
        let label: String
        let rows: [MoneyRow]

        var id: Date { date }
        /// The day's settled movement, signed: what came in minus what went
        /// out. Pending charges stay in the rows but out of this figure, the
        /// same rule the month's own totals apply, and are counted beside it.
        var settledNet: Double {
            rows.filter { !$0.pending }.reduce(0) { $0 + $1.amount }
        }
        var pendingTotal: Double {
            rows.filter(\.pending).reduce(0) { $0 + abs($1.amount) }
        }
    }

    static func group(_ rows: [MoneyRow], calendar: Calendar = .current, now: Date = .now) -> [Day] {
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
            return Day(date: day, label: label, rows: grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}

/// A card per day, each one collapsible to its header: the day and what it
/// cost. Every row of every day is always one tap from view; nothing is
/// dropped, and every day starts open.
struct MoneyDayCards: View {
    let rows: [MoneyRow]
    var onOpen: ((MoneyDetailFilter) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    /// Per visit, not persisted: a key per calendar day forever is not a
    /// preference anyone set.
    @State private var collapsedDays: Set<Date> = []

    var body: some View {
        ForEach(MoneyDayGroup.group(rows)) { day in
            MoneyCard(
                tone: MoneyPalette.stone,
                collapsed: Binding(
                    get: { collapsedDays.contains(day.date) },
                    set: { collapsed in
                        if collapsed { collapsedDays.insert(day.date) } else { collapsedDays.remove(day.date) }
                    }
                ),
                accessibilityName: day.label
            ) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.label).moneyEyebrow(scheme)
                    Text("\(day.rows.count)")
                        .font(LifeOSType.eyebrow.weight(.regular))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                    Spacer(minLength: Space.x1)
                    VStack(alignment: .trailing, spacing: 2) {
                        MoneyFigure(amount: day.settledNet, size: 15, showsSign: day.settledNet != 0)
                            .fixedSize()
                        if day.pendingTotal > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                MoneyFigure(amount: day.pendingTotal, size: 12)
                                Text("pending").moneyEyebrow(scheme)
                            }
                            .fixedSize()
                        }
                    }
                }
            } content: {
                VStack(spacing: 0) {
                    ForEach(day.rows) { row in
                        MoneyRowDivider()
                        MoneyTransactionRow(row: row, onOpen: onOpen)
                    }
                }
            }
        }
    }
}
