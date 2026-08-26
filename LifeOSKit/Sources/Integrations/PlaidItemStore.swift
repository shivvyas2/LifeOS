import Foundation

/// One connected bank, and where its last sync left off.
public struct PlaidStoredItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let institutionName: String
    /// Plaid's `/transactions/sync` cursor, scoped to this Item. Nil means
    /// "start from the beginning", which is also what a fresh install wants.
    public var cursor: String?

    public init(itemID: String, institutionName: String, cursor: String?) {
        self.itemID = itemID
        self.institutionName = institutionName
        self.cursor = cursor
    }
}

public protocol PlaidItemStoring: Sendable {
    func items() -> [PlaidStoredItem]
    /// Adds the Item, or updates its institution name while keeping its cursor.
    func upsert(_ item: PlaidStoredItem)
    func setCursor(_ cursor: String, for itemID: String)
    func remove(itemID: String)
    func clear()
}

/// Held in `UserDefaults`, deliberately not the Keychain.
///
/// The Keychain survives a reinstall; the SwiftData database does not. A cursor
/// that outlived its database would mean Plaid replays nothing into an empty
/// app and the history is silently gone forever. This state must die with the
/// data it describes, so it lives in the app container.
public struct UserDefaultsPlaidItemStore: PlaidItemStoring {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key = "plaid.items"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func items() -> [PlaidStoredItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlaidStoredItem].self, from: data)
        else { return [] }
        return decoded
    }

    public func upsert(_ item: PlaidStoredItem) {
        var current = items()
        if let index = current.firstIndex(where: { $0.itemID == item.itemID }) {
            // The cursor is ours, not the caller's. A sync response re-states the
            // institution name, and letting that reset the cursor would replay
            // full history on every sync.
            let keptCursor = current[index].cursor
            current[index] = PlaidStoredItem(itemID: item.itemID,
                                             institutionName: item.institutionName,
                                             cursor: item.cursor ?? keptCursor)
        } else {
            current.append(item)
        }
        write(current)
    }

    public func setCursor(_ cursor: String, for itemID: String) {
        var current = items()
        guard let index = current.firstIndex(where: { $0.itemID == itemID }) else { return }
        current[index].cursor = cursor
        write(current)
    }

    public func remove(itemID: String) {
        write(items().filter { $0.itemID != itemID })
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func write(_ items: [PlaidStoredItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
