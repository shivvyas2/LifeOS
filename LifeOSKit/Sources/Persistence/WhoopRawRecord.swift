import Foundation
import SwiftData

/// An unprocessed Whoop payload, retained so re-derivation never requires
/// re-fetching. Whoop rate-limits, and a derivation bug found six months from
/// now must be fixable without asking for the data again.
///
/// The columns mirror the `whoop_raw` table in the Supabase schema so moving
/// this server-side later is a copy rather than a redesign.
@Model
public final class WhoopRawRecord {
    #Unique<WhoopRawRecord>([\.kind, \.externalID])

    /// Whoop's collection name: recovery, sleep, cycle or workout. A String and
    /// not an enum, so a collection we have never seen lands as data rather
    /// than as a failed insert.
    public var kind: String
    public var externalID: String
    public var payload: Data
    public var receivedAt: Date

    public init(kind: String, externalID: String, payload: Data, receivedAt: Date = .now) {
        self.kind = kind
        self.externalID = externalID
        self.payload = payload
        self.receivedAt = receivedAt
    }
}

/// Reads and writes the raw archive. Upserts on (kind, externalID) because a
/// re-sync returns records already seen.
@MainActor
public struct WhoopArchive {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func store(kind: String, externalID: String, payload: Data) throws {
        let existing = try context.fetch(
            FetchDescriptor<WhoopRawRecord>(
                predicate: #Predicate { $0.kind == kind && $0.externalID == externalID }
            )
        ).first

        if let existing {
            existing.payload = payload
            existing.receivedAt = .now
        } else {
            context.insert(WhoopRawRecord(kind: kind, externalID: externalID, payload: payload))
        }
        try context.save()
    }

    /// Batched: one save for a whole page, because a save per record turns a
    /// fourteen-day sync into hundreds of writes.
    public func store(_ records: [(kind: String, externalID: String, payload: Data)]) throws {
        for record in records {
            let kind = record.kind
            let id = record.externalID
            let existing = try context.fetch(
                FetchDescriptor<WhoopRawRecord>(
                    predicate: #Predicate { $0.kind == kind && $0.externalID == id }
                )
            ).first

            if let existing {
                existing.payload = record.payload
                existing.receivedAt = .now
            } else {
                context.insert(WhoopRawRecord(kind: kind, externalID: id, payload: record.payload))
            }
        }
        try context.save()
    }

    public func payloads(kind: String) throws -> [Data] {
        try context.fetch(
            FetchDescriptor<WhoopRawRecord>(
                predicate: #Predicate { $0.kind == kind },
                sortBy: [SortDescriptor(\.receivedAt)]
            )
        ).map(\.payload)
    }

    /// Sibling to `payloads(kind:)` rather than a change to it: the four
    /// collection kinds carry their own date inside the payload and never
    /// need `receivedAt`, so their call sites should not have to churn to
    /// tolerate a shape they do not use. The body kind has no date field at
    /// all, and `receivedAt` is the only day a rebuild can attribute it to.
    public func records(kind: String) throws -> [(payload: Data, receivedAt: Date)] {
        try context.fetch(
            FetchDescriptor<WhoopRawRecord>(
                predicate: #Predicate { $0.kind == kind },
                sortBy: [SortDescriptor(\.receivedAt)]
            )
        ).map { (payload: $0.payload, receivedAt: $0.receivedAt) }
    }

    public func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<WhoopRawRecord>())
    }
}
