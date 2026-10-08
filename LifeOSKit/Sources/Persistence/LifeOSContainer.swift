import Foundation
import SwiftData

public enum LifeOSContainer {
    public static let schema = Schema([
        DailyMetrics.self,
        UserGoals.self,
        WorkoutRecord.self,
        SleepRecord.self,
        WhoopRawRecord.self,
        PlanEntry.self,
        HabitTick.self,
        MoneyEntry.self,
        MoneyAccount.self,
        SpendBucket.self,
        MerchantCardRule.self,
        SectorScore.self,
        CheckInAnswer.self,
        CalendarEvent.self,
        ChatMessage.self,
        NoteDocument.self,
        NoteFolder.self,
        NoteTask.self,
        NoteLink.self,
        CatalogVideo.self,
        WorkoutBookmark.self,
        ProjectRecord.self,
        ProjectMemberRecord.self,
        MilestoneRecord.self,
        ProjectTaskRecord.self,
    ])

    /// In memory, for tests and previews.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// One store per account.
    ///
    /// The isolation the app relies on: two accounts on one device do not
    /// share rows because they do not share a file. See `UserScope` for why
    /// this rather than an owning column on every model.
    public static func make(for scope: UserScope, base: URL? = nil) throws -> ModelContainer {
        let root = try base ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = scope.directory(base: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = ModelConfiguration(schema: schema, url: scope.storeURL(base: root))
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Hands one account's store to another, once.
    ///
    /// A file move rather than a row by row copy, so it is atomic and costs
    /// the same whether the person wrote one note or a thousand.
    ///
    /// Refuses when the destination already has a store. Adopting into an
    /// account that has its own data would mean choosing which of two rows
    /// wins for every model in the schema, and the answer is not obviously
    /// either of them.
    /// Moves the store written before accounts existed into the first account
    /// that signs in.
    ///
    /// Every install before this change kept one unscoped store at SwiftData's
    /// default location. Scoping the store without moving that file would have
    /// looked exactly like the app deleting a year of notes on upgrade, so the
    /// first account to sign in adopts it and the file stops being anybody's
    /// by default.
    ///
    /// Runs once and then never matches again, because the legacy file is gone
    /// after the move.
    @discardableResult
    public static func adoptLegacyStore(into destination: UserScope, base: URL? = nil) throws -> Bool {
        let manager = FileManager.default
        let root = try base ?? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )

        // SwiftData's own default, which is what every build so far has used.
        let legacy = root.appendingPathComponent("default.store")
        let to = destination.storeURL(base: root)
        guard manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: to.path) else {
            return false
        }

        try manager.createDirectory(
            at: destination.directory(base: root), withIntermediateDirectories: true
        )
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: legacy.path + suffix)
            let destinationFile = URL(fileURLWithPath: to.path + suffix)
            guard manager.fileExists(atPath: sourceFile.path) else { continue }
            try manager.moveItem(at: sourceFile, to: destinationFile)
        }
        return true
    }

    @discardableResult
    public static func adopt(
        _ source: UserScope, into destination: UserScope, base: URL? = nil
    ) throws -> Bool {
        let manager = FileManager.default
        let root = try base ?? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )

        let from = source.storeURL(base: root)
        let to = destination.storeURL(base: root)
        guard manager.fileExists(atPath: from.path), !manager.fileExists(atPath: to.path) else {
            return false
        }

        try manager.createDirectory(
            at: destination.directory(base: root), withIntermediateDirectories: true
        )
        // SQLite keeps its write-ahead log and shared memory beside the
        // database. Moving the database alone would leave the most recent
        // writes behind in a log the new file has no way to find.
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: from.path + suffix)
            let destinationFile = URL(fileURLWithPath: to.path + suffix)
            guard manager.fileExists(atPath: sourceFile.path) else { continue }
            try manager.moveItem(at: sourceFile, to: destinationFile)
        }
        return true
    }
}
