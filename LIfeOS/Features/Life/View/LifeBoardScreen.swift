import SwiftUI
import DesignSystem
import Persistence
import Sectors

/// The nine-sector board. A pure function of the view model, like `MoneyScreen`
/// and `PlanScreen` — `RootView` owns the model, attaches the context, and
/// reloads it; this screen only renders what it is handed.
///
/// The one exception to "pure function of the model" is the close sheet:
/// tapping the banner is purely local navigation (which month to close was
/// already decided by `model.monthAwaitingClose`), so it is state owned right
/// here rather than threaded up through `RootView`, the way `MoneyScreen` and
/// `PlanScreen` thread their add-sheets — those need `RootView` because the
/// thing being added belongs to a model `RootView` owns and other tabs read;
/// nothing outside this screen needs to know the close sheet is open.
struct LifeBoardScreen: View {
    let model: LifeBoardViewModel
    /// Called with the sector whose full tab should open. The board does not
    /// know how the tab bar works, and `AppTab` stays private to RootView.
    let onOpenTab: (LifeSector) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    @State private var showClose = false
    @State private var closeMonth = Date.now

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.x2), count: layout.isRegular ? 3 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if let month = model.monthAwaitingClose {
                        Button {
                            closeMonth = month
                            showClose = true
                        } label: {
                            AlertBanner(messages: [
                                "Close \(month.formatted(.dateTime.month(.wide).year())): score your nine sectors for the month."
                            ])
                        }
                        .buttonStyle(.plain)
                    }

                    header

                    LazyVGrid(columns: columns, spacing: Space.x2) {
                        ForEach(model.cards) { card in
                            NavigationLink(value: card.sector) {
                                SectorCard(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.gutter)
                .padding(.leading, layout.railInset)
                .padding(.top, Space.x3)
                .padding(.bottom, layout.contentBottomInset)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationDestination(for: LifeSector.self) { sector in
                SectorDetailScreen(sector: sector, onOpenTab: openTabClosure(for: sector))
            }
            .sheet(isPresented: $showClose) {
                MonthlyCloseScreen(month: closeMonth) {
                    showClose = false
                    model.load()
                }
            }
        }
    }

    /// Only Body, Money and Mission own a full tab; every other sector gets
    /// no row on its detail screen.
    private func openTabClosure(for sector: LifeSector) -> (() -> Void)? {
        switch sector {
        case .body, .money, .mission:
            return { onOpenTab(sector) }
        default:
            return nil
        }
    }

    /// The header carries the two `BoardSummary` facts. There is no combined
    /// life score to show here — see `BoardSummary`'s own doc comment.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            if let lowest = model.summary.lowest {
                Text("Lowest: \(lowest.title)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            if let mover = model.summary.biggestMover {
                Text("Biggest move: \(mover.sector.title) \(mover.delta > 0 ? "+" : "")\(mover.delta)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }
}

/// One sector's tile: the design system's pastel metric card, plus its own
/// six-month strip underneath when there is more than one point to show.
private struct SectorCard: View {
    let card: LifeBoardViewModel.Card

    var body: some View {
        VStack(spacing: Space.x1) {
            // `value: nil` renders PastelFillCard's own em dash for a sector
            // that has not been scored yet, rather than a hand-built one.
            PastelFillCard(
                icon: SectorPalette.icon(card.sector),
                hue: SectorPalette.hue(card.sector),
                label: card.sector.title,
                value: card.score.map(String.init)
            )

            if card.history.count > 1 {
                RoundedBarChart(
                    bars: card.history.map {
                        RoundedBarChart.Bar(
                            id: $0.id,
                            label: $0.id.formatted(.dateTime.month(.narrow)),
                            value: $0.value
                        )
                    },
                    hue: SectorPalette.hue(card.sector),
                    spacing: Space.half,
                    height: 48
                )
            }
        }
    }
}
