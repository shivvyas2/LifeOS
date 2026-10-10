import SwiftUI
import DesignSystem
import Persistence

/// A card, drawn.
///
/// One vertical fade in the card's own colour family and nothing else on the
/// face: the name top left with the kind and last four under it, the
/// contactless mark top right, the issuer bottom left and the network
/// bottom right. An original face in the spirit of the real one, never the
/// issuer's artwork. There is no chip. The fade and the name are what make
/// it a card, the way a matte metal card carries nothing but a wordmark.
///
/// The top band, the name and its eyebrow, is all a card shows when it is
/// covered in the deck, so everything that tells two cards apart sits there,
/// over the darkest part of the fade.
struct CardFace: View {
    let card: MoneyCardSummary
    var width: CGFloat = 156

    /// ID-1, the proportion of a real card.
    static func height(width: CGFloat) -> CGFloat { width / 1.586 }

    private var height: CGFloat { Self.height(width: width) }
    private var style: CardFaceStyle { card.style }
    private var ink: Color { style.darkInk ? Color.black.opacity(0.84) : Color.white.opacity(0.95) }
    private var quietInk: Color { style.darkInk ? Color.black.opacity(0.55) : Color.white.opacity(0.64) }
    private var radius: CGFloat { width * 0.075 }
    private var pad: CGFloat { width * 0.065 }
    /// A thumbnail carries the name and the network; nothing smaller than
    /// that survives at 64 points.
    private var isThumbnail: Bool { width < 140 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: style.fade.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: width * 0.008) {
                        Text(card.title)
                            .font(titleFont)
                            .tracking(-width * 0.0015)
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !isThumbnail {
                            Text(eyebrow)
                                .font(.system(size: max(9, width * 0.031), weight: .semibold).monospacedDigit())
                                .tracking(width * 0.0035)
                                .foregroundStyle(quietInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if !isThumbnail {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: width * 0.05, weight: .medium))
                            .foregroundStyle(quietInk)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    if !isThumbnail, let issuer = issuerMark {
                        Text(issuer)
                            .font(.system(size: width * 0.045, weight: .medium))
                            .foregroundStyle(ink.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(card.network.displayName)
                        .font(.system(size: width * (card.network == .mastercard ? 0.05 : 0.058),
                                      weight: .heavy).italic())
                        .foregroundStyle(ink.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(pad)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(style.darkInk ? Color.black.opacity(0.10) : Color.white.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityName)
    }

    /// The name is set the way the site sets a headline: medium and tight.
    /// A card whose real face is a serif wordmark keeps that.
    private var titleFont: Font {
        let size = width * (isThumbnail ? 0.1 : 0.068)
        return style.serif
            ? .system(size: size, weight: .regular, design: .serif)
            : .system(size: size, weight: .medium)
    }

    /// The issuer, bottom left, unless the name already says it: a Zolve is
    /// issued by Zolve and a Discover it by Discover, and a card that says
    /// so twice looks like a mistake.
    private var issuerMark: String? {
        let issuer = card.issuer
        guard !issuer.isEmpty,
              !card.title.localizedCaseInsensitiveContains(issuer),
              issuer.caseInsensitiveCompare(card.network.displayName) != .orderedSame else { return nil }
        return issuer
    }

    /// "CREDIT · •• 4821", the one line that separates two cards of the same
    /// product.
    private var eyebrow: String {
        [card.kind.uppercased(), card.mask.map { "•• \($0)" }].compactMap { $0 }.joined(separator: "  ·  ")
    }
}

/// The card on a transaction row: a thumbnail face with the last four.
///
/// Small enough to sit beside an amount on one line. An unknown card is a
/// dashed outline with a question mark, which is also the prompt to say which
/// card it was.
struct CardChip: View {
    let card: MoneyCardSummary?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let card {
                let style = card.style
                let fade = style.fade
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: fade.first ?? style.base),
                                                      Color(hex: fade.last ?? style.accent)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.black.opacity(style.darkInk ? 0.15 : 0), lineWidth: 0.5)
                    Text(card.mask ?? card.initials)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(style.darkInk ? Color.black.opacity(0.8) : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 2)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(MoneyPalette.quietInk(scheme),
                                      style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                    Text("?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                }
            }
        }
        .frame(width: 34, height: 22)
        .accessibilityLabel(card.map { "Paid with \($0.accessibilityName)" } ?? "Card unknown")
    }
}

extension Color {
    /// `#RRGGBB`, falling back to a neutral grey for anything else, so a bad
    /// stored colour draws a plain card rather than nothing.
    init(hex: String) {
        let (r, g, b) = CardColor.components(hex) ?? (0.23, 0.25, 0.28)
        self.init(red: r, green: g, blue: b)
    }
}
