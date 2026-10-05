import SwiftUI
import DesignSystem

/// The Money tab.
///
/// Six questions, one per side tab, rather than one long scroll: what came in
/// and went out, where it went, what repeats every month, what it is being
/// saved towards, what is hurting, and the ledger itself. They are separate
/// visits, and stacking them into a single column made every one of them a
/// scroll past the other five.
///
/// Laid out as a page rather than a panel: the month's net figure as the
/// masthead, a numbered strip of the six questions under it, and the answer
/// as ruled blocks on the app's own paper. It used to be pastel bands on pure
/// white beside a vertical icon rail, a departure from every other tab that
/// read as a second app, and the rail took a third of a phone's width to say
/// six one-word labels.
struct MoneyScreen: View {
    let snapshot: MoneySnapshot
    var onAdd: () -> Void = {}
    var onConnect: () -> Void = {}
    var onSync: () -> Void = {}
    var onEditBudgets: () -> Void = {}
    /// A category, merchant or transaction was tapped. The stack that owns
    /// this screen pushes the detail page.
    var onOpen: (MoneyDetailFilter) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    /// Not persisted: the tab a visit starts on should be the summary, not
    /// wherever the last visit happened to end up.
    @State private var section: MoneySection = .flow

    var body: some View {
        ZStack {
            MoneyPalette.paper.resolve(scheme).ignoresSafeArea()

            if snapshot.isFetchingHistory && snapshot.recent.isEmpty {
                fetchingState
            } else if snapshot.isConnected {
                loaded
            } else {
                emptyState
            }
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                masthead
                if snapshot.reconnectPrompt != nil { reconnectBanner }
                IndexedTabStrip(selection: $section,
                                options: MoneySection.allCases.map { ($0, $0.title) })
                sections
                    // A fresh identity per section, so switching tabs starts
                    // the new answer from its own top rather than mid-way.
                    .id(section)
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x2)
            .padding(.bottom, layout.contentBottomInset)
        }
        .scrollIndicators(.hidden)
    }

    /// The month in one figure. Net is what every section below explains, so
    /// it is said once, here, rather than as the first band of one tab.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Money · \(snapshot.monthLabel)").editorialEyebrow()
                Spacer(minLength: Space.x1)
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .overlay(Capsule().stroke(LifeOSTokens.primaryText.resolve(scheme).opacity(0.5)))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a transaction")
            }
            MoneyFigure(amount: snapshot.net, size: 64, showsSign: true)
            HStack(spacing: Space.x1) {
                EditorialTag(snapshot.verdict, filled: snapshot.net < 0)
                Text("kept this month")
                    .font(LifeOSType.caption)
                    .foregroundStyle(Editorial.quietInk(scheme))
                Spacer(minLength: Space.x1)
                if let synced = snapshot.lastSyncedAt {
                    Text("Synced \(synced, format: .relative(presentation: .named))")
                        .font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch section {
        case .flow:       MoneyFlowSection(snapshot: snapshot)
        case .categories: MoneyCategoriesSection(snapshot: snapshot, onOpen: onOpen)
        case .repeating:  MoneyRecurringSection(snapshot: snapshot, onOpen: onOpen)
        case .goal:       MoneyGoalSection(snapshot: snapshot, onEdit: onEditBudgets)
        case .pressure:   MoneyPressureSection(points: snapshot.pressurePoints,
                                               onEditBudgets: onEditBudgets)
        case .ledger:     MoneyLedgerSection(snapshot: snapshot, onAdd: onAdd, onOpen: onOpen)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.x2) {
            Spacer(minLength: Space.x8)
            Text("Money").moneyEyebrow(scheme)
            Text("Nothing here yet")
                .font(LifeOSType.screenTitle)
                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
            Text("Connect a bank, or log a transaction by hand to get started.")
                .font(LifeOSType.label.weight(.regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(MoneyPalette.quietInk(scheme))

            Button("Connect your bank", action: onConnect)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.fabGlyph.resolve(scheme))
                .padding(.vertical, 12)
                .padding(.horizontal, Space.x3)
                .background(Capsule().fill(LifeOSTokens.fabFill.resolve(scheme)))

            Button("Add a transaction", action: onAdd)
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(MoneyPalette.quietInk(scheme))
            Spacer()
        }
        .padding(.horizontal, Space.x3)
    }

    /// Connected, but Plaid is still assembling the history.
    ///
    /// Plaid fetches transactions asynchronously after the login completes, so
    /// the first sync can honestly come back with nothing. Rendering that as an
    /// empty month would state, as fact, that the user spent nothing.
    private var fetchingState: some View {
        VStack(spacing: Space.x2) {
            ProgressView()
            Text("Fetching your transactions")
                .font(LifeOSType.body.weight(.semibold))
                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
            Text("Your bank is sending the last few months. This usually takes a minute.")
                .font(LifeOSType.label.weight(.regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(MoneyPalette.quietInk(scheme))
            Button("Check again", action: onSync)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
        }
        .padding(.horizontal, Space.x3)
    }

    private var reconnectBanner: some View {
        HStack(spacing: Space.x1) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(LifeOSType.label.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.reconnectPrompt ?? "Your bank") needs you to sign in again")
                    .font(LifeOSType.label.weight(.semibold))
                Text("Figures below are from your last sync.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(MoneyPalette.quietInk(scheme))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
        .padding(Space.x2)
        .background(LifeOSTokens.accentSoft.resolve(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    static func money(_ value: Double) -> String? {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func signed(_ value: Double) -> String {
        let formatted = abs(value).formatted(.currency(code: "USD").precision(.fractionLength(2)))
        return value >= 0 ? "+\(formatted)" : "-\(formatted)"
    }
}

extension MoneySnapshot {
    /// What is costing more than it should, assembled where the data is rather
    /// than in the view: the "what hurts" tab renders a list, and deciding what
    /// belongs on it is a judgement about money, not about layout.
    var pressurePoints: [PressurePoint] {
        var points: [PressurePoint] = []

        for bucket in budgets where bucket.isOver {
            points.append(PressurePoint(
                id: "budget-\(bucket.id)",
                title: bucket.name,
                detail: "Over its limit by \(MoneyScreen.money(bucket.spent - bucket.limit) ?? "")",
                amount: bucket.spent - bucket.limit
            ))
        }

        // Unclaimed spend is not over anything, but it is money leaving with
        // no bucket watching it, which is the same problem one step earlier.
        let unclaimedTotal = unclaimed.reduce(0) { $0 + abs($1.amount) }
        if unclaimedTotal > 0 {
            points.append(PressurePoint(
                id: "unclaimed",
                title: "Unclaimed spending",
                detail: "\(unclaimed.reduce(0) { $0 + $1.count }) charges no bucket is watching",
                amount: unclaimedTotal
            ))
        }

        // A subscription pile only counts as pressure when it is a real share
        // of the month. Below that it is a fact, and it already has its own tab.
        let recurringTotal = recurring.reduce(0) { $0 + $1.amount }
        if expenses > 0, recurringTotal / expenses > 0.2 {
            points.append(PressurePoint(
                id: "recurring",
                title: "Repeating payments",
                detail: "\(Int(((recurringTotal / expenses) * 100).rounded()))% of this month's spending renews by itself",
                amount: recurringTotal
            ))
        }

        return points.sorted { $0.amount > $1.amount }
    }
}
