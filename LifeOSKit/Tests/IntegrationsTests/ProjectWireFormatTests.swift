import Testing
import Foundation
@testable import Integrations

@Suite struct ProjectWireFormatTests {
    private func roundTrip(_ payload: [String: Any]) throws -> [String: Any] {
        let data = try SupabaseREST.encode([payload])
        return try #require(SupabaseREST.decode(data).first)
    }

    @Test func aProjectRoundTrips() throws {
        let row = ProjectRow(id: UUID(), name: "LifeOS 1.1", scope: "Ship Notes", startsOn: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 86_400 * 20_000 + 43_200)),
                             endsOn: nil, colour: "tomato", ownerID: UUID(), repo: "o/r", archivedAt: nil,
                             updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deletedAt: nil)
        #expect(ProjectRow(json: try roundTrip(row.payload())) == row)
    }

    @Test func aTaskRoundTrips() throws {
        let row = ProjectTaskRow(id: UUID(), projectID: UUID(), milestoneID: nil, title: "Wireframes", notes: "Flows",
                                 status: "doing", ownerID: UUID(), dueOn: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 86_400 * 20_003 + 43_200)),
                                 startsAt: Date(timeIntervalSince1970: 1_700_003_600), endsAt: Date(timeIntervalSince1970: 1_700_007_200),
                                 position: 2, doneAt: nil, updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deletedAt: nil)
        #expect(ProjectTaskRow(json: try roundTrip(row.payload())) == row)
    }

    @Test func aMilestoneAndAMemberRoundTrip() throws {
        let milestone = MilestoneRow(id: UUID(), projectID: UUID(), title: "Alpha", dueOn: nil, position: 1,
                                     updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deletedAt: nil)
        #expect(MilestoneRow(json: try roundTrip(milestone.payload())) == milestone)
        let member = ProjectMemberRow(id: UUID(), projectID: UUID(), userID: UUID(), role: "member",
                                      addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(ProjectMemberRow(json: try roundTrip(member.payload())) == member)
    }

    @Test func aRowMissingItsIdIsDropped() {
        #expect(ProjectRow(json: ["name": "x"]) == nil)
    }

    @Test func aDueDateKeepsItsLocalDay() throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 14))!
        let row = ProjectTaskRow(id: UUID(), projectID: UUID(), milestoneID: nil, title: "T", notes: "", status: "todo",
                                 ownerID: nil, dueOn: afternoon, startsAt: nil, endsAt: nil, position: 0, doneAt: nil,
                                 updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deletedAt: nil)
        let payload = row.payload()
        #expect(payload["due_on"] as? String == "2026-10-09")
        let back = try #require(ProjectTaskRow(json: try roundTrip(payload)))
        #expect(calendar.isDate(try #require(back.dueOn), inSameDayAs: afternoon))
    }
}

