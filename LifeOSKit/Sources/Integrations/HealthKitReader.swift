import Foundation
import OSLog

/// One day's worth of Apple Health readings, already reduced to the units
/// `DailyMetrics` stores.
public struct HealthDay: Sendable, Equatable {
    public var date: Date
    public var values: [HealthMetric: Double]

    public init(date: Date, values: [HealthMetric: Double]) {
        self.date = date
        self.values = values
    }
}

/// Errors worth telling apart. Authorisation refused is a user decision and a
/// settings row; anything else is ours.
public enum HealthKitError: Error, Equatable {
    case unavailableOnThisDevice
    case authorisationRefused
    case queryFailed(String)
}

#if canImport(HealthKit)
import HealthKit

/// Reads Apple Health.
///
/// An actor because `HKHealthStore` is a shared resource and the sync can be
/// entered from a launch task and a foreground transition at the same time.
///
/// Read-only on purpose: the app never writes back, so there is no
/// `NSHealthUpdateUsageDescription` and nothing Life OS can do to a user's
/// Health data.
public actor HealthKitReader {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "healthkit")
    private let store = HKHealthStore()
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Asks once for everything the app reads.
    ///
    /// HealthKit deliberately never tells us whether read access was granted:
    /// `authorizationStatus(for:)` reports only whether we asked, because
    /// revealing a refusal would itself leak that the user has no data of that
    /// type. So there is nothing to check here, and an empty result later is
    /// indistinguishable from a refusal by design. That is why the settings row
    /// has to link out to Health rather than claim a connection state.
    public func requestAuthorisation() async throws {
        guard isAvailable else { throw HealthKitError.unavailableOnThisDevice }
        let types = Set(HealthMetric.allCases.compactMap(Self.sampleType))
        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            Self.log.error("authorisation failed: \(error.localizedDescription, privacy: .public)")
            throw HealthKitError.authorisationRefused
        }
    }

    /// Every metric for one day, skipping the ones with nothing recorded.
    ///
    /// A metric that errors is dropped rather than failing the day: one
    /// unreadable type must not cost the user the other nine.
    public func day(_ date: Date) async -> HealthDay {
        var values: [HealthMetric: Double] = [:]
        for metric in HealthMetric.allCases {
            if let value = try? await read(metric, on: date) {
                values[metric] = value
            }
        }
        return HealthDay(date: calendar.startOfDay(for: date), values: values)
    }

    private func read(_ metric: HealthMetric, on date: Date) async throws -> Double? {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let range = HKQuery.predicateForSamples(withStart: start, end: end)

        if metric == .sleepMinutes {
            return try await sleepMinutes(in: range)
        }
        guard let type = Self.sampleType(for: metric) as? HKQuantityType,
              let unit = Self.unit(for: metric) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: range,
                options: Self.option(for: metric)
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let quantity = Self.option(for: metric) == .cumulativeSum
                    ? statistics?.sumQuantity()
                    : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Sleep is a category, not a quantity, so it is summed by hand.
    ///
    /// Only the asleep stages count. `.inBed` is time on a mattress, not sleep,
    /// and counting it would inflate the night by however long its owner reads
    /// before turning the light off.
    private func sleepMinutes(in range: NSPredicate) async throws -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: range,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let seconds = samples
            .filter { asleep.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 60 : nil
    }

    // MARK: - Mapping

    static func sampleType(for metric: HealthMetric) -> HKSampleType? {
        switch metric {
        case .steps:            HKQuantityType(.stepCount)
        case .activeEnergyKcal: HKQuantityType(.activeEnergyBurned)
        case .exerciseMinutes:  HKQuantityType(.appleExerciseTime)
        case .weightKg:         HKQuantityType(.bodyMass)
        case .waterML:          HKQuantityType(.dietaryWater)
        case .restingHR:        HKQuantityType(.restingHeartRate)
        case .hrvMs:            HKQuantityType(.heartRateVariabilitySDNN)
        case .spo2Percentage:   HKQuantityType(.oxygenSaturation)
        case .respiratoryRate:  HKQuantityType(.respiratoryRate)
        case .sleepMinutes:     HKCategoryType(.sleepAnalysis)
        }
    }

    static func unit(for metric: HealthMetric) -> HKUnit? {
        switch metric {
        case .steps:            .count()
        case .activeEnergyKcal: .kilocalorie()
        case .exerciseMinutes:  .minute()
        case .weightKg:         .gramUnit(with: .kilo)
        case .waterML:          .literUnit(with: .milli)
        case .restingHR:        HKUnit.count().unitDivided(by: .minute())
        case .hrvMs:            .secondUnit(with: .milli)
        // Stored as a percentage, and HealthKit reports a 0...1 fraction, so
        // the scaling happens where the value is read, not on the screen.
        case .spo2Percentage:   .percent()
        case .respiratoryRate:  HKUnit.count().unitDivided(by: .minute())
        case .sleepMinutes:     nil
        }
    }

    /// Counts accumulate across the day; measurements are averaged over it.
    /// Summing a heart rate would produce a number in the thousands.
    static func option(for metric: HealthMetric) -> HKStatisticsOptions {
        switch metric {
        case .steps, .activeEnergyKcal, .exerciseMinutes, .waterML:
            .cumulativeSum
        case .weightKg, .restingHR, .hrvMs, .spo2Percentage, .respiratoryRate, .sleepMinutes:
            .discreteAverage
        }
    }
}
#endif
