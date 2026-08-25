import Foundation

/// One day's reading, or the absence of one.
///
/// `value` is optional so a day Whoop never reported stays a gap all the way to
/// the chart. Substituting zero would draw a bar claiming the user's HRV was
/// nought, which is the false zero this app refuses everywhere else.
public struct TrendPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double?

    public var id: Date { date }

    public init(date: Date, value: Double?) {
        self.date = date
        self.value = value
    }
}

/// A metric over a window of days, with the baseline a single reading needs to
/// mean anything.
///
/// SpO2 of 97.2 tells a reader nothing. SpO2 a tenth above their own fortnight
/// average tells them something. Every derived figure here ignores gaps rather
/// than counting them.
public struct TrendSeries: Sendable, Equatable {
    public let points: [TrendPoint]

    public init(points: [TrendPoint]) {
        self.points = points
    }

    /// The `count` days ending on `date`, oldest first.
    ///
    /// Every day gets a slot whether or not a reading exists for it, so the
    /// caller fills gaps with nil rather than dropping them. Compacting the
    /// days that do have readings would draw a chart whose neighbouring bars
    /// are not a day apart: a quieter lie than a false zero, but a lie.
    public static func days(endingOn date: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        let end = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: end)
        }
    }

    private var readings: [Double] { points.compactMap(\.value) }

    /// Whether the window holds a single reading. False is the shape of a fresh
    /// install, or of a metric this user has never connected a source for.
    public var hasAnyReading: Bool { points.contains { $0.value != nil } }

    /// Mean of the readings that exist. Nil when none do.
    public var average: Double? {
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    /// The most recent actual reading, which is not always the last slot: the
    /// window usually ends on a day Whoop has not scored yet.
    public var latest: Double? {
        points.reversed().first { $0.value != nil }?.value ?? nil
    }

    /// How far the latest reading sits from the baseline.
    ///
    /// Nil when there is only one reading: a lone value is its own average, and
    /// rendering "0 from baseline" would imply a history that has not been
    /// collected yet. A new connection therefore shows bare readings for its
    /// first fortnight rather than fabricated deltas.
    public var deltaFromAverage: Double? {
        guard readings.count > 1, let latest, let average else { return nil }
        return latest - average
    }
}
