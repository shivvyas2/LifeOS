import DesignSystem
import Persistence

/// The one place a sector meets a colour and an icon.
///
/// Kept out of `LifeSector` so the Persistence target never imports SwiftUI
/// or DesignSystem.
///
/// `ModuleHue` has six cases, not nine, and it is a shared design token used
/// by other screens: adding cases to it is a design decision that belongs to
/// the app's owner, not to this feature. So the nine sectors share the six
/// hues. `body` and `money` take the semantically matching hue; the other
/// seven are chosen so that no two cards touching in the board's three-column
/// (iPad) grid share a hue. That grid is the one optimised for. Collapsed to
/// two columns on iPhone, `soul` and `friends` end up adjacent and both read
/// `.nutrition` — the one place the two layouts disagree, and, with only six
/// hues for nine sectors, unavoidable without a mapping that would gerrymander
/// the icons and labels around it instead of matching them.
enum SectorPalette {
    static func hue(_ sector: LifeSector) -> ModuleHue {
        switch sector {
        case .family:  .activity
        case .romance: .recovery
        case .soul:    .nutrition
        case .friends: .nutrition
        case .growth:  .habits
        case .money:   .money
        case .mission: .activity
        case .body:    .body
        case .mind:    .recovery
        }
    }

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
