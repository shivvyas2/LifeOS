import SwiftUI
import DesignSystem

/// The Money tab's own palette.
///
/// Separate from `LifeOSTokens` and from `ModuleHue` on purpose. Those carry
/// the whole app's identity on a warm off-white canvas; this screen is built
/// the other way round, as full-bleed pastel bands on pure white, and mixing
/// the two vocabularies made every band look like a card that had lost its
/// margins.
///
/// The pastels sit a step darker and a step more saturated than the reference
/// screens this was drawn from. On a real phone at real brightness the paler
/// versions washed out to grey, and the whole point of a band is that it reads
/// as a block of colour rather than as a tint.
enum MoneyPalette {
    /// Pure white, not the app's warm canvas: the bands supply all the colour
    /// here, and a warm ground under a cool pastel reads as a printing error.
    static let paper = AdaptiveColor(light: .white, dark: Color(white: 0.07))

    /// One ink across every band. Nine bands in nine inks would be nine
    /// designs; a single near-black that clears contrast on all of them is
    /// what holds the screen together.
    static let ink = AdaptiveColor(
        light: Color(red: 0.10, green: 0.11, blue: 0.09),
        dark: Color(red: 0.95, green: 0.95, blue: 0.93)
    )

    /// Ink at reading weight for secondary lines inside a band.
    static func quietInk(_ scheme: ColorScheme) -> Color {
        ink.resolve(scheme).opacity(scheme == .dark ? 0.62 : 0.55)
    }

    static let sage = AdaptiveColor(
        light: Color(red: 0.71, green: 0.76, blue: 0.66),
        dark:  Color(red: 0.26, green: 0.31, blue: 0.24)
    )
    static let butter = AdaptiveColor(
        light: Color(red: 0.91, green: 0.82, blue: 0.42),
        dark:  Color(red: 0.35, green: 0.31, blue: 0.13)
    )
    static let clay = AdaptiveColor(
        light: Color(red: 0.89, green: 0.53, blue: 0.38),
        dark:  Color(red: 0.40, green: 0.22, blue: 0.15)
    )
    static let mint = AdaptiveColor(
        light: Color(red: 0.64, green: 0.81, blue: 0.72),
        dark:  Color(red: 0.20, green: 0.32, blue: 0.27)
    )
    static let mist = AdaptiveColor(
        light: Color(red: 0.68, green: 0.76, blue: 0.86),
        dark:  Color(red: 0.21, green: 0.27, blue: 0.34)
    )
    static let stone = AdaptiveColor(
        light: Color(red: 0.85, green: 0.84, blue: 0.80),
        dark:  Color(red: 0.20, green: 0.20, blue: 0.19)
    )
}

// MARK: - Type

extension View {
    /// The tiny tracked uppercase label the reference screens hang everything
    /// from. Always paired with a numeral; never used as body text.
    func moneyEyebrow(_ scheme: ColorScheme) -> some View {
        self.font(LifeOSType.eyebrow)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(MoneyPalette.quietInk(scheme))
    }
}

/// A figure at display size, with the decimal ghosted.
///
/// The reference sets every amount as `$1,894.00` with the cents in a
/// lighter tint, which is what stops a wall of numbers reading as a
/// spreadsheet: the eye lands on the magnitude and the cents stay available
/// without competing.
struct MoneyFigure: View {
    let amount: Double
    var size: CGFloat = 44
    var showsSign = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Round to cents FIRST, then split. Splitting before rounding lets
        // .995 carry into a fraction of 100 and render as "$19.100". Money
        // that displays as the wrong number is the worst bug this screen
        // could have, so the arithmetic is done in the order that carries.
        let magnitude = (abs(amount) * 100).rounded() / 100
        let whole = Int(magnitude)
        let cents = Int(((magnitude - Double(whole)) * 100).rounded())
        let sign = showsSign ? (amount < 0 ? "-" : "+") : ""

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(sign)$\(whole.formatted(.number.grouping(.automatic)))")
            Text(".\(cents < 10 ? "0" : "")\(cents)")
                .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.35))
        }
        .font(LifeOSType.numeral(size))
        .monospacedDigit()
        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The hairline fill the references use instead of a solid progress bar.
///
/// A solid bar at these sizes reads as a heavy block and fights the band it
/// sits on. Pinstripes carry the same proportion while staying visibly a
/// texture, which is what lets a band hold two of them without turning into a
/// chart.
struct Pinstripes: View {
    var fraction: Double
    var spacing: CGFloat = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let count = max(Int(proxy.size.width / spacing), 1)
            let lit = Int((Double(count) * min(max(fraction, 0), 1)).rounded())
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(MoneyPalette.ink.resolve(scheme)
                            .opacity(index < lit ? 0.55 : 0.13))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
