import Testing
import Foundation
@testable import Integrations

@Suite struct PlaidItemStoreTests {
    private func makeStore() -> UserDefaultsPlaidItemStore {
        // A named suite per test run keeps this out of the app's real defaults.
        let defaults = UserDefaults(suiteName: "plaid.tests.\(UUID().uuidString)")!
        return UserDefaultsPlaidItemStore(defaults: defaults)
    }

    @Test func cursorsAreScopedToTheirItem() {
        // Plaid scopes a sync cursor to one Item. A single shared cursor works
        // until a second bank is connected, then corrupts both.
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: nil))
        store.upsert(PlaidStoredItem(itemID: "item_b", institutionName: "Amex", cursor: nil))

        store.setCursor("cursor_a", for: "item_a")

        let items = store.items()
        #expect(items.count == 2)
        #expect(items.first { $0.itemID == "item_a" }?.cursor == "cursor_a")
        #expect(items.first { $0.itemID == "item_b" }?.cursor == nil)
    }

    @Test func upsertingAnItemKeepsTheCursorItAlreadyHad() {
        // A sync response re-states the institution name. Letting that reset the
        // cursor would replay full history on every sync.
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: nil))
        store.setCursor("cursor_a", for: "item_a")

        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase Bank", cursor: nil))

        #expect(store.items().first?.cursor == "cursor_a")
        #expect(store.items().first?.institutionName == "Chase Bank")
    }

    @Test func removingOneItemLeavesTheOther() {
        let store = makeStore()
        store.upsert(PlaidStoredItem(itemID: "item_a", institutionName: "Chase", cursor: "c"))
        store.upsert(PlaidStoredItem(itemID: "item_b", institutionName: "Amex", cursor: "d"))

        store.remove(itemID: "item_a")

        #expect(store.items().map(\.itemID) == ["item_b"])
    }

    @Test func settingACursorForAnUnknownItemDoesNotInventOne() {
        // The item list comes from the server. A cursor with no Item behind it
        // would be a phantom connection on the Money screen.
        let store = makeStore()
        store.setCursor("orphan", for: "item_missing")
        #expect(store.items().isEmpty)
    }
}
