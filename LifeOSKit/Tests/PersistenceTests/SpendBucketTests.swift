import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SpendBucketTests {
    private func makeStore() throws -> MoneyStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MoneyStore(context: ModelContext(container))
    }

    @Test func aClaimKeyMovesRatherThanBeingHeldTwice() throws {
        let store = try makeStore()
        let eatingOut = try store.addBucket(name: "Eating out", monthlyLimit: 300)
        let groceries = try store.addBucket(name: "Groceries", monthlyLimit: 450)
        try store.claim("FOOD_AND_DRINK_FAST_FOOD", for: eatingOut)

        let movedFrom = try store.claim("FOOD_AND_DRINK_FAST_FOOD", for: groceries)

        #expect(movedFrom == "Eating out")
        #expect(!eatingOut.claimedRaw.contains("FOOD_AND_DRINK_FAST_FOOD"))
        #expect(groceries.claimedRaw == ["FOOD_AND_DRINK_FAST_FOOD"])
    }

    @Test func claimingAFreeKeyReportsNoPreviousHolder() throws {
        let store = try makeStore()
        let bucket = try store.addBucket(name: "Transport", monthlyLimit: 120)
        #expect(try store.claim("TRANSPORTATION_TAXIS", for: bucket) == nil)
        #expect(bucket.claimedRaw == ["TRANSPORTATION_TAXIS"])
    }

    @Test func claimingAKeyTwiceForTheSameBucketDoesNotDuplicateIt() throws {
        let store = try makeStore()
        let bucket = try store.addBucket(name: "Transport", monthlyLimit: 120)
        try store.claim("TRANSPORTATION_TAXIS", for: bucket)
        try store.claim("TRANSPORTATION_TAXIS", for: bucket)
        #expect(bucket.claimedRaw == ["TRANSPORTATION_TAXIS"])
    }

    @Test func aBucketLimitMustBePositive() throws {
        let store = try makeStore()
        #expect(throws: SpendBucketError.limitNotPositive) {
            try store.addBucket(name: "Nothing", monthlyLimit: 0)
        }
        let bucket = try store.addBucket(name: "Coffee", monthlyLimit: 60)
        #expect(throws: SpendBucketError.limitNotPositive) {
            try store.updateBucket(bucket, name: "Coffee", monthlyLimit: -5)
        }
    }

    @Test func deletingABucketFreesItsKeys() throws {
        let store = try makeStore()
        let doomed = try store.addBucket(name: "Doomed", monthlyLimit: 100)
        try store.claim("ENTERTAINMENT_MUSIC", for: doomed)
        try store.deleteBucket(doomed)

        let successor = try store.addBucket(name: "Successor", monthlyLimit: 100)
        #expect(try store.claim("ENTERTAINMENT_MUSIC", for: successor) == nil)
        #expect(try store.buckets().map(\.name) == ["Successor"])
    }

    @Test func bucketsComeBackInSortOrder() throws {
        let store = try makeStore()
        try store.addBucket(name: "First", monthlyLimit: 10)
        try store.addBucket(name: "Second", monthlyLimit: 10)
        try store.addBucket(name: "Third", monthlyLimit: 10)
        #expect(try store.buckets().map(\.name) == ["First", "Second", "Third"])
    }

    /// The claim key prefers the raw code: `category` is display text, and
    /// keying arithmetic off display text means renaming a label silently
    /// changes what a budget counts.
    @Test func claimKeyPrefersTheCodeOverTheDisplayLabel() {
        let coded = MoneyEntry(
            date: .now, amount: -10, merchant: "Cafe",
            category: "Food & drink", categoryCode: "FOOD_AND_DRINK_COFFEE"
        )
        let manual = MoneyEntry(date: .now, amount: -10, merchant: "Cafe", category: "Coffee")
        let bare = MoneyEntry(date: .now, amount: -10, merchant: "Mystery")
        #expect(coded.claimKey == "FOOD_AND_DRINK_COFFEE")
        #expect(manual.claimKey == "Coffee")
        #expect(bare.claimKey == nil)
    }
}
