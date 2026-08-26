import Foundation
import SwiftData

/// One budget: a name, a monthly limit, and the raw claim keys it counts.
///
/// A claim key may be held by at most one bucket. `MoneyStore` enforces that
/// on write; nothing resolves collisions at read time, because by then the
/// same transaction has already counted twice and every total is quietly
/// wrong.
@Model
public final class SpendBucket {
    public var id: UUID
    public var name: String
    /// Always positive; the store rejects anything else.
    public var monthlyLimit: Double
    /// Raw claim keys: `MoneyEntry.claimKey` values.
    public var claimedRaw: [String]
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String, monthlyLimit: Double, claimedRaw: [String] = [], sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.monthlyLimit = monthlyLimit
        self.claimedRaw = claimedRaw
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}

public enum SpendBucketError: Error, Equatable {
    case limitNotPositive
}

extension MoneyEntry {
    /// What a bucket claims. The raw Plaid detailed code when the entry has
    /// one, else a manual entry's free-form category. `category` is display
    /// text and never keys arithmetic; see the `categoryCode` note above.
    public var claimKey: String? { categoryCode ?? category }
}
