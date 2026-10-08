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
    private let defaults: UserDefaults
    private var context: ModelContext?
    private var active = true
    private var lastAttemptAt: Date?

    func deactivate() {
        active = false
        context = nil
        PlaidLinkPresenter.resetForAccountChange()
    }

    init(items: any PlaidItemStoring = UserDefaultsPlaidItemStore(),
         sessions: any AuthSessionStoring = KeychainAuthSessionStore(),
         defaults: UserDefaults = .currentAccount) {
        self.items = items
        self.sessions = sessions
        self.defaults = defaults
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

    /// What the Link session in flight was opened for, so a refusal can be
    /// worded for a card rather than a bank.
    private(set) var connectingKind: PlaidLinkKind = .bank

    func connect(_ kind: PlaidLinkKind = .bank) {
        guard active, let api else { state = .unconfigured; return }
        state = .connecting
        connectingKind = kind

        Task {
            do {
                let linkToken = try await api.createLinkToken(for: kind)
                guard active, sessions.load() != nil else { return }
                PlaidLinkPresenter.present(linkToken: linkToken) { result in
                    Task { await self.finishConnect(result) }
                }
            } catch {
                plaidLog.error("link token failed: \(String(describing: error))")
                state = .failed(kind == .creditCard ? "Could not start the card connection"
                                                    : "Could not start the bank connection")
            }
        }
    }

    private func finishConnect(_ result: PlaidLinkResult) async {
        guard active, let api else { return }
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
                guard active, sessions.load() != nil else { return }
                items.upsert(PlaidStoredItem(itemID: item.item_id,
                                             institutionName: item.institution_name,
                                             cursor: nil))
                isFetchingHistory = true
                refreshState()
                await sync()
            } catch PlaidClientError.institutionAlreadyConnected {
                // One login per bank: a second one would bring the same
                // transactions in twice. A card at a bank already connected
                // is reached through that bank's login instead.
                state = .failed(connectingKind == .creditCard
                    ? "\(institutionName ?? "That bank") is already connected. Its cards come in with it; to add one you left out, disconnect the bank and connect it again with the card ticked."
                    : "That bank is already connected")
            } catch {
                plaidLog.error("exchange failed: \(String(describing: error))")
                state = .failed("Could not finish connecting")
            }
        }
    }

    // MARK: - Sync

    /// Rows synced before the logo field existed never get one, because
    /// `/transactions/sync` only re-sends what changed. Clearing every cursor
    /// once makes the next sync replay history through the same upsert, and
    /// the flag stops it happening again: a replay on every launch would pull
    /// years of rows daily.
    static let logoReplayKey = "plaid.logoReplayDone.v1"

    func replayHistoryOnce(defaults: UserDefaults = .currentAccount) {
        guard !defaults.bool(forKey: Self.logoReplayKey) else { return }
        items.resetCursors()
        defaults.set(true, forKey: Self.logoReplayKey)
    }

    /// `staleAfter` is an hour for ordinary reloads, and much less when
    /// someone opens the Money tab to see what they just spent.
    func syncIfDue(staleAfter: TimeInterval = 3_600) async {
        replayHistoryOnce(defaults: defaults)
        guard active, sessions.load() != nil,
              SyncStalenessPolicy.shouldSync(lastSync: lastAttemptAt, staleAfter: staleAfter) else { return }
        // The server owns the link. Ask it even when this device has no cache.
        if case .connecting = state { return }
        if case .unconfigured = state { return }
        lastAttemptAt = .now
        await sync()
    }

    func sync() async {
        guard active, let api, let context, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let runner = PlaidSync(api: api, money: MoneyStore(context: context), items: items)
        do {
            var outcome = try await runner.run()
            // Plaid hands back a bounded number of pages per call, so an initial
            // pull of years of history finishes across several runs rather than
            // stopping part-way and looking complete.
            var guardRail = 0
            while active, outcome.hasMore, guardRail < 20 {
                outcome = try await runner.run()
                guardRail += 1
            }

            guard active else { return }
            if outcome.failedItems.isEmpty && !outcome.hasMore { lastSyncedAt = .now }
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
            // A network outage does not disconnect a saved bank.
            refreshState()
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
            return
        }
        guard active else { return }
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
