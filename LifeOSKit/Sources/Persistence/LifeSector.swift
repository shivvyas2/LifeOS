import Foundation

/// The nine sectors of life this app scores.
///
/// Raw values are written to the store, so a case may be added but never
/// renamed: a rename orphans every score already recorded against it.
public enum LifeSector: String, Codable, Sendable, CaseIterable {
    case family, romance, soul, friends, growth, money, mission, body, mind

    public var title: String {
        switch self {
        case .family:  "Family"
        case .romance: "Romance"
        case .soul:    "Soul"
        case .friends: "Friends"
        case .growth:  "Growth"
        case .money:   "Money"
        case .mission: "Mission"
        case .body:    "Body"
        case .mind:    "Mind"
        }
    }

    /// Reading order on the board. Kept separate from `allCases` so that
    /// adding a sector later cannot silently reshuffle the grid.
    public static let boardOrder: [LifeSector] = [
        .family, .romance, .soul,
        .friends, .growth, .money,
        .mission, .body, .mind,
    ]
}
