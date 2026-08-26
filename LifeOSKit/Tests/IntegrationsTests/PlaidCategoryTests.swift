import Testing
@testable import Integrations

@Suite struct PlaidCategoryTests {
    @Test func knownPrimariesBecomeReadableLabels() {
        #expect(PlaidCategory.display(primary: "FOOD_AND_DRINK") == "Food & drink")
        #expect(PlaidCategory.display(primary: "RENT_AND_UTILITIES") == "Rent & utilities")
        #expect(PlaidCategory.display(primary: "INCOME") == "Income")
    }

    @Test func anUnknownCategoryFallsThroughInsteadOfCrashing() {
        // Plaid can add a primary category at any time. A new one must arrive as
        // an uncategorised row, not a crash or a shouty SCREAMING_SNAKE label
        // sitting in the transaction list.
        #expect(PlaidCategory.display(primary: "QUANTUM_TELEPORTATION") == nil)
        #expect(PlaidCategory.display(primary: nil) == nil)
    }
}
