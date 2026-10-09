import Foundation

/// The project card's lines, as words. Kept apart from the card so every
/// count and the milestone's three shapes are tested.
public enum ProjectHeadline {
    public static func commits(_ count: Int, isTodayWithoutCommits: Bool) -> String {
        if count == 0 { return isTodayWithoutCommits ? "No commits yet today" : "No commits" }
        return count == 1 ? "1 commit" : "\(count) commits"
    }

    public static func milestone(title: String, open: Int, total: Int, due: Date?, calendar: Calendar) -> String {
        if open == 0 { return "Milestone \(title) · all \(total) done" }
        let head = "Milestone \(title) · \(open) of \(total) left"
        guard let due else { return head }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return "\(head) · due \(due.formatted(style))"
    }

    public static func issues(_ count: Int) -> String {
        count == 1 ? "1 open issue" : "\(count) open issues"
    }

    public static func more(_ count: Int) -> String { "\(count) more" }

    /// Done over total as a whole percent, rounded, never truncated.
    public static func percent(done: Int, total: Int) -> Int {
        total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded())
    }

    public static func tasksDone(_ done: Int, of total: Int) -> String {
        if total == 0 { return "No tasks yet" }
        if done >= total { return "All \(total) tasks done" }
        return "\(done) of \(total) tasks done"
    }

    public static func closed(open: Int, total: Int) -> String {
        "\(total - open) of \(total) closed"
    }

    /// The day's momentum, one quiet line under the progress.
    public static func today(commits count: Int) -> String {
        switch count {
        case 0: "No commits yet today"
        case 1: "1 commit today"
        default: "\(count) commits today"
        }
    }

    public static func asOf(_ date: Date, calendar: Calendar) -> String {
        // The locale's own short time: 9:40 AM in the US, 9:40 in Britain.
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return "As of \(date.formatted(style))"
    }
}
