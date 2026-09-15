import Foundation

/// Whether a catalog response may replace the cache.
///
/// A successful fetch that comes back empty is almost never the truth: an
/// unseeded table, a policy that stopped matching, or a range quirk all look
/// like `[]` at the client. Replacing a full cache with that leaves a person
/// who had the whole library a second ago with nothing, offline or not. So an
/// empty answer is only believed when there was nothing to lose.
public enum CatalogRefresh {
    public static func shouldReplace(cacheCount: Int, incoming: Int) -> Bool {
        !(incoming == 0 && cacheCount > 0)
    }
}
