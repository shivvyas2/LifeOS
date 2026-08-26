import SwiftUI
import DesignSystem

/// The six panels behind `MoneySectionRail`.
///
/// Each is a stack of full-bleed bands: a band owns its colour edge to edge,
/// carries one tracked label and one figure at display size, and states one
/// thing. Cards with margins were the alternative and made every section look
/// like a settings list.
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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .top)
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x2)
        .background(tone.resolve(scheme))
    }
}

// MARK: - In and out

struct MoneyFlowSection: View {
    let snapshot: MoneySnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.sage) {
                Text("Net · \(snapshot.monthLabel)").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.net, size: 46, showsSign: snapshot.net < 0)
                Text(snapshot.verdict)
                    .font(.system(size: 13, weight: .semibold))
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
                    Text("\(Int((snapshot.expenses / snapshot.income) * 100))% of what you earned")
                        .font(.system(size: 12))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }
            }

            if let rate = snapshot.savingsRate {
                MoneyBand(tone: MoneyPalette.stone) {
                    Text("Kept").moneyEyebrow(scheme)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(rate * 100))")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("%").font(.system(size: 18, weight: .semibold))
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.mist) {
                Text("Spent · \(snapshot.monthLabel)").moneyEyebrow(scheme)
                MoneyFigure(amount: snapshot.expenses, size: 40)
            }

            if snapshot.categories.isEmpty {
                MoneyEmptyBand(
                    tone: MoneyPalette.stone,
                    line: "Nothing categorised yet. Categories appear once transactions carry one."
                )
            } else {
                ForEach(snapshot.categories) { row in
                    MoneyBand(tone: MoneyPalette.stone) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                            Spacer(minLength: Space.x1)
                            MoneyFigure(amount: row.amount, size: 20)
                        }
                        Pinstripes(fraction: row.share)
                            .frame(height: 18)
                        Text("\(Int(row.share * 100))% of spending")
                            .font(.system(size: 11))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                    }
                }
            }
        }
    }
}

// MARK: - Every month

struct MoneyRecurringSection: View {
    let snapshot: MoneySnapshot
    @Environment(\.colorScheme) private var scheme

    private var monthlyTotal: Double {
        snapshot.recurring.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.mint) {
                Text("Every month").moneyEyebrow(scheme)
                MoneyFigure(amount: monthlyTotal, size: 40)
                Text(snapshot.recurring.isEmpty
                     ? "No repeating payments found yet"
                     : "\(snapshot.recurring.count) repeating payment\(snapshot.recurring.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }

            if snapshot.recurring.isEmpty {
                MoneyEmptyBand(
                    tone: MoneyPalette.stone,
                    line: "A payment shows up here once the same merchant has charged a similar amount in two separate months."
                )
            } else {
                ForEach(snapshot.recurring) { row in
                    MoneyBand(tone: MoneyPalette.stone) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.merchant)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                Text(row.category ?? "Uncategorised")
                                    .moneyEyebrow(scheme)
                            }
                            Spacer(minLength: Space.x1)
                            VStack(alignment: .trailing, spacing: 2) {
                                MoneyFigure(amount: row.amount, size: 20)
                                Text("\(row.months) months")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoneyPalette.quietInk(scheme))
                            }
                        }
                    }
                }

                MoneyBand(tone: MoneyPalette.sage) {
                    Text("A year of these").moneyEyebrow(scheme)
                    MoneyFigure(amount: monthlyTotal * 12, size: 28)
                    // The annual figure is the argument for cancelling
                    // anything: a monthly number small enough to ignore is
                    // rarely small enough to ignore twelve times.
                    Text("What these cost if nothing changes")
                        .font(.system(size: 12))
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
        VStack(spacing: 0) {
            if let goal = snapshot.goal {
                MoneyBand(tone: MoneyPalette.butter) {
                    Text(goal.name).moneyEyebrow(scheme)
                    MoneyFigure(amount: goal.saved, size: 46)
                    HStack(alignment: .firstTextBaseline) {
                        Text("of").font(.system(size: 13))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                        MoneyFigure(amount: goal.target, size: 18)
                    }
                    Pinstripes(fraction: goal.progress)
                        .frame(height: 34)
                        .padding(.top, Space.half)
                    Text(goal.isMet
                         ? "Reached. Anything more is ahead of plan."
                         : "\(Int(goal.progress * 100))% there")
                        .font(.system(size: 13, weight: .semibold))
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
                                .font(.system(size: 12))
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        } else {
                            // Honest rather than encouraging: a month that
                            // kept nothing gets no arrival date.
                            Text("No date while the month is not keeping anything")
                                .font(.system(size: 12))
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                        }
                    }
                }
            } else {
                MoneyBand(tone: MoneyPalette.butter, minHeight: 180) {
                    Text("Saving for").moneyEyebrow(scheme)
                    Text("No goal set")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    Text("Name a target and this becomes the month's scoreboard.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set a goal", action: onEdit)
                        .font(.system(size: 14, weight: .semibold))
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
        VStack(spacing: 0) {
            if points.isEmpty {
                MoneyBand(tone: MoneyPalette.mint, minHeight: 200) {
                    Text("What hurts").moneyEyebrow(scheme)
                    Text("Nothing right now")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    Text("No bucket is over and nothing is quietly repeating. This band fills itself when that changes.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                MoneyBand(tone: MoneyPalette.clay) {
                    Text("What hurts").moneyEyebrow(scheme)
                    MoneyFigure(amount: points.reduce(0) { $0 + $1.amount }, size: 40)
                    Text("across \(points.count) thing\(points.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }

                ForEach(points) { point in
                    MoneyBand(tone: MoneyPalette.stone) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(point.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                            Spacer(minLength: Space.x1)
                            MoneyFigure(amount: point.amount, size: 20)
                        }
                        Text(point.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(MoneyPalette.quietInk(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                MoneyBand(tone: MoneyPalette.sage) {
                    Button("Edit budgets", action: onEditBudgets)
                        .font(.system(size: 14, weight: .semibold))
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MoneyBand(tone: MoneyPalette.stone) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent").moneyEyebrow(scheme)
                        Text("\(snapshot.recent.count) transactions")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                    }
                    Spacer()
                    Button("Add", action: onAdd)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                }
            }

            if snapshot.recent.isEmpty {
                MoneyEmptyBand(tone: MoneyPalette.mist, line: "Nothing logged this month yet.")
            } else {
                ForEach(snapshot.recent) { row in
                    // The left glyph rail from the reference: a fixed square of
                    // deeper tone that turns a list of text into a list of
                    // rows the eye can run down.
                    HStack(spacing: 0) {
                        Image(systemName: MoneyLedgerSection.glyph(for: row.category))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.75))
                            .frame(width: 52, height: 62)
                            .background(MoneyPalette.sage.resolve(scheme))

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.merchant)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                Text(row.category ?? "Uncategorised").moneyEyebrow(scheme)
                            }
                            Spacer(minLength: Space.x1)
                            MoneyFigure(amount: row.amount, size: 18, showsSign: true)
                                .opacity(row.pending ? 0.45 : 1)
                        }
                        .padding(.horizontal, Space.x2)
                        .frame(height: 62)
                        .background(MoneyPalette.stone.resolve(scheme))
                    }
                }
            }
        }
    }

    /// A glyph per category, falling back to a neutral one. Deliberately a
    /// small fixed set: inventing an icon for every string a bank sends would
    /// produce a different picture for "Coffee" and "Coffee Shops".
    static func glyph(for category: String?) -> String {
        switch category?.lowercased() {
        case let value? where value.contains("groc") || value.contains("food"): "cart.fill"
        case let value? where value.contains("eat") || value.contains("restaurant"): "fork.knife"
        case let value? where value.contains("transport") || value.contains("travel"): "car.fill"
        case let value? where value.contains("health") || value.contains("fitness"): "heart.fill"
        case let value? where value.contains("entertain") || value.contains("subscription"): "play.rectangle.fill"
        case let value? where value.contains("home") || value.contains("rent"): "house.fill"
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
                .font(.system(size: 13))
                .foregroundStyle(MoneyPalette.quietInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
