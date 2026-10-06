import Testing
import Foundation
@testable import DesignSystem

@Suite struct DayHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func placementCountsWholeDays() {
        let today = date(2026, 10, 6, hour: 23)
        #expect(DayPlacement.of(date(2026, 10, 6, hour: 1), now: today, calendar: calendar) == .today)
        #expect(DayPlacement.of(date(2026, 10, 5), now: today, calendar: calendar) == .past(daysAgo: 1))
        #expect(DayPlacement.of(date(2026, 10, 9), now: today, calendar: calendar) == .future(daysAhead: 3))
        #expect(DayPlacement.past(daysAgo: 2).isEditable == false)
        #expect(DayPlacement.today.isEditable && DayPlacement.future(daysAhead: 1).isEditable)
    }

    @Test func eyebrowNamesWhereTheDaySits() {
        let today = date(2026, 10, 6)
        func eyebrow(_ d: Date) -> String { DayHeadline.make(date: d, now: today, calendar: calendar, locale: en).eyebrow }
        #expect(eyebrow(date(2026, 10, 6)) == "Today · 6 October")
        #expect(eyebrow(date(2026, 10, 5)) == "Yesterday · 5 October")
        #expect(eyebrow(date(2026, 10, 7)) == "Tomorrow · 7 October")
        #expect(eyebrow(date(2026, 10, 8)) == "In 2 days · 8 October")
        #expect(eyebrow(date(2026, 10, 12)) == "In 6 days · 12 October")
        #expect(eyebrow(date(2026, 10, 4)) == "2 days ago · 4 October")
        #expect(eyebrow(date(2026, 9, 30)) == "6 days ago · 30 September")
    }

    @Test func farDaysShowTheDateAndTheYearOnlyWhenItDiffers() {
        let today = date(2026, 10, 6)
        let h = DayHeadline.make(date: date(2026, 11, 14), now: today, calendar: calendar, locale: en)
        #expect(h.eyebrow == "14 November")
        #expect(h.title == "Saturday")
        #expect(DayHeadline.make(date: date(2027, 1, 14), now: today, calendar: calendar, locale: en).eyebrow == "14 January 2027")
        #expect(DayHeadline.make(date: date(2026, 9, 29), now: today, calendar: calendar, locale: en).eyebrow == "29 September")
    }

    @Test func sectionsFollowThePlacement() {
        #expect(DaySections.visible(for: .today) == DaySection.allCases)
        #expect(DaySections.visible(for: .past(daysAgo: 3)) == [.agenda, .checklist, .readings, .money, .nudges])
        #expect(DaySections.visible(for: .future(daysAhead: 3)) == [.weather, .agenda, .checklist])
        #expect(DaySections.visible(for: .future(daysAhead: 9)) == [.weather, .agenda, .checklist])
        #expect(DaySections.visible(for: .future(daysAhead: 10)) == [.agenda, .checklist])
    }
}
