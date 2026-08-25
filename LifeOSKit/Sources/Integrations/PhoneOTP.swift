import Foundation

/// E.164 checks used before an OTP is requested.
///
/// The Edge Function enforces the same rules. This copy exists so the form
/// can refuse a number we will never send to, without a round trip.
public enum PhoneOTP: Sendable {
    /// Digits only, with a leading `+`.
    public static func normalized(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 8, digits.count <= 15 else { return nil }
        return "+" + digits
    }

    public static func isAcceptable(_ raw: String) -> Bool {
        guard let e164 = normalized(raw) else { return false }
        let digits = String(e164.dropFirst())
        if digits.hasPrefix("91") {
            // Indian mobiles: +91 then 10 digits starting 6–9.
            let national = String(digits.dropFirst(2))
            guard national.count == 10, let first = national.first, ("6"..."9").contains(first) else {
                return false
            }
            return true
        }
        if digits.hasPrefix("1") {
            // USA / NANP: +1 then 10 digits. Includes the local test number.
            return digits.count == 11
        }
        return false
    }

    /// Country + early national digits. Used server-side to catch SMS pumping
    /// against a neighbouring range of numbers.
    public static func pumpingPrefix(_ raw: String) -> String? {
        guard let e164 = normalized(raw) else { return nil }
        let digits = String(e164.dropFirst())
        if digits.hasPrefix("91"), digits.count >= 6 {
            return String(digits.prefix(6))
        }
        return String(digits.prefix(min(5, digits.count)))
    }
}
