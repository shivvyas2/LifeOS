import SwiftUI
import DesignSystem
import Persistence

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

/// One card in the deck.
///
/// The band across the top is the part that survives being covered, so it
/// carries the two facts the board exists to deliver: which sector, and where
/// it stands. Everything below the band belongs to the open card.
private struct SectorDeckCard: View {
    let card: LifeBoardViewModel.Card
    let peek: CGFloat
    let height: CGFloat
    let isOpen: Bool
    let onOpenDetail: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { SectorPalette.cardInk.resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            band

            // Nothing renders below the band while closed. A covered card has
            // only `peek` points of room, and anything taller than that gets
            // sliced in half by the card in front: the trend line showed as a
            // clipped strip of letter-tops under every title.
            if isOpen { openBody }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(SectorPalette.tone(card.sector).resolve(scheme))
        )
        // Cast upward, onto the card this one covers. A shadow falling the
        // usual way would land on the card in front and the deck would read
        // inside out. An open card's shadow deepens: that, plus the raised
        // z-order, is what sells it as lifted rather than merely taller.
        .shadow(
            color: .black.opacity(shadowOpacity),
            radius: isOpen ? 22 : 10,
            y: isOpen ? 6 : -3
        )
        .accessibilityElement(children: isOpen ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Collapse" : "Expand for the trend")
    }

    private var shadowOpacity: Double {
        let base = scheme == .dark ? 0.34 : 0.12
        return isOpen ? base * 1.8 : base
    }

    /// Title and score on one line, sized to fill the visible band.
    private var band: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(card.sector.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
            Spacer(minLength: Space.x1)
            Text(scoreText)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(card.score == nil ? 0.35 : 1))
        }
        .foregroundStyle(ink)
        .frame(height: peek - Space.x2 - Space.x1, alignment: .center)
    }

    /// What the deck was hiding. Trend first, because the shape of six months
    /// says more at a glance than any single number on the card.
    @ViewBuilder
    private var openBody: some View {
        Text(trendLine)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ink.opacity(0.65))

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
                height: 64
            )
        }

        Spacer(minLength: 0)

        Button(action: onOpenDetail) {
            HStack(spacing: Space.half) {
                Text("Open")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
            .overlay(Capsule().strokeBorder(ink.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// An em dash for an unscored sector, matching what the rest of the app
    /// shows for a missing value.
    private var scoreText: String {
        card.score.map(String.init) ?? "—"
    }

    /// Derived from the history the card already carries.
    private var trendLine: String {
        guard card.score != nil else { return "Not scored yet" }
        guard card.history.count > 1 else { return "First month scored" }
        let months = card.history.suffix(2)
        guard let previous = months.first?.value, let latest = months.last?.value else {
            return " "
        }
        let delta = latest - previous
        if delta == 0 { return "Level with last month" }
        return "\(delta > 0 ? "Up" : "Down") \(abs(delta)) from last month"
    }

    /// The visual truncation must never truncate what VoiceOver reads: eight
    /// of the nine cards are partly covered on screen, and all nine are whole
    /// here.
    private var accessibilityText: String {
        let score = card.score.map { "score \($0)" } ?? "not scored yet"
        return "\(card.sector.title), \(score)"
    }
}
