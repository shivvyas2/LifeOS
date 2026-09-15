import Testing
@testable import Sectors

struct CatalogRefreshTests {
    @Test func anEmptyAnswerNeverReplacesAFullCache() {
        #expect(CatalogRefresh.shouldReplace(cacheCount: 122, incoming: 0) == false)
    }
    @Test func rowsAlwaysReplaceTheCache() {
        #expect(CatalogRefresh.shouldReplace(cacheCount: 122, incoming: 130) == true)
        #expect(CatalogRefresh.shouldReplace(cacheCount: 0, incoming: 1) == true)
    }
    @Test func aGenuinelyEmptyServerClearsNothingBecauseThereIsNothingToClear() {
        // The empty-cache case still returns true: nothing is lost, and the
        // first refresh on a fresh install must be allowed to write zero rows
        // rather than be treated as a failure.
        #expect(CatalogRefresh.shouldReplace(cacheCount: 0, incoming: 0) == true)
    }
}
