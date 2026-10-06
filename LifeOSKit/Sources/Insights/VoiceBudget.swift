import Foundation

/// How much premium voice an account has used this month, in characters
/// sent for synthesis. Speech is billed per character, so this is the unit
/// the bill is in. A month is the account's own calendar month; the key
/// names it so a new month starts at zero without anything being reset.
public struct VoiceBudget: @unchecked Sendable {
    /// About forty narrated answers at the per-answer cap, and about a
    /// dollar fifty at the published Flash rate: inside the cost ceiling with
    /// room for the rest of the stack.
    public static let monthlyAllowance = 30_000

    // `UserDefaults` is thread-safe, which is what the unchecked conformance
    // vouches for.
    private let defaults: UserDefaults
    private let calendar: Calendar

    public init(defaults: UserDefaults, calendar: Calendar = .current) {
        self.defaults = defaults; self.calendar = calendar
    }

    public static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "voice.characters.%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public func used(now: Date = .now) -> Int {
        defaults.integer(forKey: Self.key(for: now, calendar: calendar))
    }

    public func remaining(now: Date = .now) -> Int {
        max(0, Self.monthlyAllowance - used(now: now))
    }

    public func debit(_ characters: Int, now: Date = .now) {
        let key = Self.key(for: now, calendar: calendar)
        defaults.set(defaults.integer(forKey: key) + max(0, characters), forKey: key)
    }
}
