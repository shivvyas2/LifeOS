import Foundation

/// A dialling code paired with its country, for the phone field.
public struct DialCountry: Identifiable, Equatable, Sendable {
    public let id: String       // ISO region code
    public let name: String
    public let dial: String

    public init(id: String, name: String, dial: String) {
        self.id = id; self.name = name; self.dial = dial
    }

    public var flag: String {
        id.unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = UnicodeScalar(127_397 + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
    }
}

public enum DialCountries {
    /// Phone OTP is only sent to the US and India.
    public static let otpRegions: Set<String> = ["US", "IN"]
    /// Built from the system's region list so it is complete and localised,
    /// rather than a hand-typed subset that omits someone's country.
    public static let all: [DialCountry] = {
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

    public static func dial(for region: String) -> String { knownDialCodes[region] ?? "+1" }

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
