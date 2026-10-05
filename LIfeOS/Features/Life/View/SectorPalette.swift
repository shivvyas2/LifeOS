import SwiftUI
import Persistence

/// The one place a sector meets an icon.
///
/// Kept out of `LifeSector` so the Persistence target never imports SwiftUI
/// or DesignSystem. The sectors used to carry colours too; the editorial
/// theme draws every one of them in ink on paper, so only the icon is left.
enum SectorPalette {
    static func icon(_ sector: LifeSector) -> String {
        switch sector {
        case .family:  "house.fill"
        case .romance: "heart.fill"
        case .soul:    "sparkles"
        case .friends: "person.2.fill"
        case .growth:  "chart.line.uptrend.xyaxis"
        case .money:   "dollarsign"
        case .mission: "target"
        case .body:    "figure.run"
        case .mind:    "brain.head.profile"
        }
    }
}
