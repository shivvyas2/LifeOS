import SwiftUI
import DesignSystem

/// The six panels behind `MoneySectionRail`.
///
/// Each is a stack of full-bleed bands: a band owns its colour edge to edge,
/// carries one tracked label and one figure at display size, and states one
/// thing. Cards with margins were the alternative and made every section look
/// like a settings list.
///
/// Two things were added later without changing that. A band that holds a
/// chart or a list is a `MoneyCard`: its body folds under its header, and the
/// header keeps the figure, so a collapsed card still says its number. And on
/// a regular width the bands stop stacking and flow into a two-column grid
/// (`MoneyBandStack`), each with its own corners, because a single 340-point
/// column down the middle of an iPad is most of the screen saying nothing.
///
/// Split out of `MoneyScreen` because six panels in one file was a thousand
/// lines and every edit meant scrolling past five sections to reach the sixth.

// MARK: - Band

/// The unit every section is built from.
struct MoneyBand<Content: View>: View {
    let tone: AdaptiveColor
    var minHeight: CGFloat = 0
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .top)
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x2)
        .background(tone.resolve(scheme))
        // In the grid each band is its own card and needs its own corners.
        // Stacked, the section is clipped as one block and a rounded band
        // inside it would show the paper through the gap.
        .clipShape(RoundedRectangle(cornerRadius: layout.isRegular ? Radius.medium : 0,
                                    style: .continuous))
    }
}

/// How a section lays its bands out: one column on a phone, an adaptive
/// grid on a regular width. Every child is one cell, so a list that must
/// stay together (a day of transactions) is wrapped in a single card first.
struct MoneyBandStack<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.layout) private var layout

    var body: some View {
        if layout.isRegular {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 340, maximum: 620), spacing: Space.x1)],
                alignment: .leading,
                spacing: Space.x1
            ) {
                content
            }
        } else {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

/// A band whose body folds away under its header.
///
/// The header is always the whole story in one line: the eyebrow and the
/// figure. What folds is the thing under it, the chart or the list. Nothing
/// is dropped by collapsing; it is hidden until the header is tapped again,
/// and every card starts open.
struct MoneyCard<Header: View, Body: View>: View {
    let tone: AdaptiveColor
    @Binding var collapsed: Bool
    var accessibilityName: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Body
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MoneyBand(tone: tone) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: Space.x1) {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        header
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(collapsed ? "Shows the detail" : "Hides the detail")

            if !collapsed {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggle() {
        if reduceMotion {
            collapsed.toggle()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                collapsed.toggle()
            }
        }
    }
}

/// A `MoneyCard` that remembers whether it was left collapsed. For the
/// handful of chart cards with a stable identity; a day of transactions
/// uses transient state instead, since a key per day is a key per day
/// forever.
struct PersistedMoneyCard<Header: View, Body: View>: View {
    let tone: AdaptiveColor
    let name: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Body
    @AppStorage private var collapsed: Bool

    init(id: String, tone: AdaptiveColor, name: String,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Body) {
        self.tone = tone
        self.name = name
        self.header = header()
        self.content = content()
        _collapsed = AppStorage(wrappedValue: false, "money.card.collapsed.\(id)")
    }

    var body: some View {
        MoneyCard(tone: tone, collapsed: $collapsed, accessibilityName: name,
                  header: { header }, content: { content })
    }
}

/// A hairline between rows that sit inside one card.
struct MoneyRowDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(MoneyPalette.ink.resolve(scheme).opacity(0.10))
            .frame(height: 1)
    }
}

// MARK: - In and out

struct MoneyFlowSection: View {
    let snapshot: MoneySnapshot
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        MoneyBandStack {
            MoneyBand(tone: MoneyPalette.sage) {
                Text("Net · \(snapshot.monthLabel)").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.net, size: 46, showsSign: snapshot.net < 0)
                Text(snapshot.verdict)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }

            MoneyBand(tone: MoneyPalette.mint) {
                Text("Earned").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.income, size: 34)
            }

            MoneyBand(tone: MoneyPalette.clay) {
                Text("Spent").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.expenses, size: 34)
                // The proportion, not a second number: how much of what came
                // in went straight back out is the thing this band is for.
                if snapshot.income > 0 {
                    Pinstripes(fraction: snapshot.expenses / snapshot.income)
                        .frame(height: 26)
                        .padding(.top, Space.half)
                    Text("\(Int(((snapshot.expenses / snapshot.income) * 100).rounded()))% of what you earned")
                        .font(LifeOSType.caption)
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }
            }

            if !snapshot.week.isEmpty {
                PersistedMoneyCard(id: "week", tone: MoneyPalette.stone, name: "This week") {
                    Text("This week").moneyEyebrow(scheme)
                    MoneyFigure(amount: snapshot.week.reduce(0) { $0 + $1.amount }, size: 28)
                } content: {
                    MoneyWeekChart(days: snapshot.week, height: layout.isRegular ? 150 : 110)
                        .padding(.top, Space.half)
                }
            }

            if let rate = snapshot.savingsRate {
                MoneyBand(tone: MoneyPalette.butter) {
                    Text("Kept").moneyEyebrow(scheme)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int((rate * 100).rounded()))")
                            .font(LifeOSType.numeral(34))
                            .monospacedDigit()
                        Text("%").font(LifeOSType.body.weight(.semibold))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                }
            }

            if let netWorth = snapshot.netWorth {
                MoneyBand(tone: MoneyPalette.mist) {
                    Text("Net worth").moneyEyebrow(scheme)
                    MoneyFigure(amount: netWorth, size: 34)
                }
            }
        }
    }
}

// MARK: - Where it went

struct MoneyCategoriesSection: View {
    let snapshot: MoneySnapshot
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        MoneyBandStack {
            PersistedMoneyCard(id: "donut", tone: MoneyPalette.mist, name: "Spent by category") {
                Text("Spent · \(snapshot.monthLabel)").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.expenses, size: 34)
                Text("\(snapshot.spendCount) transaction\(snapshot.spendCount == 1 ? "" : "s")")
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            } content: {
                if !snapshot.slices.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x2) {
                        MoneyDonut(slices: snapshot.slices, size: layout.isRegular ? 180 : 150) {
                            onOpen(.category($0.name))
                        }
                        .frame(maxWidth: .infinity)
                        // The legend under the ring, two to a row, one line
                        // each, so a slice can be read without scrolling to
                        // the band that names it and no name is ever broken.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Space.x1)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(snapshot.slices) { slice in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(MoneyPalette.ink.resolve(scheme).opacity(slice.opacity))
                                        .frame(width: 8, height: 8)
                                    Text(slice.name)
                                        .font(LifeOSType.caption)
                                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("\(Int((slice.share * 100).rounded()))%")
                                        .font(LifeOSType.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                                        .fixedSize()
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(.top, Space.x1)
                }
            }

            if snapshot.categories.isEmpty {
                MoneyEmptyBand(
                    tone: MoneyPalette.stone,
                    line: "Nothing categorised yet. Categories appear once transactions carry one."
                )
            } else {
                ForEach(snapshot.categories) { row in
                    Button { onOpen(.category(row.name)) } label: {
                        MoneyBand(tone: MoneyPalette.stone) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                                if let opacity = swatchOpacity(for: row) {
                                    Circle()
                                        .fill(MoneyPalette.ink.resolve(scheme).opacity(opacity))
                                        .frame(width: 10, height: 10)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                }
                                // One line: the figure is drawn at full size
                                // and the name shrinks a little, then trails
                                // off. A word cut in half reads as a
                                // different category.
                                Text(row.name)
                                    .font(LifeOSType.body.weight(.semibold))
                                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text("\(row.count)")
                                    .font(LifeOSType.eyebrow.weight(.regular))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                                    .fixedSize()
                                Spacer(minLength: Space.x1)
                                MoneyFigure(amount: row.amount, size: 20)
                                    .fixedSize()
                                Image(systemName: "chevron.right")
                                    .font(LifeOSType.caption.weight(.semibold))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                            }
                            Pinstripes(fraction: row.share)
                                .frame(height: 18)
                            Text("\(Int((row.share * 100).rounded()))% of spending")
                                .font(LifeOSType.eyebrow.weight(.regular))
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens every charge in \(row.name)")
                }
            }
        }
    }

    /// The band's swatch matches its slice. A category folded into "Other"
    /// has no slice of its own and gets no swatch.
    private func swatchOpacity(for row: CategoryRow) -> Double? {
        snapshot.slices.first { $0.name == row.name && !$0.isOther }?.opacity
    }
}

// MARK: - Every month

struct MoneyRecurringSection: View {
    let snapshot: MoneySnapshot
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    private var monthlyTotal: Double {
        snapshot.recurring.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        MoneyBandStack {
            PersistedMoneyCard(id: "recurring", tone: MoneyPalette.mint, name: "Every month") {
                Text("Every month").moneyEyebrow(scheme)
                MoneyFigure(amount: monthlyTotal, size: 40)
                Text(snapshot.recurring.isEmpty
                     ? "No repeating payments found yet"
                     : "\(snapshot.recurring.count) repeating payment\(snapshot.recurring.count == 1 ? "" : "s")")
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            } content: {
                if snapshot.recurring.isEmpty {
                    Text("A payment shows up here once the same merchant has charged a similar amount in two separate months.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.x1)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.recurring) { row in
                            MoneyRowDivider()
                            Button { onOpen(.merchant(row.merchant)) } label: {
                                HStack(spacing: Space.x2 - 4) {
                                    MerchantTile(logoURL: row.logoURL,
                                                 glyph: MoneyLedgerSection.glyph(for: row.category))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.merchant)
                                            .font(LifeOSType.body.weight(.semibold))
                                            .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Text(row.category ?? "Uncategorised")
                                            .moneyEyebrow(scheme)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    Spacer(minLength: Space.x1)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        MoneyFigure(amount: row.amount, size: 20)
                                            .fixedSize()
                                        Text("\(row.months) months")
                                            .font(LifeOSType.eyebrow.weight(.regular))
                                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                                            .fixedSize()
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(LifeOSType.caption.weight(.semibold))
                                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                                }
                                .padding(.vertical, Space.x1 + 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens every charge from \(row.merchant)")
                        }
                    }
                    .padding(.top, Space.x1)
                }
            }

            if !snapshot.recurring.isEmpty {
                MoneyBand(tone: MoneyPalette.sage) {
                    Text("A year of these").moneyEyebrow(scheme)
                    MoneyFigure(amount: monthlyTotal * 12, size: 28)
                    // The annual figure is the argument for cancelling
                    // anything: a monthly number small enough to ignore is
                    // rarely small enough to ignore twelve times.
                    Text("What these cost if nothing changes")
                        .font(LifeOSType.caption)
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }
            }
        }
    }
}

// MARK: - Saving for

struct MoneyGoalSection: View {
    let snapshot: MoneySnapshot
    var onEdit: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MoneyBandStack {
            if let goal = snapshot.goal {
                MoneyBand(tone: MoneyPalette.butter) {
                    Text(goal.name).moneyEyebrow(scheme)
                    MoneyFigure(amount: goal.saved, size: 46)
                    HStack(alignment: .firstTextBaseline) {
                        Text("of").font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                        MoneyFigure(amount: goal.target, size: 18)
                    }
                    Pinstripes(fraction: goal.progress)
                        .frame(height: 34)
                        .padding(.top, Space.half)
                    Text(goal.isMet
                         ? "Reached. Anything more is ahead of plan."
                         : "\(Int((goal.progress * 100).rounded()))% there")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }

                if !goal.isMet {
                    MoneyBand(tone: MoneyPalette.stone) {
                        Text("Still to find").moneyEyebrow(scheme)
                        MoneyFigure(amount: goal.remaining, size: 34)
                        if snapshot.net > 0 {
                            let months = Int((goal.remaining / snapshot.net).rounded(.up))
                            Text(months <= 1
                                 ? "About a month at this month's pace"
                                 : "About \(months) months at this month's pace")
                                .font(LifeOSType.caption)
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        } else {
                            // Honest rather than encouraging: a month that
                            // kept nothing gets no arrival date.
                            Text("No date while the month is not keeping anything")
                                .font(LifeOSType.caption)
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        }
                    }
                }
            } else {
                MoneyBand(tone: MoneyPalette.butter, minHeight: 180) {
                    Text("Saving for").moneyEyebrow(scheme)
                    Text("No goal set")
                        .font(LifeOSType.numeral)
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    Text("Name a target and this becomes the month's scoreboard.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set a goal", action: onEdit)
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        .padding(.vertical, 8)
                        .padding(.horizontal, Space.x2)
                        .overlay(Capsule().strokeBorder(
                            MoneyPalette.ink.resolve(scheme).opacity(0.4), lineWidth: 1))
                        .padding(.top, Space.half)
                }
            }
        }
    }
}

// MARK: - What hurts

struct MoneyPressureSection: View {
    let points: [PressurePoint]
    var onEditBudgets: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MoneyBandStack {
            if points.isEmpty {
                MoneyBand(tone: MoneyPalette.mint, minHeight: 200) {
                    Text("What hurts").moneyEyebrow(scheme)
                    Text("Nothing right now")
                        .font(LifeOSType.numeral)
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    Text("No bucket is over and nothing is quietly repeating. This band fills itself when that changes.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                MoneyBand(tone: MoneyPalette.clay) {
                    Text("What hurts").moneyEyebrow(scheme)
                    MoneyFigure(amount: points.reduce(0) { $0 + $1.amount }, size: 40)
                    Text("across \(points.count) thing\(points.count == 1 ? "" : "s")")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }

                ForEach(points) { point in
                    MoneyBand(tone: MoneyPalette.stone) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(point.title)
                                .font(LifeOSType.body.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: Space.x1)
                            MoneyFigure(amount: point.amount, size: 20)
                                .fixedSize()
                        }
                        Text(point.detail)
                            .font(LifeOSType.caption)
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                MoneyBand(tone: MoneyPalette.sage) {
                    Button("Edit budgets", action: onEditBudgets)
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                        .padding(.vertical, 8)
                        .padding(.horizontal, Space.x2)
                        .overlay(Capsule().strokeBorder(
                            MoneyPalette.ink.resolve(scheme).opacity(0.4), lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Recent

struct MoneyLedgerSection: View {
    let snapshot: MoneySnapshot
    var onAdd: () -> Void = {}
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MoneyBandStack {
            MoneyBand(tone: MoneyPalette.stone) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.monthLabel).moneyEyebrow(scheme)
                        Text("\(snapshot.recent.count) transaction\(snapshot.recent.count == 1 ? "" : "s")")
                            .font(LifeOSType.sectionTitle.weight(.bold))
                            .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    }
                    Spacer()
                    Button("Add", action: onAdd)
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                }
            }

            if snapshot.recent.isEmpty {
                MoneyEmptyBand(tone: MoneyPalette.mist, line: "Nothing logged this month yet.")
            } else {
                // The whole month, a card per day. Eight undated rows was the
                // old list, and "what did I spend" has no answer without dates.
                MoneyDayCards(rows: snapshot.recent, onOpen: onOpen)
            }
        }
    }

    /// A glyph per category, falling back to a neutral one. Deliberately a
    /// small fixed set: inventing an icon for every string a bank sends would
    /// produce a different picture for "Coffee" and "Coffee Shops".
    static func glyph(for category: String?) -> String {
        switch category?.lowercased() {
        case let value? where value.contains("groc") || value.contains("food"): "cart.fill"
        case let value? where value.contains("eat") || value.contains("restaurant") || value.contains("dining"): "fork.knife"
        case let value? where value.contains("transport") || value.contains("travel"): "car.fill"
        case let value? where value.contains("health") || value.contains("fitness") || value.contains("medical"): "heart.fill"
        case let value? where value.contains("entertain") || value.contains("subscription"): "play.rectangle.fill"
        case let value? where value.contains("shop") || value.contains("merchandise"): "bag.fill"
        case let value? where value.contains("home") || value.contains("rent") || value.contains("utilit"): "house.fill"
        case let value? where value.contains("income") || value.contains("salary"): "arrow.down.left"
        default: "circle.grid.2x2.fill"
        }
    }
}

// MARK: - Shared empty band

struct MoneyEmptyBand: View {
    let tone: AdaptiveColor
    let line: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MoneyBand(tone: tone, minHeight: 120) {
            Text(line)
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(MoneyPalette.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
