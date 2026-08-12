import Foundation
import DesignSystem
import Integrations

/// Where the user is in signup. A single enum rather than a pile of booleans,
/// so an impossible combination cannot be represented.
enum OnboardingStep: Equatable {
    case intro
    case identity            // phone or email
    case code                // OTP (phone)
    case linkSent            // magic link (email)
    case profile             // name, country
    case connections         // Whoop and Health, all optional
}

/// One page of the intro. Kept as data so the pager is a loop, not five
/// hand-written screens that drift apart.
struct IntroPage: Identifiable, Equatable {
    let id: Int
    let hue: ModuleHue
    let headline: String
    let body: String
}

extension IntroPage {
    /// The pitch: this is not a fitness app. Each page is one domain, in the
    /// order the tabs appear, so the intro maps onto the interface.
    static let all: [IntroPage] = [
        IntroPage(
            id: 0, hue: .body,
            headline: "Everything about your life,\nin one place",
            body: "Health, money, habits and plans, tracked together instead of scattered across six apps."
        ),
        IntroPage(
            id: 1, hue: .activity,
            headline: "Your body,\nunderstood",
            body: "Steps, sleep, weight and recovery from Whoop and Apple Health, rolled into one day."
        ),
        IntroPage(
            id: 2, hue: .money,
            headline: "Your money,\nhonestly",
            body: "Income, spending and what you actually keep. No invented numbers. A blank stays blank."
        ),
        IntroPage(
            id: 3, hue: .habits,
            headline: "Your goals\nand your days",
            body: "Habits, goals, notes and plans. One dot per day, so a month is readable at a glance."
        ),
    ]
}

/// What the user types during signup, before any of it is trusted.
struct SignupDraft: Equatable {
    var channel: SupabaseAuthChannel = .phone
    var phone = ""
    var dialCode = "+1"
    var email = ""
    var code = ""
    var firstName = ""
    var lastName = ""
    var country = Locale.current.region?.identifier ?? "US"

    /// E.164, which is what Supabase expects for SMS.
    var e164: String { dialCode + phone.filter(\.isNumber) }

    var destination: String { channel == .phone ? e164 : email.trimmingCharacters(in: .whitespaces) }

    var canSendCode: Bool {
        channel == .phone
            ? phone.filter(\.isNumber).count >= 7
            : email.contains("@") && email.contains(".")
    }

    var canVerify: Bool { code.filter(\.isNumber).count >= 6 }

    var canFinishProfile: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// A dialling code paired with its country, for the phone field.
struct DialCountry: Identifiable, Equatable {
    let id: String       // ISO region code
    let name: String
    let dial: String

    var flag: String {
        id.unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = UnicodeScalar(127_397 + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }
}

enum DialCountries {
    /// Built from the system's region list so it is complete and localised,
    /// rather than a hand-typed subset that omits someone's country.
    static let all: [DialCountry] = {
        let dialCodes = knownDialCodes
        return Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty }
            .compactMap { region in
                guard let dial = dialCodes[region.identifier],
                      let name = Locale.current.localizedString(forRegionCode: region.identifier)
                else { return nil }
                return DialCountry(id: region.identifier, name: name, dial: dial)
            }
            .sorted { $0.name < $1.name }
    }()

    static func dial(for region: String) -> String { knownDialCodes[region] ?? "+1" }

    /// The common set. A country missing here simply has no dial code offered,
    /// which is better than guessing one and sending an SMS into the void.
    private static let knownDialCodes: [String: String] = [
        "US": "+1", "CA": "+1", "GB": "+44", "IE": "+353", "AU": "+61", "NZ": "+64",
        "IN": "+91", "PK": "+92", "BD": "+880", "LK": "+94", "NP": "+977",
        "AE": "+971", "SA": "+966", "QA": "+974", "KW": "+965", "BH": "+973", "OM": "+968",
        "DE": "+49", "FR": "+33", "ES": "+34", "IT": "+39", "PT": "+351", "NL": "+31",
        "BE": "+32", "CH": "+41", "AT": "+43", "SE": "+46", "NO": "+47", "DK": "+45",
        "FI": "+358", "IS": "+354", "PL": "+48", "CZ": "+420", "GR": "+30", "TR": "+90",
        "RU": "+7", "UA": "+380", "RO": "+40", "HU": "+36",
        "JP": "+81", "KR": "+82", "CN": "+86", "HK": "+852", "TW": "+886", "SG": "+65",
        "MY": "+60", "TH": "+66", "VN": "+84", "PH": "+63", "ID": "+62",
        "ZA": "+27", "NG": "+234", "KE": "+254", "EG": "+20", "MA": "+212", "GH": "+233",
        "BR": "+55", "MX": "+52", "AR": "+54", "CL": "+56", "CO": "+57", "PE": "+51",
        "IL": "+972", "JO": "+962", "LB": "+961",
    ]
}
