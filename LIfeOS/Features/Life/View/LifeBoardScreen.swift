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
    @State private var openSector: LifeSector?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if let month = model.monthAwaitingClose {
                        CloseBanner(month: month) {
                            closeMonth = month
                            showClose = true
                        }
                    }

                    Picker("Month", selection: Binding(
                        get: { model.mode },
                        set: { model.mode = $0 }
                    )) {
                        ForEach(LifeBoardViewModel.BoardMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    header

                    SectorStack(cards: model.cards) { sector in
                        openSector = sector
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
            .quickActionsToolbar()
            .navigationDestination(item: $openSector) { sector in
                switch model.mode {
                case .closed:
                    SectorDetailScreen(sector: sector, onOpenTab: openTabClosure(for: sector))
                case .inFlight:
                    InFlightSectorScreen(sector: sector)
                }
            }
            // Reload on dismissal, not on completion. `MonthlyCloseScreen`
            // calls `onFinish` only after all nine sectors are walked, so
            // scoring three and swiping the sheet away used to leave the deck
            // showing em dashes for scores that were already saved.
            .sheet(isPresented: $showClose, onDismiss: { model.load() }) {
                MonthlyCloseScreen(month: closeMonth) {
                    showClose = false
                }
            }
        }
    }

    /// `LifeSector.ownsTab` is the one decision about which sectors own a
    /// full tab; every other sector gets no row on its detail screen.
    private func openTabClosure(for sector: LifeSector) -> (() -> Void)? {
        sector.ownsTab ? { onOpenTab(sector) } : nil
    }

    /// Closed mode carries the two `BoardSummary` facts. In flight there is
    /// no previous month to compare against and no closed score to compare,
    /// so it answers the only question that mode has: how much is left.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            switch model.mode {
            case .closed:
                if let lowest = model.summary.lowest {
                    Text("Lowest: \(lowest.title)")
                        .font(LifeOSType.sectionTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                }
                if let mover = model.summary.biggestMover {
                    Text("Biggest move: \(mover.sector.title) \(mover.delta > 0 ? "+" : "")\(mover.delta)")
                        .font(LifeOSType.secondary.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

            case .inFlight:
                if let progress = model.progress {
                    Text(progress.remainingDays == 1 ? "1 day left" : "\(progress.remainingDays) days left")
                        .font(LifeOSType.sectionTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                }
                if let decided = model.meanDecided {
                    Text("\(Int((decided * 100).rounded()))% of this month is decided")
                        .font(LifeOSType.secondary.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }
}
