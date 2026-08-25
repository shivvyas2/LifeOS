import Testing
@testable import Persistence

@Suite struct LifeSectorTests {

    @Test func thereAreNineSectors() {
        #expect(LifeSector.allCases.count == 9)
    }

    /// The board reads in the order Shiv already scores in, which is not
    /// declaration order and not alphabetical.
    @Test func boardOrderCoversEverySectorExactlyOnce() {
        #expect(LifeSector.boardOrder.count == LifeSector.allCases.count)
        #expect(Set(LifeSector.boardOrder) == Set(LifeSector.allCases))
    }

    @Test func boardOrderStartsWithFamily() {
        #expect(LifeSector.boardOrder.first == .family)
    }

    /// Raw values are persisted, so renaming a case silently orphans stored rows.
    @Test func rawValuesAreStable() {
        #expect(LifeSector.body.rawValue == "body")
        #expect(LifeSector.romance.rawValue == "romance")
        #expect(LifeSector(rawValue: "mission") == .mission)
    }

    @Test func everySectorHasATitle() {
        #expect(LifeSector.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
