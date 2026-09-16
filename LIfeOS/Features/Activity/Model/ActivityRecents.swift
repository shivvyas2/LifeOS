import Foundation
import AppSurfaces

/// The last activities this account started, most recent first, so the
/// picker leads with what the person actually does. Stored as names so a
/// renamed or removed catalog entry simply drops out of the list.
struct ActivityRecents {
    static let key = "activity.recents"
    static let limit = 6
    private let defaults: UserDefaults
    private(set) var names: [String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.key) ?? []
    }
    /// Catalog entries for the stored names, skipping any that no longer exist.
    func types() -> [ActivityType] { names.compactMap { ActivityCatalog.type(named: $0) } }

    mutating func record(_ type: ActivityType) {
        names.removeAll { $0 == type.name }
        names.insert(type.name, at: 0)
        if names.count > Self.limit { names.removeLast(names.count - Self.limit) }
        defaults.set(names, forKey: Self.key)
    }
}
