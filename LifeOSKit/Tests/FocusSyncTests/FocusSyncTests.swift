import Testing
import Foundation
import SwiftData
import Integrations
import Persistence
@testable import FocusSync

final class FakeRemote: FocusRemote, @unchecked Sendable {
    var inserted: [Data] = []
    var insertError: Error?
    var rows = Data("[]".utf8)
    func insertIgnoringDuplicates(table: String, body: Data, accessToken: String) async throws {
        if let insertError { throw insertError }
        inserted.append(body)
    }
    func focusRows(since: Date, accessToken: String) async throws -> Data { rows }
}

@MainActor
struct FocusSyncTests {
    private let signedIn = AuthSession(accessToken: "t", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600),
                                       userID: "u1", phone: nil, email: nil)

    /// The container is returned too: a context whose in-memory container
    /// has been released traps on its next fetch.
    private func finished() throws -> (ModelContainer, ModelContext) {
        let container = try LifeOSContainer.make(inMemory: true)
        try FocusStore(context: container.mainContext).record(mood: "focus", source: "soundscape",
            startedAt: .now.addingTimeInterval(-900), endedAt: .now, focusedSeconds: 900,
            blocksCompleted: 1, projectTaskID: nil)
        return (container, container.mainContext)
    }

    @Test func uploadsPendingAndMarksThem() async throws {
        let remote = FakeRemote()
        let session = signedIn
        let (container, context) = try finished()
        defer { withExtendedLifetime(container) {} }
        let sync = FocusSync(context: context, remote: remote, owner: "u1", session: { session })
        #expect(await sync.uploadPending() == 1)
        #expect(sync.pendingCount == 0)
        let body = String(decoding: try #require(remote.inserted.first), as: UTF8.self)
        #expect(body.contains("\"focused_seconds\":900"))
        #expect(!body.contains("user_id"))   // the server fills it from the token
    }

    @Test func skipsWhenSignedOut() async throws {
        let remote = FakeRemote()
        let (container, context) = try finished()
        defer { withExtendedLifetime(container) {} }
        let sync = FocusSync(context: context, remote: remote, owner: "u1", session: { nil })
        #expect(await sync.uploadPending() == 0)
        #expect(remote.inserted.isEmpty)
        #expect(sync.pendingCount == 1)
    }

    @Test func skipsWhenTheTokenHasExpired() async throws {
        let remote = FakeRemote()
        let expired = AuthSession(accessToken: "t", refreshToken: "r", expiresAt: .now.addingTimeInterval(-10),
                                  userID: "u1", phone: nil, email: nil)
        let (container, context) = try finished()
        defer { withExtendedLifetime(container) {} }
        let sync = FocusSync(context: context, remote: remote, owner: "u1", session: { expired })
        #expect(await sync.uploadPending() == 0)
        #expect(remote.inserted.isEmpty)
    }

    @Test func aFailedUploadLeavesRecordsPending() async throws {
        let remote = FakeRemote()
        remote.insertError = SupabaseREST.RESTError.transport
        let session = signedIn
        let (container, context) = try finished()
        defer { withExtendedLifetime(container) {} }
        let sync = FocusSync(context: context, remote: remote, owner: "u1", session: { session })
        #expect(await sync.uploadPending() == 0)
        #expect(sync.pendingCount == 1)
    }

    @Test func pullMergesRowsFromElsewhereOnce() async throws {
        let remote = FakeRemote()
        let id = UUID()
        remote.rows = Data("""
        [{"id":"\(id)","mood":"relax","source":"silence","started_at":"2026-10-10T09:00:00+00:00",
          "ended_at":"2026-10-10T09:25:00.123456+00:00","focused_seconds":1500,"blocks_completed":1,"project_task_id":null}]
        """.utf8)
        let session = signedIn
        let container = try LifeOSContainer.make(inMemory: true)
        let sync = FocusSync(context: container.mainContext, remote: remote, owner: "u1", session: { session })
        let now = ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!
        #expect(await sync.pullWeek(now: now) == 1)
        #expect(await sync.pullWeek(now: now) == 0)
        withExtendedLifetime(container) {}
    }

    /// PostgREST rejects a bulk insert whose objects do not all have the same
    /// keys, so a nil task or end must be sent as null, never left out.
    @Test func everyRowInABatchHasTheSameKeys() async throws {
        let container = try LifeOSContainer.make(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: .now.addingTimeInterval(-900), endedAt: .now,
                         focusedSeconds: 900, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "relax", source: "silence", startedAt: .now.addingTimeInterval(-600), endedAt: .now,
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: UUID())
        let remote = FakeRemote()
        let session = signedIn
        let sync = FocusSync(context: container.mainContext, remote: remote, owner: "u1", session: { session })
        #expect(await sync.uploadPending() == 2)
        let body = try #require(remote.inserted.first)
        let rows = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(Set(rows[0].keys) == Set(rows[1].keys))
        #expect(rows[0].keys.contains("project_task_id"))
    }

    /// The store belongs to one account. If the current session is someone
    /// else's (an account switch mid-run), nothing goes up and nothing of
    /// theirs comes down into this store.
    @Test func refusesASessionForAnotherAccount() async throws {
        let (container, context) = try finished()
        defer { withExtendedLifetime(container) {} }
        let remote = FakeRemote()
        remote.rows = Data(#"[{"id":"\#(UUID())","mood":"focus","source":"silence","started_at":"2026-10-10T09:00:00Z","ended_at":null,"focused_seconds":60,"blocks_completed":0,"project_task_id":null}]"#.utf8)
        let other = AuthSession(accessToken: "b", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600),
                                userID: "someone-else", phone: nil, email: nil)
        let sync = FocusSync(context: context, remote: remote, owner: "u1", session: { other })
        #expect(await sync.uploadPending() == 0)
        #expect(await sync.pullWeek() == 0)
        #expect(remote.inserted.isEmpty)
        #expect(sync.pendingCount == 1)
    }
}
