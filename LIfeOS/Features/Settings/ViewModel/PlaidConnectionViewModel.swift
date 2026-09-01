import Foundation
import SwiftData
import OSLog
import Integrations
import Persistence

private let plaidLog = Logger(subsystem: "com.shivvyas.lifeos", category: "plaid")

/// Owns the bank connection: the Link round trip, and the sync that follows it.
@MainActor @Observable
final class PlaidConnectionViewModel {
    enum State: Equatable {
        case unconfigured
        case disconnected
        case connecting
        case connected([String])
        /// The bank invalidated the stored login. Only the user can fix it.
        case needsReconnect(String)
        case failed(String)
    }

    private(set) var state: State = .disconnected
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    /// True between connecting and the first transaction arriving. Plaid
    /// fetches history asynchronously, so an empty first sync is normal and
    /// must not be rendered as "you spent nothing this month".
    private(set) var isFetchingHistory = false

    private let items: any PlaidItemStoring
    private let sessions: any AuthSessionStoring
    private var context: ModelContext?

    init(items: any PlaidItemStoring = UserDefaultsPlaidItemStore(),
         sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.items = items
        self.sessions = sessions
    }

    func attach(_ context: ModelContext) {
        self.context = context
        // A bank's OAuth login can outlive the process. When it does, the Link
        // session resumed on relaunch has no completion closure left to call,
        // because the one `connect` handed over died with the old process.
        // This is where the replacement comes from.
        PlaidLinkPresenter.onResumedConnect = { [weak self] result in
            Task { await self?.finishConnect(result) }
        }
        refreshState()
    }

    func refreshState() {
        guard AppConfig.isPlaidConfigured else { state = .unconfigured; return }
        let connected = items.items().map(\.institutionName)
        state = connected.isEmpty ? .disconnected : .connected(connected)
    }

    /// A bank needing re-authentication is not connected for this purpose:
    /// the summary dot answers "is this working", and a stale login is not.
    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var statusDetail: String {
        switch state {
        case .unconfigured: "Not configured"
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let names): names.joined(separator: ", ")
        case .needsReconnect(let name): "\(name) needs you to sign in again"
        case .failed(let message): message
        }
    }

    private var api: PlaidClient? {
        guard let base = AppConfig.plaidFunctionsBase else { return nil }
        let sessions = self.sessions
        return PlaidClient(functionsBase: base, accessToken: { sessions.load()?.accessToken })
    }

    // MARK: - Connect

    func connect() {
        guard let api else { state = .unconfigured; return }
        state = .connecting

        Task {
            do {
                let linkToken = try await api.createLinkToken()
                PlaidLinkPresenter.present(linkToken: linkToken) { result in
                    Task { await self.finishConnect(result) }
                }
            } catch {
                plaidLog.error("link token failed: \(String(describing: error))")
                state = .failed("Could not start the bank connection")
            }
        }
    }

    private func finishConnect(_ result: PlaidLinkResult) async {
        guard let api else { return }
        switch result {
        case .cancelled:
            refreshState()
        case .failed(let message):
            plaidLog.error("link exited: \(message)")
            state = .failed(message)
        case .connected(let publicToken, let institutionID, let institutionName):
            do {
                let item = try await api.exchange(publicToken: publicToken,
                                                  institutionID: institutionID,
                                                  institutionName: institutionName)
                items.upsert(PlaidStoredItem(itemID: item.item_id,
                                             institutionName: item.institution_name,
                                             cursor: nil))
                isFetchingHistory = true
                refreshState()
                await sync()
            } catch PlaidClientError.institutionAlreadyConnected {
                state = .failed("That bank is already connected")
            } catch {
                plaidLog.error("exchange failed: \(String(describing: error))")
                state = .failed("Could not finish connecting")
            }
        }
    }

    // MARK: - Sync

    func syncIfDue() async {
        guard case .connected = state,
              SyncStalenessPolicy.shouldSync(lastSync: lastSyncedAt) else { return }
        await sync()
    }

    func sync() async {
        guard let api, let context, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let runner = PlaidSync(api: api, money: MoneyStore(context: context), items: items)
        do {
            var outcome = try await runner.run()
            // Plaid hands back a bounded number of pages per call, so an initial
            // pull of years of history finishes across several runs rather than
            // stopping part-way and looking complete.
            var guardRail = 0
            while outcome.hasMore, guardRail < 20 {
                outcome = try await runner.run()
                guardRail += 1
            }

            lastSyncedAt = .now
            if outcome.transactionsIngested > 0 { isFetchingHistory = false }
            if let reconnect = outcome.needsReconnect.first {
                state = .needsReconnect(reconnect)
            } else {
                refreshState()
            }
        } catch {
            // The previous snapshot stays on screen with its own timestamp,
            // which is honest, rather than being replaced by zeroes.
            plaidLog.error("sync failed: \(String(describing: error))")
            state = .failed("Sync failed")
        }
    }

    // MARK: - Disconnect

    /// History is kept unless the user asks otherwise. Revoking a credential
    /// and stopping the billing is not a request to erase the past.
    func disconnect(itemID: String, deletingHistory: Bool) async {
        guard let api else { return }
        do {
            try await api.disconnect(itemID: itemID)
        } catch {
            plaidLog.error("disconnect failed: \(String(describing: error))")
        }
        items.remove(itemID: itemID)

        if deletingHistory, let context {
            let store = MoneyStore(context: context)
            let plaidIDs = (try? store.entries(from: .distantPast, to: .now))?
                .filter { $0.source == .plaid }
                .compactMap(\.externalID) ?? []
            try? store.remove(externalIDs: plaidIDs)
        }
        refreshState()
    }
}
