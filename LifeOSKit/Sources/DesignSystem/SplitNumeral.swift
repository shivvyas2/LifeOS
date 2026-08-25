import Foundation

/// A numeral split the way the reference paints "120 / 80": a huge hero
/// figure and a quieter remainder. Sleep duration uses the same shape so
/// hours do not collapse into a cramped "7h 12m" string on the card.
public struct SplitNumeral: Equatable, Sendable {
    public let hero: String
    public let remainder: String?

    public init(hero: String, remainder: String? = nil) {
        self.hero = hero
        self.remainder = remainder
    }

    /// Hours become the hero. Exact hours drop a "0m"; under an hour the
    /// minutes themselves are the hero.
    public static func sleep(minutes: Int) -> SplitNumeral {
        if minutes < 60 {
            return SplitNumeral(hero: "\(minutes)", remainder: "m")
        }
        let hours = minutes / 60
        let leftover = minutes % 60
        if leftover == 0 {
            return SplitNumeral(hero: "\(hours)", remainder: "h")
        }
        return SplitNumeral(hero: "\(hours)", remainder: "h \(leftover)m")
    }
}
