import Foundation

/// The payment network printed in a card's corner.
public enum CardNetwork: String, Sendable, CaseIterable {
    case visa, mastercard, amex, discover, other

    public var displayName: String {
        switch self {
        case .visa: "VISA"
        case .mastercard: "mastercard"
        case .amex: "AMEX"
        case .discover: "DISCOVER"
        case .other: ""
        }
    }
}

/// How a face is drawn. Each is an original design in the spirit of the real
/// card, never the issuer's artwork: shipping a bank's card art in an App
/// Store app is a trademark problem, and a face in the right colour family is
/// already enough to tell five cards apart at a glance.
public struct CardFaceStyle: Sendable, Equatable {
    public enum Pattern: String, Sendable {
        /// A diagonal wash from `base` to `accent`.
        case gradient
        /// A plain face with a band of `accent` across it.
        case stripe
        /// A brushed sheen: `base` to `accent` with a highlight.
        case metal
        /// `base` only, with a thin `accent` rule near the bottom.
        case plain
        /// A dark `base` crossed by one glowing `accent` blade.
        case saber
    }

    /// `#RRGGBB`.
    public let base: String
    /// `#RRGGBB`.
    public let accent: String
    public let pattern: Pattern
    /// True when the face is light and its text should be dark.
    public let darkInk: Bool
    /// A serif wordmark, for the cards whose real face uses one.
    public let serif: Bool

    public init(base: String, accent: String, pattern: Pattern, darkInk: Bool = false, serif: Bool = false) {
        self.base = base
        self.accent = accent
        self.pattern = pattern
        self.darkInk = darkInk
        self.serif = serif
    }

    /// A face for a card the catalog does not know, in the colour the person
    /// picked.
    public static func plain(_ hex: String) -> CardFaceStyle {
        CardFaceStyle(base: hex, accent: hex, pattern: .gradient, darkInk: CardColor.isLight(hex))
    }

    /// The face before anyone has said anything about the card.
    public static let unknown = CardFaceStyle(base: "#3A3F47", accent: "#5A616B", pattern: .gradient)
}

/// One card the app knows how to draw.
public struct CardProduct: Sendable, Equatable, Identifiable {
    public let id: String
    /// The product, as it reads on the face: "Sapphire Preferred".
    public let name: String
    public let issuer: String
    public let network: CardNetwork
    public let face: CardFaceStyle
    /// Lowercased fragments of the account name a bank reports for this card.
    /// Checked in catalog order, so a more specific card sits above a broader
    /// one from the same issuer.
    let keywords: [String]
}

/// Every card the app ships a face for.
///
/// A plain list rather than stored rows, so adding a card is a code change
/// with no migration. Reward rates are deliberately not here yet: they belong
/// to the best-card advisor, and a stale rate is worse than none.
public enum CardCatalog {
    public static let all: [CardProduct] = [
        CardProduct(id: "chase-sapphire-reserve", name: "Sapphire Reserve", issuer: "Chase", network: .visa,
                    face: CardFaceStyle(base: "#0E1726", accent: "#2C3D5C", pattern: .metal),
                    keywords: ["sapphire reserve"]),
        CardProduct(id: "chase-sapphire-preferred", name: "Sapphire Preferred", issuer: "Chase", network: .visa,
                    face: CardFaceStyle(base: "#0A2A6B", accent: "#3D8BFF", pattern: .gradient),
                    keywords: ["sapphire"]),
        CardProduct(id: "chase-freedom", name: "Freedom", issuer: "Chase", network: .visa,
                    face: CardFaceStyle(base: "#123F9C", accent: "#58A6FF", pattern: .gradient),
                    keywords: ["freedom"]),
        CardProduct(id: "chase-debit", name: "Chase Debit", issuer: "Chase", network: .visa,
                    face: CardFaceStyle(base: "#0A0A0C", accent: "#FF2A2A", pattern: .saber),
                    keywords: ["total checking", "chase checking", "college checking", "chase college",
                               "secure banking", "premier plus"]),
        CardProduct(id: "discover-it", name: "Discover it", issuer: "Discover", network: .discover,
                    face: CardFaceStyle(base: "#B8862B", accent: "#F6DC8C", pattern: .gradient, darkInk: true),
                    keywords: ["discover"]),
        CardProduct(id: "apple-card", name: "Apple Card", issuer: "Goldman Sachs", network: .mastercard,
                    face: CardFaceStyle(base: "#F7F7F9", accent: "#DADBE0", pattern: .metal, darkInk: true),
                    keywords: ["apple card", "apple"]),
        CardProduct(id: "zolve", name: "Zolve", issuer: "Zolve", network: .mastercard,
                    face: CardFaceStyle(base: "#D62A1E", accent: "#FF8A3D", pattern: .gradient),
                    keywords: ["zolve"]),
        CardProduct(id: "banana-republic", name: "Banana Republic", issuer: "Barclays", network: .visa,
                    face: CardFaceStyle(base: "#EFE8DC", accent: "#2A2622", pattern: .plain, darkInk: true, serif: true),
                    keywords: ["banana republic", "banana"]),
        CardProduct(id: "amex-platinum", name: "Platinum", issuer: "American Express", network: .amex,
                    face: CardFaceStyle(base: "#C5C9CF", accent: "#EEF0F2", pattern: .metal, darkInk: true),
                    keywords: ["platinum card", "amex platinum"]),
        CardProduct(id: "amex-gold", name: "Gold", issuer: "American Express", network: .amex,
                    face: CardFaceStyle(base: "#B88F45", accent: "#E4C985", pattern: .metal, darkInk: true),
                    keywords: ["gold card", "amex gold"]),
        CardProduct(id: "capital-one-venture", name: "Venture", issuer: "Capital One", network: .visa,
                    face: CardFaceStyle(base: "#1D2A44", accent: "#44597E", pattern: .gradient),
                    keywords: ["venture"]),
        CardProduct(id: "capital-one-savor", name: "Savor", issuer: "Capital One", network: .mastercard,
                    face: CardFaceStyle(base: "#5E1A26", accent: "#9A3442", pattern: .gradient),
                    keywords: ["savor"]),
        CardProduct(id: "citi-double-cash", name: "Double Cash", issuer: "Citi", network: .mastercard,
                    face: CardFaceStyle(base: "#0E5FA8", accent: "#22A6CF", pattern: .gradient),
                    keywords: ["double cash"]),
        CardProduct(id: "wells-fargo-active-cash", name: "Active Cash", issuer: "Wells Fargo", network: .visa,
                    face: CardFaceStyle(base: "#9E1B1B", accent: "#D9472B", pattern: .gradient),
                    keywords: ["active cash"]),
        CardProduct(id: "bofa-customized-cash", name: "Customized Cash", issuer: "Bank of America", network: .visa,
                    face: CardFaceStyle(base: "#B30F2B", accent: "#1F3A70", pattern: .stripe),
                    keywords: ["customized cash"]),
        CardProduct(id: "bilt", name: "Bilt", issuer: "Wells Fargo", network: .mastercard,
                    face: CardFaceStyle(base: "#0D0D0D", accent: "#3A3A3A", pattern: .plain),
                    keywords: ["bilt"]),
    ]

    public static func product(id: String?) -> CardProduct? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The catalog card a bank's account name most likely is, or nil.
    /// "CHASE SAPPHIRE PREFERRED" finds Sapphire Preferred; "Total Checking"
    /// finds nothing, which draws a plain face rather than a wrong one.
    public static func guess(accountName: String) -> CardProduct? {
        let name = accountName.lowercased()
        return all.first { product in product.keywords.contains { name.contains($0) } }
    }

    /// Colours offered for a card the catalog does not know.
    public static let swatches = ["#3A3F47", "#0B2A5B", "#2F6DB5", "#1F7A5C", "#6B3FA0",
                                  "#9E1B1B", "#E07A1F", "#B88F45", "#F3EFE7", "#0D0D0D"]
}

public enum CardColor {
    /// Whether text on this colour should be dark. Relative luminance, so a
    /// cream face gets dark ink and a navy one gets light ink.
    public static func isLight(_ hex: String) -> Bool {
        guard let (r, g, b) = components(hex) else { return false }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6
    }

    /// 0...1 channels, or nil for anything that is not `#RRGGBB`.
    public static func components(_ hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }
}

extension MoneyAccount {
    /// The catalog card this account is: the person's choice, else a guess
    /// from the name the bank reports. A hand-added card is never guessed,
    /// because its name is whatever the person typed.
    public var cardProduct: CardProduct? {
        if let chosen = CardCatalog.product(id: cardProductID) { return chosen }
        return isManual ? nil : CardCatalog.guess(accountName: name)
    }

    /// How this card's face is drawn.
    public var faceStyle: CardFaceStyle {
        if let product = cardProduct { return product.face }
        if let faceColorHex { return .plain(faceColorHex) }
        return .unknown
    }
}
