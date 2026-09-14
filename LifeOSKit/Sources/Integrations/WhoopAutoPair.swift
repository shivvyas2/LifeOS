import Foundation

/// Which discovered sensor to pair without asking. Only a WHOOP, and only
/// when there is exactly one: another person's strap in a gym is not a
/// reading this person owns.
public enum WhoopAutoPair {
    public enum Choice: Equatable, Sendable { case none, one(Int), several }

    public static func choice(among names: [String]) -> Choice {
        let matches = names.indices.filter { names[$0].localizedCaseInsensitiveContains("whoop") }
        switch matches.count {
        case 0: return .none
        case 1: return .one(matches[0])
        default: return .several
        }
    }
}
