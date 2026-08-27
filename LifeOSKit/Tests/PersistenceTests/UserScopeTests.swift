import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite struct UserScopeTests {

    /// The isolation the whole feature rests on: two accounts cannot share
    /// rows because they do not share a file.
    @Test func twoAccountsGetDifferentStoreFiles() {
        let base = URL(fileURLWithPath: "/tmp/scope-test")
        let a = UserScope(id: "11111111-1111-1111-1111-111111111111")
        let b = UserScope(id: "22222222-2222-2222-2222-222222222222")

        #expect(a.storeURL(base: base) != b.storeURL(base: base))
        #expect(a.defaultsSuiteName != b.defaultsSuiteName)
    }

    /// A user id is a UUID and could never do this, which is exactly why it is
    /// worth proving that a malformed one still cannot escape the accounts
    /// directory.
    @Test func anIdCannotClimbOutOfTheAccountsDirectory() {
        let base = URL(fileURLWithPath: "/tmp/scope-test")
        let hostile = UserScope(id: "../../etc")
        let path = hostile.storeURL(base: base).path

        #expect(path.hasPrefix("/tmp/scope-test/Accounts/"))
        #expect(!path.contains(".."))
    }

    @Test func anEmptyIdStillProducesAUsableDirectory() {
        let base = URL(fileURLWithPath: "/tmp/scope-test")
        #expect(UserScope(id: "").storeURL(base: base).path.hasSuffix("unknown/store.sqlite"))
    }
}

@Suite @MainActor struct AccountAdoptionTests {

    private func temporaryBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("adopt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Every install before accounts existed kept one unscoped store. Not
    /// moving it would look exactly like the app deleting a year of notes on
    /// upgrade.
    @Test func theLegacyStoreIsAdoptedByTheFirstAccount() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let legacy = base.appendingPathComponent("default.store")
        try Data("notes".utf8).write(to: legacy)
        let user = UserScope(id: "user-1")

        #expect(try LifeOSContainer.adoptLegacyStore(into: user, base: base))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try Data(contentsOf: user.storeURL(base: base)) == Data("notes".utf8))
    }

    /// It runs once. A second account signing in later must not inherit the
    /// first one's data.
    @Test func theLegacyStoreIsAdoptedOnlyOnce() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try Data("notes".utf8).write(to: base.appendingPathComponent("default.store"))

        #expect(try LifeOSContainer.adoptLegacyStore(into: UserScope(id: "first"), base: base))
        #expect(try LifeOSContainer.adoptLegacyStore(into: UserScope(id: "second"), base: base) == false)
        #expect(!FileManager.default.fileExists(atPath: UserScope(id: "second").storeURL(base: base).path))
    }

    /// Adopting into an account that already has data would mean choosing
    /// which of two rows wins for every model in the schema, and the answer is
    /// not obviously either.
    @Test func adoptionRefusesWhenTheAccountAlreadyHasAStore() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let source = UserScope(id: "source")
        let user = UserScope(id: "user-2")
        for scope in [source, user] {
            try FileManager.default.createDirectory(
                at: scope.directory(base: base), withIntermediateDirectories: true
            )
            try Data(scope.id.utf8).write(to: scope.storeURL(base: base))
        }

        #expect(try LifeOSContainer.adopt(source, into: user, base: base) == false)
        // Neither store was touched.
        #expect(try Data(contentsOf: user.storeURL(base: base)) == Data("user-2".utf8))
    }

    /// SQLite keeps recent writes in a write-ahead log beside the database.
    /// Moving the database alone would strand them.
    @Test func adoptionCarriesTheWriteAheadLog() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let source = UserScope(id: "source-3")
        let user = UserScope(id: "user-3")
        try FileManager.default.createDirectory(
            at: source.directory(base: base), withIntermediateDirectories: true
        )
        let file = source.storeURL(base: base)
        try Data("db".utf8).write(to: file)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: file.path + "-wal"))

        #expect(try LifeOSContainer.adopt(source, into: user, base: base))
        let moved = URL(fileURLWithPath: user.storeURL(base: base).path + "-wal")
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func adoptingNothingIsNotAnError() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(try LifeOSContainer.adopt(UserScope(id: "absent"), into: UserScope(id: "user-4"), base: base) == false)
        #expect(try LifeOSContainer.adoptLegacyStore(into: UserScope(id: "user-4"), base: base) == false)
    }

    /// Rows written to one account's store must not appear in another's.
    @Test func rowsDoNotCrossBetweenAccounts() throws {
        let base = try temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let first = try LifeOSContainer.make(for: UserScope(id: "alice"), base: base)
        let store = NotesStore(context: ModelContext(first))
        try store.createDocument(title: "Alice's page", bucket: .projects)
        #expect(try store.documents(includeArchived: true).count == 1)

        let second = try LifeOSContainer.make(for: UserScope(id: "bob"), base: base)
        let bob = NotesStore(context: ModelContext(second))
        #expect(try bob.documents(includeArchived: true).isEmpty)
    }
}
