import Foundation
import AppSurfaces

/// Heart-rate zones from age. Tanaka's estimate of maximum heart rate and
/// WHOOP's zone bands, so the number on the HUD agrees with the number in
/// the app the person already trusts.
///
/// No birth date means no zones, never a guessed maximum: a zone built on an
/// assumed age would be a reading the person never gave.
public struct HeartRateZones: Equatable, Sendable {
    public let maxHeartRate: Int

    public init?(birthDate: Date?, on date: Date = .now, calendar: Calendar = .current) {
        guard let birthDate,
              let age = calendar.dateComponents([.year], from: birthDate, to: date).year,
              (10...120).contains(age) else { return nil }
        maxHeartRate = Int((208.0 - 0.7 * Double(age)).rounded())
    }

    /// 0 below half of maximum, then one zone per ten percent up to 5.
    public func zone(for bpm: Int) -> Int {
        let fraction = Double(bpm) / Double(maxHeartRate)
        switch fraction {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}

/// Estimated effort on WHOOP's 0 to 21 scale.
///
/// Seconds in each zone add a weight to a running load, and the load maps
/// through a saturating curve so a long day approaches 21 without reaching
/// it. The constants are pinned by calibration tests: a steady hour in zone 3
/// is about 12, a hard ninety minutes about 18. Retuning is a deliberate
/// change with a diff, not a drift.
public struct EffortAccumulator: Equatable, Sendable {
    public static let weights: [Double] = [0, 0.15, 0.28, 0.35, 0.45, 0.63]
    public static let scale = 1500.0
    /// A gap in the stream is not effort that was measured. One reading
    /// credits at most this many seconds.
    public static let maxCredit: TimeInterval = 5

    public private(set) var load: Double

    public init(load: Double = 0) { self.load = max(0, load) }

    public mutating func add(zone: Int, seconds: TimeInterval) {
        guard seconds > 0, Self.weights.indices.contains(zone) else { return }
        load += Self.weights[zone] * seconds
    }

    public var effort: Double { 21 * (1 - exp(-load / Self.scale)) }

    /// Seconds to credit a reading at `date` given the previous reading.
    public static func credit(previous: Date?, at date: Date) -> TimeInterval {
        guard let previous else { return 0 }
        return min(maxCredit, max(0, date.timeIntervalSince(previous)))
    }
}

/// How far the person may push today: the highest zone worth visiting and
/// the effort range to aim for. Bands mirror WHOOP's recovery colours.
public struct EffortCeiling: Codable, Equatable, Sendable {
    public let maxZone: Int
    public let targetEffort: ClosedRange<Double>

    public init(maxZone: Int, targetEffort: ClosedRange<Double>) {
        self.maxZone = maxZone; self.targetEffort = targetEffort
    }

    public static let green = EffortCeiling(maxZone: 5, targetEffort: 14...18)
    public static let yellow = EffortCeiling(maxZone: 4, targetEffort: 10...14)
    public static let red = EffortCeiling(maxZone: 3, targetEffort: 4...10)
    /// Used when nothing is known about today. Cautious, without claiming a
    /// capacity that was never measured.
    public static let conservative = yellow

    public static func forCapacity(_ percent: Int) -> EffortCeiling {
        percent >= 67 ? .green : percent >= 34 ? .yellow : .red
    }
}

/// Today's battery: what the person has to spend, and where the number came
/// from. Computed once at session start and kept in the draft.
public struct Capacity: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case whoop, health }
    public let percent: Int
    public let source: Source
    public let measuredOn: Date

    public init(percent: Int, source: Source, measuredOn: Date) {
        self.percent = min(100, max(0, percent)); self.source = source; self.measuredOn = measuredOn
    }
    public var ceiling: EffortCeiling { .forCapacity(percent) }
}

/// One day's recovery inputs, lifted off `DailyMetrics` so the math has no
/// SwiftData in it. `date` is a calendar day start.
public struct RecoveryDay: Equatable, Sendable {
    public let date: Date
    public var whoopRecoveryPct: Double?
    public var whoopIsCalibrating: Bool?
    public var sleepPerformancePct: Double?
    public var hrvMs: Double?
    public var sleepMinutes: Int?

    public init(date: Date, whoopRecoveryPct: Double? = nil, whoopIsCalibrating: Bool? = nil,
                sleepPerformancePct: Double? = nil, hrvMs: Double? = nil, sleepMinutes: Int? = nil) {
        self.date = date; self.whoopRecoveryPct = whoopRecoveryPct; self.whoopIsCalibrating = whoopIsCalibrating
        self.sleepPerformancePct = sleepPerformancePct; self.hrvMs = hrvMs; self.sleepMinutes = sleepMinutes
    }
}

public enum CapacityMath {
    /// WHOOP first, Apple Health second, nothing third. Today's row, or
    /// yesterday's when today has not synced yet; anything older is stale.
    public static func capacity(days: [RecoveryDay], now: Date, calendar: Calendar = .current) -> Capacity? {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let recent = days.filter { $0.date >= yesterday && $0.date <= today }.sorted { $0.date > $1.date }

        if let day = recent.first(where: { $0.whoopRecoveryPct != nil && $0.whoopIsCalibrating != true }),
           let recovery = day.whoopRecoveryPct {
            let blended = day.sleepPerformancePct.map { 0.8 * recovery + 0.2 * $0 } ?? recovery
            return Capacity(percent: Int(blended.rounded()), source: .whoop, measuredOn: day.date)
        }

        if let day = recent.first(where: { $0.hrvMs != nil }), let hrv = day.hrvMs {
            let weekBefore = calendar.date(byAdding: .day, value: -7, to: day.date)!
            let baseline = days.filter { $0.date < day.date && $0.date >= weekBefore }.compactMap(\.hrvMs)
            guard baseline.count >= 3 else { return nil }
            let mean = baseline.reduce(0, +) / Double(baseline.count)
            let ratio = hrv / mean
            // 0.7 of baseline is 20, baseline is 65, 1.2 of baseline is 90.
            var percent = ratio <= 1 ? 20 + (ratio - 0.7) / 0.3 * 45 : 65 + (ratio - 1) / 0.2 * 25
            percent = min(90, max(20, percent))
            if let sleep = day.sleepMinutes {
                percent += min(10, max(-10, Double(sleep - 450) / 60 * 10))
            }
            return Capacity(percent: Int(percent.rounded()), source: .health, measuredOn: day.date)
        }
        return nil
    }
}

public enum EffortMath {
    /// Battery drains as effort approaches the target's top. Zero is a real
    /// event, the budget spent, not a missing value.
    public static func batteryRemaining(capacity: Int, effort: Double, ceiling: EffortCeiling) -> Int {
        let fraction = 1 - effort / ceiling.targetEffort.upperBound
        return max(0, Int((Double(capacity) * fraction).rounded()))
    }

    public static func pushState(zone: Int?, effort: Double, ceiling: EffortCeiling) -> PushState {
        let upper = ceiling.targetEffort.upperBound
        if effort > upper || (zone ?? 0) > ceiling.maxZone { return .overLimit }
        if zone == ceiling.maxZone || effort >= upper - 1.5 { return .nearLimit }
        if effort < ceiling.targetEffort.lowerBound && (zone ?? 0) <= 2 { return .easy }
        return .onTrack
    }
}

/// Joins the recorder's state into the one readout every surface renders.
public enum LiveReadoutBuilder {
    public static func readout(timer: ActivitySessionState, heartRate: Int?, zones: HeartRateZones?,
                               effort: EffortAccumulator, capacity: Capacity?,
                               energyKcal: Double?, distanceMeters: Double?,
                               reps: Int? = nil, setIndex: Int? = nil) -> LiveSessionReadout {
        let zone = zones.flatMap { zones in heartRate.map { zones.zone(for: $0) } }
        let ceiling = capacity?.ceiling ?? .conservative
        let push: PushState = zones == nil ? .onTrack : EffortMath.pushState(zone: zone, effort: effort.effort, ceiling: ceiling)
        var readout = LiveSessionReadout(elapsed: timer.accumulated, runningSince: timer.runningSince, push: push)
        readout.heartRate = heartRate
        readout.zone = zone
        readout.calories = energyKcal.map { Int($0.rounded()) }
        readout.distanceMeters = distanceMeters.map { Int($0.rounded()) }
        readout.capacitySource = capacity?.source.rawValue
        if zones != nil {
            readout.effort = (effort.effort * 10).rounded() / 10
            readout.ceilingMaxZone = ceiling.maxZone
            readout.ceilingTarget = ceiling.targetEffort
            readout.batteryPercent = capacity.map {
                EffortMath.batteryRemaining(capacity: $0.percent, effort: effort.effort, ceiling: ceiling)
            }
        }
        readout.reps = reps
        readout.setIndex = setIndex
        return readout
    }
}
