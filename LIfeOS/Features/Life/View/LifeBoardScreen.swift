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
    /// A card to mount open, for the design previews. Nil in the app.
    var initiallyOpen: LifeSector? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    @State private var showClose = false
    @State private var closeMonth = Date.now
    @State private var openSector: LifeSector?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    EditorialMasthead(eyebrow: model.headline.eyebrow,
                                      title: model.headline.title,
                                      detail: model.headline.detail)

                    UnderlinePicker(
                        selection: Binding(get: { model.mode }, set: { model.mode = $0 }),
                        options: [(.inFlight, LifeBoardViewModel.BoardMode.inFlight.title),
                                  (.closed, LifeBoardViewModel.BoardMode.closed.title)]
                    )

                    if let month = model.monthAwaitingClose {
                        CloseBanner(month: month) {
                            closeMonth = month
                            showClose = true
                        }
                    }

                    if model.isBlank {
                        emptyState
                    } else {
                        SectorStack(cards: model.cards, initiallyOpen: initiallyOpen) { sector in
                            openSector = sector
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
            .shellToolbar()
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

    /// The board before anything is on it: a ghost of three bands and the one
    /// thing to do.
    private var emptyState: some View {
        EditorialEmptyState(
            sentence: "Nine sectors, scored once a month. The board shows where life stands.",
            action: "Score this month",
            onAction: {
                closeMonth = model.monthAwaitingClose ?? model.month
                showClose = true
            }
        ) {
            VStack(spacing: Space.x1) {
                SectorBandRow(index: 1, title: "Family", value: "7", unit: "/10", isOpen: false)
                SectorBandRow(index: 2, title: "Body", value: "8", unit: "/10", isOpen: false)
                SectorBandRow(index: 3, title: "Money", value: "6", unit: "/10", isOpen: false)
            }
        }
    }
}
