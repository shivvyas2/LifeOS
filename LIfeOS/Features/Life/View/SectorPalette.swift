import SwiftUI
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

/// The nine sector tones for the board's stacked deck.
///
/// Separate from `hue` rather than replacing it. `ModuleHue` is a shared design
/// token with six cases, used by `SectorDetailScreen` and `MonthlyCloseScreen`
/// as well as here, and widening it is a decision about the whole app. These
/// nine live in the Life feature and answer a narrower question: in a deck
/// where cards physically overlap, every neighbour must be a different colour,
/// and six values cannot do that for nine sectors.
///
/// One muted earth family, so nine distinct cards still read as one deck. Where
/// a sector has an obvious temperature the tone follows it: money is pine,
/// romance is a dusty rose, mind is the one cool slate in the set.
extension SectorPalette {
    static func tone(_ sector: LifeSector) -> AdaptiveColor {
        switch sector {
        case .family:  AdaptiveColor(light: Color(red: 0.804, green: 0.647, blue: 0.545),
                                     dark:  Color(red: 0.290, green: 0.212, blue: 0.169))
        case .romance: AdaptiveColor(light: Color(red: 0.808, green: 0.612, blue: 0.596),
                                     dark:  Color(red: 0.298, green: 0.196, blue: 0.196))
        case .soul:    AdaptiveColor(light: Color(red: 0.667, green: 0.588, blue: 0.643),
                                     dark:  Color(red: 0.235, green: 0.196, blue: 0.235))
        case .friends: AdaptiveColor(light: Color(red: 0.643, green: 0.702, blue: 0.639),
                                     dark:  Color(red: 0.196, green: 0.251, blue: 0.204))
        case .growth:  AdaptiveColor(light: Color(red: 0.706, green: 0.718, blue: 0.549),
                                     dark:  Color(red: 0.243, green: 0.251, blue: 0.173))
        case .money:   AdaptiveColor(light: Color(red: 0.545, green: 0.663, blue: 0.596),
                                     dark:  Color(red: 0.157, green: 0.235, blue: 0.196))
        case .mission: AdaptiveColor(light: Color(red: 0.867, green: 0.729, blue: 0.510),
                                     dark:  Color(red: 0.302, green: 0.243, blue: 0.149))
        case .body:    AdaptiveColor(light: Color(red: 0.831, green: 0.600, blue: 0.478),
                                     dark:  Color(red: 0.302, green: 0.204, blue: 0.145))
        case .mind:    AdaptiveColor(light: Color(red: 0.620, green: 0.667, blue: 0.722),
                                     dark:  Color(red: 0.188, green: 0.220, blue: 0.251))
        }
    }

    /// One ink for all nine cards, not one per tone. Every tone above is a
    /// desaturated mid-value chosen so a single ink clears contrast on all of
    /// them, and a shared ink is what stops nine cards reading as nine designs.
    static let cardInk = AdaptiveColor(
        light: Color(red: 0.18, green: 0.15, blue: 0.13),
        dark:  Color(red: 0.93, green: 0.91, blue: 0.88)
    )
}
