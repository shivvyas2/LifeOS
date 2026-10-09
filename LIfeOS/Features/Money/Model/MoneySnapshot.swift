import Foundation
import Persistence

struct MoneySnapshot: Equatable {
    var income: Double = 0
    var expenses: Double = 0
    var net: Double = 0
    /// Nil when there is no income: undefined, not zero.
    var savingsRate: Double?
    var netWorth: Double?
    var recent: [MoneyRow] = []
    var budgets: [BudgetBandRow] = []
    var unclaimed: [UnclaimedBandRow] = []
    /// Where the money actually went, largest first. Derived from `recent`
    /// rather than stored, because a category total that disagreed with the
    /// transactions under it would be the screen contradicting itself.
    var categories: [CategoryRow] = []
    /// Merchants that bill every month. Detected from history, not declared:
    /// nothing in the data says "subscription".
    var recurring: [RecurringRow] = []
    /// This week, from the calendar's first weekday, for the seven-bar chart.
    var week: [DaySpend] = []
    /// Category shares folded for the donut.
    var slices: [CategorySlice] = []
    /// How many charges make up `expenses`.
    var spendCount: Int = 0
    /// What the month is saving towards, when a target has been set.
    var goal: SavingsGoal?
    var monthLabel: String = ""
    var isConnected = false
    /// A bank is linked, whether or not any transaction has arrived yet.
    var hasConnectedBank = false
    /// Linked, but Plaid is still assembling the history. Distinct from an
    /// empty month, and the screen must not present it as one.
    var isFetchingHistory = false
    /// Set when a bank has invalidated its stored login.
    var reconnectPrompt: String?
    var lastSyncedAt: Date?
    /// The cards strip: credit cards, hand-added cards, and any other account
    /// that paid for something this month, most spent first.
    var cards: [MoneyCardSummary] = []
    /// Every account a charge could be put on, for the card picker.
    var pickableCards: [MoneyCardSummary] = []

    var verdict: String {
        guard let savingsRate else { return "No income logged" }
        return savingsRate >= 0.2 ? "On track" : (savingsRate >= 0 ? "Tight" : "Overspending")
    }
}

struct MoneyRow: Equatable, Identifiable {
    let id: UUID
    let merchant: String
    let category: String?
    let amount: Double
    let date: Date
    let pending: Bool
    /// The merchant's mark, from Plaid or borrowed from a sibling row for the
    /// same merchant. Nil shows the category glyph.
    var logoURL: URL? = nil
    var accountName: String? = nil
    /// The card that paid, after the person's choices are applied. Nil when
    /// nobody, Plaid included, has said.
    var card: MoneyCardSummary? = nil
}

/// One card as the screens draw it: the face, the name, and the month on it.
struct MoneyCardSummary: Equatable, Identifiable, Hashable {
    /// `MoneyAccount.cardKey`.
    let id: String
    /// What the face says: the catalog product's name, else the account name.
    let title: String
    let issuer: String
    let mask: String?
    let network: CardNetwork
    let style: CardFaceStyle
    let productID: String?
    let isManual: Bool
    /// The bank's own name for the account, which can differ from `title`.
    let accountName: String
    var monthSpend: Double = 0
    var monthCount: Int = 0
    /// What the bank last reported: owed on a card, available in checking.
    /// Nil for a hand-added card, which has no balance to report.
    let balance: Double?
    /// "Credit" or "Debit", for the wallet card's second line.
    let kind: String

    var initials: String {
        String(title.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    var accessibilityName: String {
        [title, mask.map { "ending \($0)" }].compactMap { $0 }.joined(separator: " ")
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(_ account: MoneyAccount) {
        let product = account.cardProduct
        id = account.cardKey
        title = product?.name ?? account.name
        issuer = product?.issuer ?? ""
        mask = account.mask
        network = product?.network ?? .other
        style = account.faceStyle
        productID = account.cardProductID
        isManual = account.isManual
        accountName = account.name
        let isDebit = account.type == "depository"
        balance = account.isManual ? nil : (isDebit ? account.availableBalance ?? account.currentBalance
                                                    : account.currentBalance)
        kind = isDebit ? "Debit" : "Credit"
    }
}

struct BudgetBandRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    let limit: Double
    let spent: Double

    var isOver: Bool { spent > limit }
    var progress: Double { limit > 0 ? min(spent / limit, 1) : 0 }
}

struct UnclaimedBandRow: Equatable, Identifiable {
    /// The claim key, or "uncategorised" for the nil key.
    let id: String
    let label: String
    let amount: Double
    let count: Int
}

/// One spending category with its share of the month.
struct CategoryRow: Equatable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    /// Share of total spend, 0...1. Precomputed so the view never divides by a
    /// total it would have to be handed separately and could get wrong.
    let share: Double
    /// How many charges make it up.
    let count: Int
}

/// A merchant that bills every month.
struct RecurringRow: Equatable, Identifiable {
    let id: String
    let merchant: String
    let category: String?
    let amount: Double
    /// How many distinct months this merchant has charged in.
    let months: Int
    var logoURL: URL? = nil
}

/// A savings target and how far along it is.
struct SavingsGoal: Equatable {
    let name: String
    let target: Double
    let saved: Double

    /// 0...1, clamped: a goal passed is full, never more than full, because a
    /// bar drawn past its own end reads as a rendering bug.
    var progress: Double { target > 0 ? min(saved / target, 1) : 0 }
    var remaining: Double { max(target - saved, 0) }
    var isMet: Bool { saved >= target && target > 0 }
}

/// Something costing more than it should this month.
///
/// Assembled by the view model from budgets and recurring spend, so the screen
/// has one list to render rather than three rules to apply.
struct PressurePoint: Equatable, Identifiable {
    let id: String
    let title: String
    /// A plain sentence saying what is wrong, in the app's voice.
    let detail: String
    let amount: Double
}

/// One day of the current week, for the seven-bar chart.
struct DaySpend: Equatable, Identifiable {
    let date: Date
    let amount: Double
    let isFuture: Bool
    let isToday: Bool

    var id: Date { date }
}

/// One slice of the donut. At most five categories and an "Other".
struct CategorySlice: Equatable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    let share: Double
    /// Ink opacity for the slice and for the swatch on the band that names it.
    /// Largest slice darkest: the donut is a magnitude, not a set of
    /// identities, and the money palette has one ink.
    let opacity: Double
    let isOther: Bool

    /// The opacity steps, largest slice first. Six, because `fold` keeps five
    /// and adds one.
    static let steps: [Double] = [0.92, 0.72, 0.54, 0.40, 0.28, 0.16]
}
