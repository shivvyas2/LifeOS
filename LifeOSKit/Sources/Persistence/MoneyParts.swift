import Foundation

/// A money amount split for display: sign, whole units, and cents.
///
/// The one rule is that rounding happens to the cent before anything is
/// split. Splitting a Double first and rounding each half lets a fraction of
/// .995 round up to 100 cents and render as "$19.100", and lets the float
/// noise in 0.1 + 0.2 leak into the cents. Money that displays as the wrong
/// number is the worst bug a finance screen can have, so this is in the kit
/// where it is tested rather than in a view where it is eyeballed.
public struct MoneyParts: Equatable, Sendable {
    /// True for money out. Zero is never negative.
    public let isNegative: Bool
    public let whole: Int
    /// 0...99.
    public let cents: Int

    public init(_ amount: Double) {
        // Round in the unit that has to carry: cents, as an integer.
        let totalCents = Int((abs(amount) * 100).rounded())
        self.isNegative = amount < 0 && totalCents > 0
        self.whole = totalCents / 100
        self.cents = totalCents % 100
    }

    /// Two digits, always: "05", not "5".
    public var centsText: String {
        cents < 10 ? "0\(cents)" : "\(cents)"
    }

    /// The magnitude with grouping, no sign: "1,894".
    public var wholeText: String {
        whole.formatted(.number.grouping(.automatic))
    }
}
