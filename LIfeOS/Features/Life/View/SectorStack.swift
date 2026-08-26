import SwiftUI
import DesignSystem
import Persistence

/// The nine sectors as a deck of overlapping cards, in the shape of a wallet.
///
/// Each card is laid out at its full height and then pulled up over the one
/// before it, so all that shows is a top band carrying the sector and its
/// score. Only the last card in the deck has nothing on top of it, which is
/// why it alone reads at full height. That is not a special case in the code:
/// it is the same card as the other eight, simply uncovered.
///
/// Replaces a `LazyVGrid`. The grid could show a six-month strip under every
/// tile and this cannot, which is not a loss: `SectorDetailScreen` already
/// renders the same history as its trend band, one tap away.
struct SectorStack: View {
    let cards: [LifeBoardViewModel.Card]

    @Environment(\.colorScheme) private var scheme

    /// How much of a covered card stays visible. Sized to the title and score
    /// band plus its padding, so the deck shows every sector and every score
    /// without a tap. The grid it replaces showed both too, and a board that
    /// hid eight of nine scores would be a prettier, worse board.
    private static let peek: CGFloat = 78
    private static let cardHeight: CGFloat = 190

    var body: some View {
        VStack(spacing: Self.peek - Self.cardHeight) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                NavigationLink(value: card.sector) {
                    SectorDeckCard(card: card, height: Self.cardHeight, peek: Self.peek)
                }
                .buttonStyle(.plain)
                // Later cards must paint over earlier ones for the deck to
                // read as stacked rather than as a list of clipped boxes.
                .zIndex(Double(index))
            }
        }
    }
}

/// One card in the deck.
///
/// The band across the top is the part that survives being covered, so it
/// carries the two facts the board exists to deliver: which sector, and where
/// it stands. Everything below the band is seen on the uncovered card only.
private struct SectorDeckCard: View {
    let card: LifeBoardViewModel.Card
    let height: CGFloat
    let peek: CGFloat

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { SectorPalette.cardInk.resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            band
            Text(trendLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.65))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.x2)
        .padding(.top, Space.x2)
        .padding(.bottom, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(SectorPalette.tone(card.sector).resolve(scheme))
        )
        // Cast upward, onto the card this one covers. A shadow falling the
        // usual way would land on the card below, which is the one in front,
        // and the deck would read inside out.
        .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.12), radius: 10, y: -3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
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

    /// An em dash for an unscored sector, matching what `PastelFillCard` shows
    /// for a missing value everywhere else in the app.
    private var scoreText: String {
        card.score.map(String.init) ?? "—"
    }

    /// Derived from the history the card already carries, so the uncovered
    /// card says something the band cannot rather than repeating it.
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
