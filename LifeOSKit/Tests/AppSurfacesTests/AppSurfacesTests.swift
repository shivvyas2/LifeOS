import Foundation
import Testing
@testable import AppSurfaces

struct AppSurfacesTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var noon: Date { Date(timeIntervalSince1970: 1_800_014_400) }

    @Test func snapshotIsBoundedAndMissingIsNotZero() {
        let value = SurfaceSnapshot(ownerID: "a", generatedAt: noon, calendar: calendar)
        #expect(value.steps == nil)
        #expect(value.sleepText == "—")
        #expect(value.isAvailable(at: noon))
        #expect(!value.isAvailable(at: value.expiresAt))
        #expect(value.expiresAt <= noon.addingTimeInterval(6 * 3600))
        #expect(!SurfaceSnapshot(generatedAt: noon).isAvailable(at: noon))
    }
    @Test func snapshotExpiresAtMidnight() {
        let beforeMidnight = calendar.startOfDay(for: noon).addingTimeInterval(86300)
        let value = SurfaceSnapshot(ownerID: "a", generatedAt: beforeMidnight, calendar: calendar)
        #expect(value.expiresAt.timeIntervalSince(beforeMidnight) == 100)
    }
    @Test func rejectsInvalidMetricsAndClampsGoal() {
        let value = SurfaceSnapshot(ownerID: "a", steps: -1, stepGoal: 0, sleepMinutes: -1, exerciseMinutes: -1)
        #expect(value.steps == nil && value.sleepMinutes == nil && value.exerciseMinutes == nil)
        #expect(value.stepGoal == 1)
        #expect(SurfaceSnapshot(steps: 12000, stepGoal: 8000).stepProgress == 1)
        #expect(SurfaceSnapshot(sleepMinutes: 452).sleepText == "7h 32m")
    }
    @Test func tombstoneReplacesEveryAccountFieldAndRejectsOldWatchDelivery() throws {
        let suite = "test.surfaces.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = SurfaceSnapshot(ownerID: "a", generatedAt: noon, steps: 9999)
        a.write(to: defaults)
        let cleared = SurfaceSnapshot(generatedAt: noon.addingTimeInterval(1))
        cleared.write(to: defaults)
        let loaded = try #require(SurfaceSnapshot.read(from: defaults))
        #expect(loaded.ownerID == nil && loaded.steps == nil)
        #expect(!a.supersedes(loaded))
        let b = SurfaceSnapshot(ownerID: "b", generatedAt: noon.addingTimeInterval(2), steps: 20)
        #expect(b.supersedes(loaded))
        b.write(to: defaults)
        #expect(SurfaceSnapshot.read(from: defaults)?.steps == 20)
    }
    @Test func inboxDeduplicatesPreservesReadAndRejectsAnotherAccount() {
        var first = InboxEntry(ownerID: "a", text: "Take a break", trigger: "rest", day: "2026-09-14")
        first.isRead = true
        let duplicate = InboxEntry(ownerID: "a", text: first.text, trigger: first.trigger, day: first.day)
        let entries = InboxEntry.inserting(duplicate, into: [first], ownerID: "a")
        #expect(entries.count == 1 && entries[0].isRead)
        let foreign = InboxEntry(ownerID: "b", text: "Private", trigger: "sleep", day: first.day)
        #expect(InboxEntry.inserting(foreign, into: entries, ownerID: "a") == entries)
        #expect(InboxEntry.inserting(foreign, into: entries, ownerID: "b") == [foreign])
    }
    @Test func inboxKeepsOnlyOneHundredMostRecentEntries() {
        let entries = (0..<120).map { InboxEntry(ownerID: "a", text: "Check-in", trigger: "rest", day: "\($0)", receivedAt: noon.addingTimeInterval(Double($0))) }
        let result = InboxEntry.inserting(entries[0], into: entries, ownerID: "a")
        #expect(result.count == 100)
        #expect(result.first?.day == "119")
        #expect(result.last?.day == "20")
    }
}
