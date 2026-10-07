import Testing
import Foundation
@testable import DesignSystem

@Suite struct ProjectHeadlineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    @Test func commitCounts() {
        #expect(ProjectHeadline.commits(1, isTodayWithoutCommits: false) == "1 commit")
        #expect(ProjectHeadline.commits(6, isTodayWithoutCommits: false) == "6 commits")
        #expect(ProjectHeadline.commits(0, isTodayWithoutCommits: true) == "No commits yet today")
        #expect(ProjectHeadline.commits(0, isTodayWithoutCommits: false) == "No commits")
    }

    @Test func milestones() {
        let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        #expect(ProjectHeadline.milestone(title: "1.1", open: 4, total: 9, due: due, calendar: calendar)
                == "Milestone 1.1 · 4 of 9 left · due Oct 20")
        #expect(ProjectHeadline.milestone(title: "1.1", open: 4, total: 9, due: nil, calendar: calendar)
                == "Milestone 1.1 · 4 of 9 left")
        #expect(ProjectHeadline.milestone(title: "1.1", open: 0, total: 9, due: due, calendar: calendar)
                == "Milestone 1.1 · all 9 done")
    }

    @Test func issuesMoreAndAsOf() {
        #expect(ProjectHeadline.issues(1) == "1 open issue")
        #expect(ProjectHeadline.issues(3) == "3 open issues")
        #expect(ProjectHeadline.more(4) == "4 more")
        let time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9, minute: 40))!
        #expect(ProjectHeadline.asOf(time, calendar: calendar) == "As of 9:40\u{202F}AM")
        var british = calendar
        british.locale = Locale(identifier: "en_GB")
        #expect(ProjectHeadline.asOf(time, calendar: british) == "As of 9:40")
    }
}
