#if DEBUG
import Foundation
import CoreLocation
import AppSurfaces
import Integrations

/// A fixed forecast for previews: mild, cloudy, rain from three.
struct StubWeatherProvider: WeatherProviding {
    var forecast: DayForecast?

    static func sample(for day: Date, calendar: Calendar = .current) -> DayForecast {
        var rain = Array(repeating: 0.1, count: 24)
        for hour in 15...17 { rain[hour] = 0.55 }
        let start = calendar.startOfDay(for: day)
        return DayForecast(day: start, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                           highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                           rainChanceByHour: rain, windKph: 12, uvIndex: 3,
                           sunrise: calendar.date(bySettingHour: 7, minute: 12, second: 0, of: start),
                           sunset: calendar.date(bySettingHour: 18, minute: 31, second: 0, of: start),
                           fetchedAt: .now)
    }

    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? {
        forecast ?? Self.sample(for: day)
    }
}

/// A location that answers at once with whatever access the page wants.
@MainActor
final class StubLocation: LocationProviding {
    private(set) var access: LocationAccess
    init(access: LocationAccess = .granted) { self.access = access }
    func requestAccess() async -> LocationAccess {
        if access == .notDetermined { access = .granted }
        return access
    }
    func currentLocation() async throws -> CLLocation { CLLocation(latitude: 51.5, longitude: -0.12) }
} 
/// A fixed GitHub card for previews and the UI test.
struct StubGitHubProvider: GitHubDayProviding {
    var state: ProjectCardState?

    func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState? { state }

    private static let repoURL = URL(string: "https://github.com/shivvyas2/LifeOS")!

    private static func commits(_ subjects: [String]) -> [ProjectCommit] {
        subjects.enumerated().map { index, subject in
            ProjectCommit(subject: subject, url: repoURL.appendingPathComponent("commit/\(index)"))
        }
    }

    private static var dueOct20: Date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        return calendar.date(from: DateComponents(year: year, month: 10, day: 20, hour: 12))!
    }

    static let sevenCommits = ProjectCard(
        repo: "LifeOS", repoURL: repoURL, commitCount: 7,
        commits: commits([
            "fix(notes): close the gaps the review found",
            "test(notes): UI tests tap through the walkthrough with its real driver",
            "feat(design): a walkthrough script, anchors that report their frames",
            "feat(settings): replay the Notes walkthrough and the welcome tour",
            "feat(persistence): a page the app made goes only if it was left as made",
            "docs(plans): the Notes walkthrough",
            "chore(release): version 1.0.2, build 50, on every target",
        ]),
        isTodayWithoutCommits: false,
        followUp: .milestone(title: "1.1", open: 4, total: 9, due: dueOct20,
                             url: repoURL.appendingPathComponent("milestone/1")))

    static let issues = ProjectCard(
        repo: "LifeOS", repoURL: repoURL, commitCount: 3,
        commits: commits([
            "fix(day): close the gaps the review found",
            "feat(day): three ways into the day, and the day sheet goes",
            "feat(day): the day screen, its sections and six preview pages",
        ]),
        isTodayWithoutCommits: false,
        followUp: .issues(count: 3, newest: [
            ProjectIssue(title: "Crash when a note syncs offline", url: repoURL.appendingPathComponent("issues/12")),
            ProjectIssue(title: "Widget shows yesterday after midnight", url: repoURL.appendingPathComponent("issues/11")),
        ]))

    static let todayNone = ProjectCard(
        repo: "LifeOS", repoURL: repoURL, commitCount: 0, commits: [],
        isTodayWithoutCommits: true,
        followUp: .milestone(title: "1.1", open: 4, total: 9, due: dueOct20,
                             url: repoURL.appendingPathComponent("milestone/1")))
}
#endif
