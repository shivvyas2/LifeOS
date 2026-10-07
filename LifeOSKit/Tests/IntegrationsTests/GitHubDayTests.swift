import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubDayTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func theQueryCoversTheLocalDayByAuthorDate() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        #expect(GitHubDay.commitQuery(login: "shivvyas2", day: day, calendar: cal)
                == "author:shivvyas2 author-date:2026-10-07T00:00:00-04:00..2026-10-07T23:59:59-04:00")
    }

    @Test func aHalfHourZoneKeepsItsOffset() {
        let cal = calendar("Asia/Kolkata")
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 1))!
        #expect(GitHubDay.commitQuery(login: "a", day: day, calendar: cal)
                == "author:a author-date:2026-10-07T00:00:00+05:30..2026-10-07T23:59:59+05:30")
    }

    @Test func springForwardIsTwentyThreeHours() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let bounds = GitHubDay.bounds(for: day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 23 * 3600)
        #expect(GitHubDay.commitQuery(login: "a", day: day, calendar: cal)
                == "author:a author-date:2026-03-08T00:00:00-05:00..2026-03-08T23:59:59-04:00")
    }

    @Test func fallBackIsTwentyFiveHours() {
        let cal = calendar("America/New_York")
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let bounds = GitHubDay.bounds(for: day, calendar: cal)
        #expect(bounds.end.timeIntervalSince(bounds.start) == 25 * 3600)
    }
}
