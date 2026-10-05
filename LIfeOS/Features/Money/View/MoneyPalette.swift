import SwiftUI
import DesignSystem
import Persistence

/// The Money tab's paper and ink.
///
/// These are the app's own canvas and text colours now, not a palette of
/// their own. Money used to sit on pure white with six pastel band tints,
/// and side by side with any other tab it looked like a different product.
/// The names stay because forty call sites say `MoneyPalette.ink`, and what
/// they mean has not changed.
enum MoneyPalette {
    static let paper = LifeOSTokens.canvas
    static let ink = LifeOSTokens.primaryText

    /// Ink at reading weight for secondary lines.
    static func quietInk(_ scheme: ColorScheme) -> Color {
        Editorial.quietInk(scheme)
    }
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
        // The split lives in the kit (`MoneyParts`) where the carry and the
        // float noise are tested. This view only decides how to draw it.
        let parts = MoneyParts(amount)
        let sign = showsSign ? (parts.isNegative ? "-" : "+") : ""

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(sign)$\(parts.wholeText)")
            Text(".\(parts.centsText)")
                .foregroundStyle(MoneyPalette.ink.resolve(scheme).opacity(0.35))
        }
        // Light at headline sizes, the editorial figure; medium below 28pt,
        // where a light stroke on a row amount goes thin and grey.
        .font(size >= 28 ? Editorial.figure(size) : .system(size: size, weight: .medium))
        .tracking(size >= 28 ? Editorial.figureTracking(size) : 0)
        .monospacedDigit()
        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityLabel("\(sign)\(parts.wholeText) dollars \(parts.cents) cents")
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
