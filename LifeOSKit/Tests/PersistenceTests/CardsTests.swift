import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CardsTests {
    private func makeStore() throws -> (MoneyStore, ModelContext) {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        return (MoneyStore(context: context), context)
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    // MARK: Resolution

    @Test func aRowsOwnChoiceBeatsTheRuleAndThePlaidAccount() {
        let resolver = CardResolver(rules: ["amazon": "discover"])
        #expect(resolver.cardKey(override: "zolve", merchant: "Amazon", accountID: "plaid-1") == "zolve")
    }

    @Test func aMerchantRuleBeatsThePlaidAccount() {
        let resolver = CardResolver(rules: ["amazon": "discover"])
        #expect(resolver.cardKey(override: nil, merchant: "  AMAZON ", accountID: "plaid-1") == "discover")
    }

    @Test func withNothingSaidThePlaidAccountStands() {
        let resolver = CardResolver(rules: ["amazon": "discover"])
        #expect(resolver.cardKey(override: nil, merchant: "Netflix", accountID: "plaid-1") == "plaid-1")
        #expect(resolver.cardKey(override: nil, merchant: "Netflix", accountID: nil) == nil)
    }

    // MARK: Catalog

    @Test func plaidAccountNamesFindTheirCard() {
        #expect(CardCatalog.guess(accountName: "CHASE SAPPHIRE PREFERRED")?.id == "chase-sapphire-preferred")
        #expect(CardCatalog.guess(accountName: "Sapphire Reserve")?.id == "chase-sapphire-reserve")
        #expect(CardCatalog.guess(accountName: "Discover it Card")?.id == "discover-it")
        #expect(CardCatalog.guess(accountName: "Apple Card")?.id == "apple-card")
        #expect(CardCatalog.guess(accountName: "Banana Republic Visa")?.id == "banana-republic")
        #expect(CardCatalog.guess(accountName: "TOTAL CHECKING")?.id == "chase-debit")
    }

    @Test func anAccountTheCatalogDoesNotKnowGuessesNothing() {
        #expect(CardCatalog.guess(accountName: "Everyday Savings") == nil)
    }

    @Test func aChosenCardBeatsTheGuessAndAHandAddedCardIsNeverGuessed() {
        let plaid = MoneyAccount(name: "Sapphire Preferred", type: "credit", currentBalance: 0,
                                 externalID: "a", cardProductID: "discover-it")
        #expect(plaid.cardProduct?.id == "discover-it")

        let manual = MoneyAccount(name: "My Discover", type: "credit", currentBalance: 0, isManual: true)
        #expect(manual.cardProduct == nil)
        #expect(manual.faceStyle == .unknown)
        manual.faceColorHex = "#F3EFE7"
        #expect(manual.faceStyle.darkInk)
    }

    @Test func cardColourLightnessPicksTheInk() {
        #expect(CardColor.isLight("#F3EFE7"))
        #expect(!CardColor.isLight("#0B2A5B"))
        #expect(CardColor.components("nonsense") == nil)
    }

    // MARK: Fade

    @Test func aDarkFaceFadesFromNearBlackDownToItsAccent() {
        let sapphire = CardFaceStyle(base: "#0A2A6B", accent: "#3D8BFF", pattern: .gradient)
        let fade = sapphire.fade
        #expect(fade.count == 3)
        #expect(CardColor.luminance(fade[0]) < CardColor.luminance("#0A2A6B"))
        #expect(fade[1] == "#0A2A6B")
        #expect(fade[2] == "#3D8BFF")
    }

    @Test func aLightFaceFadesLighterToDarker() {
        let discover = CardFaceStyle(base: "#B8862B", accent: "#F6DC8C", pattern: .gradient, darkInk: true)
        #expect(discover.fade == ["#F6DC8C", "#B8862B"])
    }

    @Test func aLightFaceSoftensADarkEndSoDarkInkStaysReadable() {
        let banana = CardFaceStyle(base: "#EFE8DC", accent: "#2A2622", pattern: .plain, darkInk: true)
        let fade = banana.fade
        #expect(fade.first == "#EFE8DC")
        #expect(fade.last != "#2A2622")
        #expect(CardColor.luminance(fade.last!) >= 0.35)
    }

    @Test func aPlainColourStillFades() {
        let cream = CardFaceStyle.plain("#F3EFE7").fade
        #expect(cream.first == "#F3EFE7")
        #expect(CardColor.luminance(cream.last!) < CardColor.luminance("#F3EFE7"))

        let navy = CardFaceStyle.plain("#0B2A5B").fade
        #expect(CardColor.luminance(navy.first!) < CardColor.luminance("#0B2A5B"))
        #expect(navy.last == "#0B2A5B")
    }

    @Test func mixingMovesAColourTowardAnother() {
        #expect(CardColor.mix("#000000", toward: "#FFFFFF", by: 0.5) == "#808080")
        #expect(CardColor.mix("#FF0000", toward: "#000000", by: 0) == "#FF0000")
        #expect(CardColor.mix("nonsense", toward: "#000000", by: 0.5) == "nonsense")
    }

    // MARK: Store

    @Test func aHandAddedCardKeepsOnlyTheLastFourDigits() throws {
        let (store, _) = try makeStore()
        let card = try store.addManualCard(name: "Zolve", productID: "zolve", mask: "xxxx-xxxx-48 21", colorHex: nil)
        #expect(card.mask == "4821")
        #expect(card.isManual)
        #expect(card.cardKey.hasPrefix("manual:"))
        #expect(card.netWorthContribution == 0)
    }

    @Test func aPlaidCardKeepsItsBankNameWhenRestyled() throws {
        let (store, _) = try makeStore()
        try store.upsertAccounts([MoneyAccountRow(externalID: "p1", name: "Sapphire", type: "credit",
                                                  subtype: "credit card", mask: "1111", currentBalance: 10,
                                                  availableBalance: nil, creditLimit: nil, currencyCode: "USD")])
        let card = try #require(try store.accounts().first)
        try store.updateCard(card, name: "Renamed", productID: "chase-sapphire-reserve", mask: "9999", colorHex: nil)
        #expect(card.name == "Sapphire")
        #expect(card.mask == "1111")
        #expect(card.cardProductID == "chase-sapphire-reserve")
    }

    @Test func aCorrectionSurvivesTheNextSync() throws {
        let (store, _) = try makeStore()
        let row = MoneyIngestRow(externalID: "t1", date: day, amount: -20, merchant: "Shop",
                                 category: nil, categoryCode: nil, merchantID: nil, logoURL: nil,
                                 pending: false, accountID: "plaid-1", accountName: "Checking",
                                 currencyCode: "USD")
        try store.ingest([row])
        let entry = try #require(try store.monthEntries(containing: day).first)
        try store.setCard("manual:zolve", for: entry)

        try store.ingest([row])
        let again = try #require(try store.monthEntries(containing: day).first)
        #expect(again.cardOverrideKey == "manual:zolve")
        #expect(again.accountID == "plaid-1")
    }

    @Test func oneRulePerMerchant() throws {
        let (store, _) = try makeStore()
        try store.setCardRule(merchant: "Amazon", cardKey: "a")
        try store.setCardRule(merchant: "AMAZON", cardKey: "b")
        let rules = try store.cardRules()
        #expect(rules.count == 1)
        #expect(rules.first?.cardKey == "b")

        try store.removeCardRule(merchant: "amazon ")
        #expect(try store.cardRules().isEmpty)
    }

    @Test func deletingAHandAddedCardReleasesItsRowsAndRules() throws {
        let (store, _) = try makeStore()
        let card = try store.addManualCard(name: "Zolve", productID: nil, mask: nil, colorHex: "#14161B")
        let entry = try store.add(date: day, amount: -5, merchant: "Coffee", cardKey: card.cardKey)
        try store.setCardRule(merchant: "Coffee", cardKey: card.cardKey)

        try store.deleteManualCard(card)
        #expect(entry.cardOverrideKey == nil)
        #expect(try store.cardRules().isEmpty)
        #expect(try store.accounts().isEmpty)
    }

    @Test func importingTheSameStatementTwiceDoesNotDoubleIt() throws {
        let (store, _) = try makeStore()
        let lines = [
            StatementLine(date: day, amount: -12.30, merchant: "Cafe"),
            StatementLine(date: day, amount: -40, merchant: "Fuel"),
        ]
        try store.importStatement(lines, cardKey: "manual:z")
        try store.importStatement(lines.map { StatementLine(date: $0.date, amount: $0.amount, merchant: $0.merchant) },
                                  cardKey: "manual:z")
        let entries = try store.monthEntries(containing: day)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.cardOverrideKey == "manual:z" && $0.source == .manual })
    }

    // MARK: Duplicates

    @Test func aQuickAddedPurchaseIsFlaggedOnTheStatement() {
        let quick = MoneyEntry(date: day, amount: -5.75, merchant: "Blue Bottle")
        let posted = StatementLine(date: day.addingTimeInterval(2 * 86_400), amount: -5.75, merchant: "BLUE BOTTLE COFFEE #12")
        let other = StatementLine(date: day, amount: -5.70, merchant: "Blue Bottle")
        let flagged = StatementDedupe.duplicates([posted, other], existing: [quick])
        #expect(flagged == [posted.id])
    }

    @Test func oneExistingRowExplainsOnlyOneLine() {
        let quick = MoneyEntry(date: day, amount: -5, merchant: "Coffee")
        let first = StatementLine(date: day, amount: -5, merchant: "Coffee")
        let second = StatementLine(date: day, amount: -5, merchant: "Coffee")
        #expect(StatementDedupe.duplicates([first, second], existing: [quick]).count == 1)
    }

    @Test func tooFarApartIsNotADuplicate() {
        let quick = MoneyEntry(date: day, amount: -5, merchant: "Coffee")
        let late = StatementLine(date: day.addingTimeInterval(5 * 86_400), amount: -5, merchant: "Coffee")
        #expect(StatementDedupe.duplicates([late], existing: [quick]).isEmpty)
    }

    // MARK: Migration

    @Test func newCardFieldsHaveDefaults() throws {
        let checks: [(String, [String])] = [
            ("MoneyAccount", ["cardProductID", "faceColorHex", "isManual"]),
            ("MoneyEntry", ["cardOverrideKey"]),
        ]
        for (entityName, fields) in checks {
            let entity = try #require(LifeOSContainer.schema.entities.first { $0.name == entityName })
            for name in fields {
                let attribute = try #require(entity.attributesByName[name], "missing \(name)")
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(name) has no default")
            }
        }
    }
}
