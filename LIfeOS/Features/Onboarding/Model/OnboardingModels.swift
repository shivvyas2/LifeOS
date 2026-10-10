import Foundation
import DesignSystem
import Integrations

/// Where the user is in signup. A single enum rather than a pile of booleans,
/// so an impossible combination cannot be represented.
enum OnboardingStep: Equatable {
    case intro
    case identity            // phone or email
    case code                // OTP (phone or email)
    case profile             // name, country
    case connections         // Whoop and Health, all optional
    case signedIn            // returning user; nothing left to ask
}

/// One page of the intro. Kept as data so the pager is a loop, not five
/// hand-written screens that drift apart.
struct IntroPage: Identifiable, Equatable {
    let id: Int
    let headline: String
    let body: String

    var category: String {
        switch id {
        case 1: "YOUR HEALTH"
        case 2: "YOUR MONEY"
        case 3: "YOUR EVERYDAY"
        case 4: "CONNECTED TO YOU"
        default: "A HOME FOR YOUR LIFE"
        }
    }

}

extension IntroPage {
    /// The pitch: this is not a fitness app. Each page is one domain, in the
    /// order the tabs appear, so the intro maps onto the interface.
    static let all: [IntroPage] = [
        IntroPage(
            id: 0,
            headline: "A little more life.\nA lot less juggling.",
            body: "Your health, money, habits and plans.\nOne home for everything that makes you, you."
        ),
        IntroPage(
            id: 1,
            headline: "Feel more in tune\nwith you.",
            body: "Connect Apple Health and WHOOP to see your sleep, movement and recovery together."
        ),
        IntroPage(
            id: 2,
            headline: "A clearer picture.\nA calmer mind.",
            body: "Make sense of what comes in, what goes out and what you keep. All in one place."
        ),
        IntroPage(
            id: 3,
            headline: "Small steps.\nMore you.",
            body: "Make room for your habits, goals and ideas. Watch the little things add up, day by day."
        ),
        IntroPage(
            id: 4,
            headline: "Connect once.\nCome back to everything.",
            body: "Link WHOOP, Google Fitbit or your bank through Plaid. Your saved connections stay with your LifeOS account."
        ),
    ]
}

/// The profile LifeOS asks for after sign-in. Sign-in itself (channel,
/// address, code) lives in AccountUI's `SignInDraft`, shared with the
/// companion apps.
struct ProfileDraft: Equatable {
    var firstName = ""
    var lastName = ""
    var country = Locale.current.region?.identifier ?? "US"
    /// Set alongside `country` by the country picker; not sent anywhere.
    var dialCode = "+1"

    /// A picked avatar, already downsized. Held as data rather than an image
    /// so the draft stays a value type and can be compared for equality.
    var photo: Data?
    var birthDate: Date?
    /// Always centimetres internally, whatever the field shows. Storing the
    /// number in whichever unit the user happened to be typing is how a height
    /// ends up silently wrong after a locale change.
    var heightCM: Double?
    var gender: Gender = .unspecified

    /// Name is the only requirement. Everything else on the profile step
    /// sharpens what the app can say and none of it is worth blocking someone
    /// at the door for: a signup that demands a birthday before it will let
    /// you in is a signup people abandon.
    var canFinishProfile: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// How someone describes themselves, asked once so the app can address them
/// properly rather than in the awkward neutral it would otherwise use forever.
///
/// Not a biological-sex field wearing a friendlier label. If health baselines
/// ever need that, it is a different question with different answers and it
/// belongs next to the health data, not in the signup form.
///
/// "Prefer not to say" is the default and a real answer: the app records
/// nothing rather than a guess, and everything downstream already copes with
/// having no value here.
enum Gender: String, CaseIterable, Identifiable, Equatable {
    case unspecified
    case woman
    case man
    case nonBinary = "non_binary"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: "Prefer not to say"
        case .woman:       "Woman"
        case .man:         "Man"
        case .nonBinary:   "Non-binary"
        }
    }

    /// What goes to the server. Nil for unspecified, so nothing is written.
    var stored: String? { self == .unspecified ? nil : rawValue }
}
