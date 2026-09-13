import Foundation
import Persistence

public struct PlaidSyncOutcome: Sendable, Equatable {
    public var itemsSynced = 0
    public var transactionsIngested = 0
    /// Institution names whose stored login the bank has invalidated. These
    /// need the user to sign in again; nothing about them is retryable.
    public var needsReconnect: [String] = []
    /// Institution names whose sync failed for a reason other than an expired
    /// login (those go to `needsReconnect` instead). Kept so a caller does not
    /// stamp a clean "last synced" timestamp on a sync that partly failed.
    public var failedItems: [String] = []
    /// Plaid has more pages waiting. The caller should run again straight away.
    public var hasMore = false
}

/// Pulls each connected bank forward and writes the result down.
///
/// The ordering below is the whole design in three lines: store the data, then
/// move the cursor. A cursor advanced before a successful ingest is a page of
/// transactions Plaid will never send again.
@MainActor
public struct PlaidSync {
    private let api: any PlaidAPI
    private let money: any MoneyIngesting
    private let items: any PlaidItemStoring

    public init(api: any PlaidAPI, money: any MoneyIngesting, items: any PlaidItemStoring) {
        self.api = api
        self.money = money
        self.items = items
    }

    @discardableResult
    public func run() async throws -> PlaidSyncOutcome {
        let cursors = items.items().reduce(into: [String: String]()) { result, item in
            result[item.itemID] = item.cursor
        }
        let response = try await api.sync(cursors: cursors)

        // The endpoint returns every account-owned item, including failed ones.
        // A link removed on another device must disappear from this cache too.
        let remoteIDs = Set(response.items.map(\.item_id))
        for item in items.items() where !remoteIDs.contains(item.itemID) {
            items.remove(itemID: item.itemID)
        }

        var outcome = PlaidSyncOutcome()
        for delta in response.items {
            // Remember the connection before anything else, so a bank that is
            // connected but still fetching its history is not mistaken for one
            // that was never connected.
            items.upsert(PlaidStoredItem(itemID: delta.item_id,
                                         institutionName: delta.institution_name,
                                         cursor: nil))

            if delta.error == "item_login_required" {
                outcome.needsReconnect.append(delta.institution_name)
                continue
            }
            if delta.error != nil {
                // Not item_login_required: reconnecting would not fix this, and
                // it must not vanish into a sync that otherwise looks clean.
                outcome.failedItems.append(delta.institution_name)
                continue
            }

            // Plaid's /transactions/sync puts a given transaction_id in exactly
            // one of added, modified and removed within a delta, so merging
            // added and modified here is safe. remove runs after ingest below,
            // so a removal wins if that assumption is ever wrong.
            let rows = try PlaidMapping.ingestRows(from: delta.added + delta.modified,
                                                   accounts: delta.accounts)
            try money.ingest(rows)
            try money.remove(externalIDs: delta.removed.map(\.transaction_id))
            try money.upsertAccounts(PlaidMapping.accountRows(from: delta.accounts))

            // Only now. Every throw above leaves the cursor where it was, and
            // the next run replays this page into an idempotent upsert.
            if let cursor = delta.next_cursor {
                items.setCursor(cursor, for: delta.item_id)
            }

            // The balance fetch can fail on its own even though the
            // transactions above ingested cleanly, and an expired login shows
            // up here rather than on `delta.error`. Transactions still ingest
            // and the cursor still advances; only the banner is added.
            if delta.balance_error == "item_login_required" {
                outcome.needsReconnect.append(delta.institution_name)
            }

            outcome.itemsSynced += 1
            outcome.transactionsIngested += rows.count
            outcome.hasMore = outcome.hasMore || delta.has_more
        }
        return outcome
    }
}
