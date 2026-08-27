import Foundation
import DesignSystem
import Persistence
import EventKit

/// Where calendar permission stands. Read synchronously so `load()` stays
/// synchronous; the prompt itself is only ever triggered from the agenda
/// card's connect button.
enum CalendarAccessState: Equatable {
    case notDetermined, denied, authorized

    static var current: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

/// One row of the Upcoming list: an event plus the day label it renders
/// under, precomputed so the view does no date math.
struct UpcomingEvent: Equatable, Identifiable {
    let id: UUID
    let dayLabel: String
    let event: CalendarEventSnapshot
}

/// Everything the Today screen renders, as plain values.
///
/// The view never sees a `DailyMetrics`, so rendering can never fault a
/// SwiftData object or trigger a fetch mid-layout.
struct TodaySnapshot: Equatable {
    var date: Date = .now
    var cells: [DotCell] = []
    var streak: Int = 0

    var steps: Int?
    var stepsProgress: Double?
    var sleepMinutes: Int?
    var sleepProgress: Double?
    var weightKg: Double?
    var recoveryPct: Double?

    /// The last seven days behind each figure, most recent last, with a slot
    /// for every day so a gap stays a gap in the chart rather than closing up.
    var stepsWeek: TrendSeries = TrendSeries(points: [])
    var sleepWeek: TrendSeries = TrendSeries(points: [])
    var weightWeek: TrendSeries = TrendSeries(points: [])
    var recoveryWeek: TrendSeries = TrendSeries(points: [])

    /// The goals the week is judged against, so a day that hit its target can
    /// be drawn differently from one that did not.
    var stepsTarget: Double?
    var sleepTargetMinutes: Double?

    var calendarAccess: CalendarAccessState = .notDetermined

    /// True when nothing has arrived from Apple Health or Whoop for the week.
    ///
    /// Asked so the screen can offer to connect a source rather than showing a
    /// grid of dashes. The app used to seed sixty days of invented history at
    /// first launch, so this state was unreachable and never had to be drawn;
    /// now that the numbers are real, an unconnected day is the normal first
    /// thing a person sees.
    var hasNoHealthData: Bool {
        steps == nil && sleepMinutes == nil && weightKg == nil && recoveryPct == nil
            && stepsWeek.points.isEmpty && sleepWeek.points.isEmpty
    }
    /// Today's events, sorted by start.
    var agenda: [CalendarEventSnapshot] = []
    /// The next seven days after today, flattened and capped by the view.
    var upcoming: [UpcomingEvent] = []
}
