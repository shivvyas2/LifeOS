import Testing
import Foundation
import Persistence
@testable import Integrations

@MainActor
private final class StubMoney: MoneyIngesting {
    var ingested: [MoneyIngestRow] = []
    var removed: [String] = []
    var accounts: [MoneyAccountRow] = []
    var failIngest = false

    struct Boom: Error {}

    func ingest(_ incoming: [MoneyIngestRow]) throws {
        if failIngest { throw Boom() }
        ingested.append(contentsOf: incoming)
    }
    func remove(externalIDs: [String]) throws { removed.append(contentsOf: externalIDs) }
    func upsertAccounts(_ incoming: [MoneyAccountRow]) throws { accounts.append(contentsOf: incoming) }
}

private struct StubAPI: PlaidAPI {
    let response: PlaidSyncResponse
    func createLinkToken() async throws -> String { "link" }
    func exchange(publicToken: String, institutionID: String?,
                  institutionName: String?) async throws -> PlaidExchangeResult {
        PlaidExchangeResult(item_id: "item_sandbox_1", institution_name: "First Platypus Bank")
    }
    func sync(cursors: [String: String]) async throws -> PlaidSyncResponse { response }
    func disconnect(itemID: String) async throws {}
}

@Suite @MainActor struct PlaidSyncTests {
    private func fixtureResponse() throws -> PlaidSyncResponse {
        try JSONDecoder().decode(PlaidSyncResponse.self, from: Data(PlaidFixtures.syncPage.utf8))
    }

    private func makeItems() -> UserDefaultsPlaidItemStore {
        UserDefaultsPlaidItemStore(
            defaults: UserDefaults(suiteName: "plaid.sync.\(UUID().uuidString)")!
        )
    }

    @Test func aSuccessfulRunStoresTheDataAndThenTheCursor() async throws {
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(api: StubAPI(response: try fixtureResponse()),
                             money: money, items: items)

        let outcome = try await sync.run()

        #expect(outcome.itemsSynced == 1)
        #expect(outcome.transactionsIngested == 4)
        #expect(money.removed == ["txn_stale_pending"])
        #expect(money.accounts.count == 2)
        #expect(items.items().first?.cursor == "cursor_page_2")
        #expect(items.items().first?.institutionName == "First Platypus Bank")
    }

    @Test func aConnectionRemovedOnTheServerLeavesTheLocalCache() async throws {
        let items = makeItems()
        items.upsert(PlaidStoredItem(itemID: "removed", institutionName: "Old bank", cursor: "old"))
        let money = StubMoney()
        let response = try JSONDecoder().decode(PlaidSyncResponse.self, from: Data(#"{"items":[]}"#.utf8))
        _ = try await PlaidSync(api: StubAPI(response: response), money: money, items: items).run()
        #expect(items.items().isEmpty)
        #expect(money.removed.isEmpty, "disconnecting does not delete transaction history")
    }

    @Test func aFailedIngestLeavesTheCursorWhereItWas() async throws {
        // The reason the cursor lives on the device at all. Advance it here and
        // Plaid never resends this page: those transactions are gone for good.
        let money = StubMoney()
        money.failIngest = true
        let items = makeItems()
        let sync = PlaidSync(api: StubAPI(response: try fixtureResponse()),
                             money: money, items: items)

        _ = try? await sync.run()

        // Both halves matter. The cursor staying nil is the invariant, but an empty
        // store would satisfy that too through optional chaining, so the count is
        // what makes this test able to fail for the right reason.
        #expect(items.items().count == 1)
        #expect(items.items().first?.cursor == nil)
    }

    @Test func anExpiredLoginIsReportedWithoutTouchingTheData() async throws {
        let failing = #"""
        {"items":[{"item_id":"item_1","institution_name":"Chase","added":[],
        "modified":[],"removed":[],"accounts":[],"next_cursor":null,
        "has_more":false,"error":"item_login_required"}]}
        """#
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(
            api: StubAPI(response: try JSONDecoder().decode(
                PlaidSyncResponse.self, from: Data(failing.utf8))),
            money: money, items: items
        )

        let outcome = try await sync.run()

        #expect(outcome.needsReconnect == ["Chase"])
        #expect(outcome.itemsSynced == 0)
        #expect(money.ingested.isEmpty)
        #expect(items.items().count == 1)
        #expect(items.items().first?.cursor == nil)
    }

    @Test func aBalanceLoginFailureRaisesReconnectWithoutLosingTheTransactions() async throws {
        // /transactions/sync serves cached data and can succeed with an expired
        // bank login; /accounts/balance/get does a live fetch and is the call
        // that actually throws ITEM_LOGIN_REQUIRED. The transactions already
        // fetched must still land, and the banner must still show.
        let payload = #"""
        {"items":[{"item_id":"item_1","institution_name":"Chase","added":[
          {"transaction_id":"txn_1","account_id":"acc_1","amount":-10.00,
           "iso_currency_code":"USD","date":"2026-08-14","name":"Coffee Shop",
           "merchant_name":null,"pending":false,"personal_finance_category":null}
        ],"modified":[],"removed":[],"accounts":[],"next_cursor":"cursor_1",
        "has_more":false,"error":null,"balance_error":"item_login_required"}]}
        """#
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(
            api: StubAPI(response: try JSONDecoder().decode(
                PlaidSyncResponse.self, from: Data(payload.utf8))),
            money: money, items: items
        )

        let outcome = try await sync.run()

        #expect(outcome.needsReconnect == ["Chase"])
        #expect(outcome.itemsSynced == 1)
        #expect(money.ingested.count == 1)
        #expect(items.items().first?.cursor == "cursor_1")
    }

    @Test func aNonLoginItemFailureIsReportedInFailedItemsNotReconnect() async throws {
        // A transient failure on one bank must not vanish into a sync that
        // otherwise reports clean, and reconnecting would not fix it, so it
        // must not raise the reconnect banner either.
        let failing = #"""
        {"items":[{"item_id":"item_1","institution_name":"Ally","added":[],
        "modified":[],"removed":[],"accounts":[],"next_cursor":null,
        "has_more":false,"error":"rate_limited"}]}
        """#
        let money = StubMoney()
        let items = makeItems()
        let sync = PlaidSync(
            api: StubAPI(response: try JSONDecoder().decode(
                PlaidSyncResponse.self, from: Data(failing.utf8))),
            money: money, items: items
        )

        let outcome = try await sync.run()

        #expect(outcome.failedItems == ["Ally"])
        #expect(outcome.needsReconnect.isEmpty)
        #expect(outcome.itemsSynced == 0)
    }
}
