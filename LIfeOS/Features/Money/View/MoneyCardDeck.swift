import SwiftUI
import DesignSystem
import Persistence

/// Every card as a deck.
///
/// Each card is laid out whole and pulled up over the one before it, so a
/// covered card shows only a band. The cards above the open one show their
/// top band, the name and the kind; the cards below it hang out underneath
/// and show their bottom band, the issuer and the network. The open card
/// sits whole in the middle. Tapping a covered card brings it forward,
/// tapping the open card opens its charges, and holding any card restyles
/// it. One card is open at a time, and which one is remembered, so Money
/// comes back to the card it was left on.
///
/// The deck's height never changes when the open card does. Only the
/// z-order moves, which is what lets the rest of the page hold still.
///
/// The figures are not on the faces. They sit on one ruled line under the
/// deck and follow the open card, which keeps every face as plain as a real
/// one and still says the balance and the month without a tap.
struct MoneyCardDeck: View {
    let cards: [MoneyCardSummary]
    var onOpen: (MoneyCardSummary) -> Void = { _ in }
    var onEdit: (MoneyCardSummary?) -> Void = { _ in }

    @AppStorage("money.openCard", store: .currentAccount) private var rememberedID = ""
    @State private var measuredWidth: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A card is as wide as the page on a phone and capped on a wider one,
    /// where a card the width of the screen stops reading as a card.
    private var width: CGFloat { min(max(measuredWidth, 240), 440) }
    private var height: CGFloat { CardFace.height(width: width) }
    /// How much of a covered card shows: enough for the name and its eyebrow.
    private var peek: CGFloat { width * 0.2 }

    /// The open card: the remembered one if it is still here, else the first.
    private var openID: String? {
        cards.contains { $0.id == rememberedID } ? rememberedID : cards.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cards").moneyEyebrow(scheme)
                Spacer(minLength: Space.x1)
                Button("Add a card") { onEdit(nil) }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
            Color.clear.frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
            if !cards.isEmpty {
                deck
                if let open = cards.first(where: { $0.id == openID }) { figures(for: open) }
            }
        }
    }

    private var deck: some View {
        let openIndex = cards.firstIndex { $0.id == openID } ?? 0
        return VStack(spacing: peek - height) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isOpen = index == openIndex
                Button { tap(card) } label: {
                    CardFace(card: card, width: width)
                        .shadow(color: .black.opacity(isOpen ? 0.24 : 0.10),
                                radius: isOpen ? 16 : 5, y: isOpen ? 10 : 2)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Change how it looks", systemImage: "paintpalette") { onEdit(card) }
                }
                // A covered card sits a touch smaller, so the open one reads
                // as lifted out of the deck rather than merely uncovered.
                .scaleEffect(isOpen ? 1 : 0.97)
                // The open card on top. Above it each card covers the one
                // before; below it each card covers the one after, so the
                // ones underneath hang out by their bottom band.
                .zIndex(isOpen ? 1000 : (index < openIndex ? Double(index) : 999 - Double(index)))
                .accessibilityLabel(card.accessibilityName)
                .accessibilityAddTraits(isOpen ? .isSelected : [])
                .accessibilityHint(isOpen ? "Opens this month's charges on this card" : "Brings this card forward")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.x1)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: openID)
    }

    private func tap(_ card: MoneyCardSummary) {
        if card.id == openID { onOpen(card) } else { rememberedID = card.id }
    }

    /// The balance and the month on one ruled line. A hand-added card has
    /// no balance to report, so it shows the month alone.
    private func figures(for card: MoneyCardSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
            if let balance = card.balance {
                figure(card.kind == "Debit" ? "Available" : "Balance", balance)
            }
            figure("This month", card.monthSpend,
                   detail: card.monthCount == 1 ? "1 charge" : "\(card.monthCount) charges")
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.x1)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("money.deck.figures")
        .accessibilityLabel(figuresLabel(card))
    }

    private func figure(_ label: String, _ amount: Double, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).moneyEyebrow(scheme)
            HStack(alignment: .firstTextBaseline, spacing: Space.half) {
                MoneyFigure(amount: amount, size: 22)
                if let detail {
                    Text(detail)
                        .font(LifeOSType.caption)
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                        .lineLimit(1)
                }
            }
        }
    }

    private func figuresLabel(_ card: MoneyCardSummary) -> String {
        let spend = MoneyScreen.money(card.monthSpend) ?? ""
        let month = "\(spend) this month over \(card.monthCount) charge\(card.monthCount == 1 ? "" : "s")"
        guard let balance = card.balance, let figure = MoneyScreen.money(balance) else { return month }
        return "\(card.kind == "Debit" ? "Available" : "Balance") \(figure), \(month)"
    }
}
