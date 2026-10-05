import SwiftUI
import DesignSystem
import Persistence
import Sectors

/// The nine sectors as a deck of overlapping cards, in the shape of a wallet.
///
/// Each card is laid out at its full height and then pulled up over the one
/// before it, so all that shows is a top band carrying the sector and its
/// score. Tapping a card lifts it clear of the deck and opens it: the cards
/// below slide down, the card itself rises, and the space that appears
/// carries the score, the six-month trend and the change since last month.
///
/// Only one card is ever open. A deck with several cards open is a list with
/// gaps in it, and the whole point of the shape is that the closed state is
/// dense.
struct SectorStack: View {
    let cards: [LifeBoardViewModel.Card]
    /// Called when the open card's own button is used. Pushes the full sector
    /// screen, which carries the evidence, answers and notes that do not fit
    /// on a card.
    let onOpenDetail: (LifeSector) -> Void

    @State private var openSector: LifeSector?

    /// `initiallyOpen` mounts the deck with one card already lifted; the
    /// design previews use it, since a tap is not something a screenshot
    /// can make.
    init(cards: [LifeBoardViewModel.Card], initiallyOpen: LifeSector? = nil,
         onOpenDetail: @escaping (LifeSector) -> Void) {
        self.cards = cards
        self.onOpenDetail = onOpenDetail
        _openSector = State(initialValue: initiallyOpen)
    }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of a covered card stays visible: the title and score band.
    /// The grid this replaced showed every score, and a board that hid eight
    /// of nine would be a prettier, worse board.
    private static let peek: CGFloat = 78
    private static let closedHeight: CGFloat = 190

    /// An open card is sized to what it actually has to show. A sector with
    /// one month or none has no chart to draw, and a fixed tall card spent
    /// that space on nothing: one line of text, a button, and a void.
    private static func openHeight(for card: LifeBoardViewModel.Card) -> CGFloat {
        card.history.count > 1 ? 320 : 226
    }

    var body: some View {
        VStack(spacing: Self.peek - Self.closedHeight) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isOpen = openSector == card.sector

                SectorDeckCard(
                    index: index + 1,
                    card: card,
                    peek: Self.peek,
                    height: isOpen ? Self.openHeight(for: card) : Self.closedHeight,
                    isOpen: isOpen,
                    onOpenDetail: { onOpenDetail(card.sector) }
                )
                .onTapGesture { toggle(card.sector) }
                // An open card rises clear of the deck. Without the boost it
                // would expand underneath the cards after it and read as the
                // deck swallowing it rather than releasing it.
                .zIndex(isOpen ? 1000 : Double(index))
                // The gap the open card needs. Applied as padding rather than
                // by growing the negative spacing, because spacing is uniform
                // across the stack and only this one card should move its
                // neighbours.
                .padding(.bottom, isOpen ? Self.openHeight(for: card) - Self.peek : 0)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
                   value: openSector)
    }

    private func toggle(_ sector: LifeSector) {
        openSector = (openSector == sector) ? nil : sector
    }
}

/// The band that survives being covered: index, sector, score, and the
/// chevron that says it opens.
///
/// Shared with the board's teaching empty state, which ghosts three of these.
struct SectorBandRow: View {
    let index: Int
    let title: String
    let value: String
    let unit: String?
    let isOpen: Bool
    /// Nil draws in the paper ink; the open card passes the dusk field's ink.
    var ink: Color? = nil
    var hasValue = true

    @Environment(\.colorScheme) private var scheme

    private var primary: Color { ink ?? LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { ink.map { $0.opacity(0.6) } ?? Editorial.quietInk(scheme) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(Editorial.index(index))
                .font(LifeOSType.label.monospacedDigit())
                .foregroundStyle(quiet)
                .accessibilityHidden(true)
            Text(title)
                .font(Editorial.headline(22)).tracking(-0.4)
                .foregroundStyle(primary)
            Spacer(minLength: Space.x1)
            HStack(alignment: .firstTextBaseline, spacing: Space.half) {
                Text(value)
                    .font(Editorial.figure(28)).tracking(Editorial.figureTracking(28))
                    .monospacedDigit()
                    .foregroundStyle(hasValue ? primary : quiet)
                if let unit {
                    Text(unit).font(LifeOSType.caption).foregroundStyle(quiet)
                }
            }
            Image(systemName: "chevron.down")
                .font(LifeOSType.caption.weight(.semibold))
                .foregroundStyle(quiet)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
    }
}

/// One card in the deck.
///
/// Closed, it is paper with a hairline edge and only its band showing.
/// Open, it is the screen's one dusk field, carrying the trend in ink.
private struct SectorDeckCard: View {
    let index: Int
    let card: LifeBoardViewModel.Card
    let peek: CGFloat
    let height: CGFloat
    let isOpen: Bool
    let onOpenDetail: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var fieldInk: Color { EditorialFieldTone.dusk.ink(scheme) }
    private var radius: CGFloat { Radius.medium + 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            SectorBandRow(index: index, title: card.sector.title, value: scoreText, unit: scoreUnit,
                          isOpen: isOpen, ink: isOpen ? fieldInk : nil, hasValue: hasValue)
                .frame(height: peek - Space.x2 - Space.x1, alignment: .center)

            // Nothing renders below the band while closed: a covered card has
            // only `peek` points of room.
            if isOpen { openBody }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background {
            if isOpen {
                LinearGradient(colors: EditorialFieldTone.dusk.colors(scheme), startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            }
        }
        .overlay {
            if !isOpen {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Editorial.rule(scheme))
            }
        }
        .accessibilityElement(children: isOpen ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Collapse" : "Expand for the trend")
    }

    @ViewBuilder
    private var openBody: some View {
        Text(trendLine)
            .font(LifeOSType.secondary.weight(.medium))
            .foregroundStyle(fieldInk.opacity(0.7))

        if card.history.count > 1 {
            RoundedBarChart(
                bars: card.history.map {
                    RoundedBarChart.Bar(
                        id: $0.id,
                        label: $0.id.formatted(.dateTime.month(.narrow)),
                        value: $0.value
                    )
                },
                style: .ink,
                // A rating against the window's low, not nought: six months
                // of 6 to 8 is a shape, not six full bars.
                baseline: .windowMinimum,
                spacing: Space.half,
                height: 64
            )
        }

        Spacer(minLength: 0)

        Button(action: onOpenDetail) {
            HStack(spacing: Space.half) {
                Text("Open \(card.sector.title)")
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
    }

    /// A closed sector shows its score; one in flight shows the range it can
    /// still close in. An em dash for either when there is nothing to say.
    private var scoreText: String {
        if let band = card.band {
            return band.rangeText ?? "—"
        }
        return card.score.map(String.init) ?? "—"
    }

    private var scoreUnit: String? {
        card.band == nil && card.score != nil ? "/10" : nil
    }

    private var hasValue: Bool {
        card.band.map { $0.floor != nil } ?? (card.score != nil)
    }

    /// In flight the line answers how much of the month is left to decide;
    /// closed, it is the change since last month.
    private var trendLine: String {
        if let band = card.band {
            guard band.floor != nil else { return "Not read yet" }
            guard let decided = band.decided else { return "No ceiling without budgets" }
            return "\(Int((decided * 100).rounded()))% decided"
        }
        guard card.score != nil else { return "Not scored yet" }
        guard card.history.count > 1 else { return "First month scored" }
        let months = card.history.suffix(2)
        guard let previous = months.first?.value, let latest = months.last?.value else {
            return " "
        }
        let delta = latest - previous
        if delta == 0 { return "Level with last month" }
        return "\(delta > 0 ? "Up" : "Down") \(Int(abs(delta))) from last month"
    }

    /// The visual truncation must never truncate what VoiceOver reads: eight
    /// of the nine cards are partly covered on screen, and all nine are whole
    /// here.
    private var accessibilityText: String {
        if let band = card.band {
            guard let floor = band.floor else { return "\(card.sector.title), not read yet" }
            guard let ceiling = band.ceiling, ceiling != floor else {
                return "\(card.sector.title), closing at \(floor)"
            }
            return "\(card.sector.title), between \(floor) and \(ceiling)"
        }
        let score = card.score.map { "score \($0)" } ?? "not scored yet"
        return "\(card.sector.title), \(score)"
    }
}
