import SwiftUI
import DesignSystem
import Persistence

/// A card, drawn.
///
/// An original face in the spirit of the real one: the colour family, the
/// pattern and the wordmark weight, never the issuer's artwork. At the width
/// of the cards strip that is plenty to tell a Sapphire from a Discover
/// without reading a word.
struct CardFace: View {
    let card: MoneyCardSummary
    var width: CGFloat = 156

    private var height: CGFloat { width / 1.586 }
    private var style: CardFaceStyle { card.style }
    private var ink: Color { style.darkInk ? Color.black.opacity(0.82) : Color.white.opacity(0.94) }
    private var quietInk: Color { ink.opacity(0.62) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.issuer.uppercased())
                        .font(.system(size: width * 0.058, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(quietInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                Text(card.title)
                    .font(style.serif
                          ? .system(size: width * 0.1, weight: .regular, design: .serif)
                          : .system(size: width * 0.095, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                chip
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text(card.mask.map { "•••• \($0)" } ?? " ")
                        .font(.system(size: width * 0.07, weight: .medium).monospacedDigit())
                        .foregroundStyle(ink)
                    Spacer(minLength: 4)
                    Text(card.network.displayName)
                        .font(.system(size: width * (card.network == .mastercard ? 0.065 : 0.075),
                                      weight: .heavy).italic())
                        .foregroundStyle(quietInk)
                        .lineLimit(1)
                }
            }
            .padding(width * 0.07)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
            .strokeBorder(Color.black.opacity(style.darkInk ? 0.10 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityName)
    }

    /// The contact chip, a quiet gold square. It is what makes a coloured
    /// rectangle read as a card at all.
    private var chip: some View {
        RoundedRectangle(cornerRadius: width * 0.018, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#E7CF8F"), Color(hex: "#B89551")],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: width * 0.15, height: width * 0.11)
            .opacity(0.9)
    }

    @ViewBuilder
    private var background: some View {
        let base = Color(hex: style.base)
        let accent = Color(hex: style.accent)
        switch style.pattern {
        case .gradient:
            LinearGradient(colors: [base, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .metal:
            ZStack {
                LinearGradient(colors: [base, accent, base], startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .rotationEffect(.degrees(25))
                    .scaleEffect(1.6)
            }
        case .stripe:
            ZStack(alignment: .bottom) {
                base
                accent.frame(height: height * 0.16).offset(y: -height * 0.30)
            }
        case .plain:
            ZStack(alignment: .bottom) {
                base
                accent.frame(height: 1.5).padding(.horizontal, width * 0.07).offset(y: -height * 0.27)
            }
        case .saber:
            SaberField(base: base, blade: accent, length: width * 1.5, thickness: max(2, height * 0.025))
        }
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
                ZStack {
                    // A striped or plain face is its base colour; its accent
                    // is a thin band, and washed across a thumbnail it reads
                    // as a different card.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: style.base),
                                                      Color(hex: style.pattern == .gradient || style.pattern == .metal
                                                            ? style.accent : style.base)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if style.pattern == .stripe || style.pattern == .saber {
                        Color(hex: style.accent).frame(height: 4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
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

/// A dark field crossed by one glowing blade: a white core in a halo of
/// the blade's colour. The Chase debit face.
struct SaberField: View {
    let base: Color
    let blade: Color
    let length: CGFloat
    let thickness: CGFloat
    /// How far below centre the blade crosses, so it can clear the text.
    var drop: CGFloat = 0
    var angle: Double = -24

    var body: some View {
        ZStack {
            LinearGradient(colors: [base, Color(red: 0.12, green: 0.02, blue: 0.03), base],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Capsule()
                .fill(blade)
                .frame(width: length, height: thickness)
                .overlay(Capsule().fill(Color.white.opacity(0.9)).frame(height: thickness * 0.35))
                .shadow(color: blade, radius: thickness * 1.5)
                .shadow(color: blade.opacity(0.6), radius: thickness * 5)
                .rotationEffect(.degrees(angle))
                .offset(y: drop)
        }
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
