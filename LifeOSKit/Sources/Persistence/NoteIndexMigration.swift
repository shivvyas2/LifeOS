import Foundation
import SwiftData

/// Brings an existing library up to what the index layer assumes, once.
///
/// Two jobs. Every page that predates the Inbox is stamped as filed, because
/// it was filed under the old model and showing someone their entire library
/// as unsorted capture would be a worse first run than any empty state. And
/// the index is built, since no document has ever been through the indexer.
///
/// Idempotent through a marker in `UserDefaults` rather than through the data,
/// because "has this store been stamped" genuinely is a local question: the
/// stamp is a one time interpretation of history, not a fact to sync. A second
/// run must not sweep up pages captured deliberately since.
///
/// `UserDefaults.currentAccount` is the per account suite, not the shared one.
/// Two people share a device's defaults but not their stores, and a marker in
/// the shared suite would let the second account skip its own stamp and meet
/// its whole library in the Inbox. `NoteSync` keys its cursor the same way,
/// for the same reason.
@MainActor
public enum NoteIndexMigration {
    static let marker = "notes.indexMigration.v1"

    @discardableResult
    public static func run(
        context: ModelContext,
        defaults: UserDefaults = .currentAccount
    ) throws -> Int {
        let key = marker
        if !defaults.bool(forKey: key) {
            let stamp = Date.now
            for document in try context.fetch(FetchDescriptor<NoteDocument>())
            where document.filedAt == nil {
                document.filedAt = stamp
            }
            try context.save()
            defaults.set(true, forKey: key)
        }
        return try NoteIndexer.rebuildAll(context: context)
    }
}
