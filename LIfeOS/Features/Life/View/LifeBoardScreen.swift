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
            .navigationDestination(item: $openSector) { sector in
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

    /// `LifeSector.ownsTab` is the one decision about which sectors own a
    /// full tab; every other sector gets no row on its detail screen.
    private func openTabClosure(for sector: LifeSector) -> (() -> Void)? {
        sector.ownsTab ? { onOpenTab(sector) } : nil
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
