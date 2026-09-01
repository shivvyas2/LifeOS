import Testing
import Foundation
@testable import Integrations

@Suite @MainActor struct PlaidWireFormatTests {
    private func delta() throws -> PlaidItemDelta {
        let response = try JSONDecoder().decode(
            PlaidSyncResponse.self, from: Data(PlaidFixtures.syncPage.utf8)
        )
        return try #require(response.items.first)
    }

    @Test func aMerchantEntityIsDecodedWhenPlaidResolvedOne() throws {
        let coffee = try #require(delta().added.first { $0.transaction_id == "txn_coffee" })
        #expect(coffee.merchant_entity_id == "mch_bluebottle")
    }

    @Test func anUnresolvedDescriptorHasNoMerchantEntity() throws {
        // Plaid does not resolve every descriptor. Nil means "not known", and
        // grouping every nil together would invent one fictitious merchant out
        // of every unresolved row.
        let payroll = try #require(delta().added.first { $0.transaction_id == "txn_payroll" })
        #expect(payroll.merchant_entity_id == nil)
    }

    @Test func anAccountCarriesItsMaskAndSubtype() throws {
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })
        #expect(card.mask == "4127")
        #expect(card.subtype == "credit card")
        // type stays coarse and unchanged: netWorthContribution reads it.
        #expect(card.type == "credit")
    }

    @Test func aCreditLimitIsDecodedAndACheckingAccountHasNone() throws {
        // The distinction this whole slice exists for. A checking account with
        // a limit of 0 would render as fully utilised, which is arithmetically
        // true and factually meaningless.
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })
        let checking = try #require(delta().accounts.first { $0.account_id == "acc_checking" })

        #expect(card.balances.limit == 2_000)
        #expect(checking.balances.limit == nil)
    }

    @Test func anAvailableBalanceIsDecodedAndItsAbsenceIsNotZero() throws {
        let checking = try #require(delta().accounts.first { $0.account_id == "acc_checking" })
        let card = try #require(delta().accounts.first { $0.account_id == "acc_card" })

        #expect(checking.balances.available == 2_100.50)
        #expect(card.balances.available == nil)
    }
}
