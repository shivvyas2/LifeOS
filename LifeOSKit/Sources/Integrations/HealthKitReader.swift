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
/// `NSHealthUpdateUsageDescription` and nothing Almanac can do to a user's
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
        var types = Set(HealthMetric.universal.compactMap(Self.sampleType) as [HKSampleType])
            .map { $0 as HKObjectType }
        // Sex comes with the first request because it decides whether the
        // second one is ever shown. It is a single characteristic and reads as
        // "Sex" on the sheet, which is a far smaller thing to ask of everyone
        // than menstrual data.
        if let sex = HKCharacteristicType.characteristicType(forIdentifier: .biologicalSex) {
            types.append(sex)
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(types))
        } catch {
            Self.log.error("authorisation failed: \(error.localizedDescription, privacy: .public)")
            throw HealthKitError.authorisationRefused
        }
    }

    /// The second prompt, asked only when cycle tracking is turned on.
    public func requestCycleAuthorisation() async throws {
        guard isAvailable else { throw HealthKitError.unavailableOnThisDevice }
        let types = Set(HealthMetric.cycleOnly.compactMap(Self.sampleType) as [HKSampleType])
        guard !types.isEmpty else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            Self.log.error("cycle authorisation failed: \(error.localizedDescription, privacy: .public)")
            throw HealthKitError.authorisationRefused
        }
    }

    /// Whether cycle tracking should be on by default for this person.
    ///
    /// Reads Health's own sex characteristic, which is the user's setting in
    /// Apple's app and the same thing Health uses to decide whether to show
    /// Cycle Tracking. Returns a plain Bool rather than the HealthKit enum so
    /// the view models stay free of the framework, which is the arrangement
    /// that lets them be reasoned about and tested without a device.
    ///
    /// A default, not a rule. Who tracks a cycle is not answered by this
    /// field, so the setting is offered either way.
    public func healthSuggestsCycleTracking() -> Bool {
        (try? store.biologicalSex().biologicalSex) == .female
    }

    /// Every metric for one day, skipping the ones with nothing recorded.
    ///
    /// A metric that errors is dropped rather than failing the day: one
    /// unreadable type must not cost the user the other nine.
    public func day(_ date: Date, includingCycle: Bool = false) async -> HealthDay {
        var values: [HealthMetric: Double] = [:]
        let metrics = includingCycle ? HealthMetric.allCases : HealthMetric.universal
        for metric in metrics {
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

        switch metric {
        case .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes:
            return try await sleepMinutes(metric, in: range)
        case .mindfulMinutes:
            return try await categoryMinutes(.mindfulSession, in: range)
        case .menstrualFlowLevel:
            return try await categoryLevel(.menstrualFlow, in: range)
        default:
            break
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
                let raw = quantity?.doubleValue(for: unit)
                continuation.resume(returning: raw.map { $0 * Self.scale(for: metric) })
            }
            store.execute(query)
        }
    }

    /// Sleep is a category, not a quantity, so it is summed by hand.
    ///
    /// One query answers every sleep metric. `.inBed` is time on a mattress,
    /// not sleep, and counting it as sleep would inflate the night by however
    /// long its owner reads before turning the light off; it is reported
    /// separately as time in bed instead, where it is genuinely interesting
    /// next to the time actually asleep.
    private func sleepMinutes(_ metric: HealthMetric, in range: NSPredicate) async throws -> Double? {
        let samples = try await categorySamples(.sleepAnalysis, in: range)

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        let wanted: Set<Int>
        switch metric {
        case .sleepMinutes:     wanted = asleep
        case .deepSleepMinutes: wanted = [HKCategoryValueSleepAnalysis.asleepDeep.rawValue]
        case .remSleepMinutes:  wanted = [HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        case .coreSleepMinutes: wanted = [HKCategoryValueSleepAnalysis.asleepCore.rawValue]
        case .awakeMinutes:     wanted = [HKCategoryValueSleepAnalysis.awake.rawValue]
        case .timeInBedMinutes: wanted = [HKCategoryValueSleepAnalysis.inBed.rawValue]
        default:                return nil
        }

        let seconds = samples
            .filter { wanted.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 60 : nil
    }

    /// Total duration of a category's samples, for the ones that are events
    /// with a length rather than a measurement. Mindfulness is the case.
    private func categoryMinutes(
        _ identifier: HKCategoryTypeIdentifier, in range: NSPredicate
    ) async throws -> Double? {
        let samples = try await categorySamples(identifier, in: range)
        let seconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 60 : nil
    }

    /// The day's recorded level for an ordinal category. The last sample wins:
    /// a value entered later in the day is a correction of the earlier one.
    private func categoryLevel(
        _ identifier: HKCategoryTypeIdentifier, in range: NSPredicate
    ) async throws -> Double? {
        let samples = try await categorySamples(identifier, in: range)
        guard let latest = samples.max(by: { $0.startDate < $1.startDate }) else { return nil }
        return Double(latest.value)
    }

    private func categorySamples(
        _ identifier: HKCategoryTypeIdentifier, in range: NSPredicate
    ) async throws -> [HKCategorySample] {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
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
    }

    // MARK: - Mapping

    static func sampleType(for metric: HealthMetric) -> HKSampleType? {
        if let identifier = quantityIdentifier(for: metric) {
            return HKQuantityType(identifier)
        }
        switch metric {
        case .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes:
            return HKCategoryType(.sleepAnalysis)
        case .mindfulMinutes:
            return HKCategoryType(.mindfulSession)
        case .menstrualFlowLevel:
            return HKCategoryType(.menstrualFlow)
        default:
            return nil
        }
    }

    /// Nil for the category types, which are read by hand above.
    static func quantityIdentifier(for metric: HealthMetric) -> HKQuantityTypeIdentifier? {
        switch metric {
        case .steps:                        .stepCount
        case .activeEnergyKcal:             .activeEnergyBurned
        case .restingEnergyKcal:            .basalEnergyBurned
        case .exerciseMinutes:              .appleExerciseTime
        case .standMinutes:                 .appleStandTime
        case .distanceKm:                   .distanceWalkingRunning
        case .flightsClimbed:               .flightsClimbed
        case .restingHR:                    .restingHeartRate
        case .walkingHR:                    .walkingHeartRateAverage
        case .hrvMs:                        .heartRateVariabilitySDNN
        case .vo2Max:                       .vo2Max
        case .cardioRecoveryBpm:            .heartRateRecoveryOneMinute
        case .weightKg:                     .bodyMass
        case .bodyFatPercentage:            .bodyFatPercentage
        case .leanBodyMassKg:               .leanBodyMass
        case .heightCm:                     .height
        case .spo2Percentage:               .oxygenSaturation
        case .respiratoryRate:              .respiratoryRate
        case .wristTemperatureCelsius:      .appleSleepingWristTemperature
        case .bodyTemperatureCelsius:       .bodyTemperature
        case .bloodPressureSystolic:        .bloodPressureSystolic
        case .bloodPressureDiastolic:       .bloodPressureDiastolic
        case .bloodGlucoseMgDl:             .bloodGlucose
        case .waterML:                      .dietaryWater
        case .dietaryEnergyKcal:            .dietaryEnergyConsumed
        case .proteinG:                     .dietaryProtein
        case .carbsG:                       .dietaryCarbohydrates
        case .fatG:                         .dietaryFatTotal
        case .caffeineMg:                   .dietaryCaffeine
        case .daylightMinutes:              .timeInDaylight
        case .walkingSpeedKmh:              .walkingSpeed
        case .walkingStepLengthCm:          .walkingStepLength
        case .walkingAsymmetryPercentage:   .walkingAsymmetryPercentage
        case .doubleSupportPercentage:      .walkingDoubleSupportPercentage
        case .walkingSteadinessPercentage:  .appleWalkingSteadiness
        case .basalBodyTemperatureCelsius:  .basalBodyTemperature
        case .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes,
             .mindfulMinutes, .menstrualFlowLevel:
            nil
        }
    }

    static func unit(for metric: HealthMetric) -> HKUnit? {
        switch metric {
        case .steps, .flightsClimbed:       .count()
        case .activeEnergyKcal, .restingEnergyKcal, .dietaryEnergyKcal: .kilocalorie()
        case .exerciseMinutes, .standMinutes, .daylightMinutes: .minute()
        case .distanceKm:                   .meterUnit(with: .kilo)
        case .restingHR, .walkingHR, .cardioRecoveryBpm:
            HKUnit.count().unitDivided(by: .minute())
        case .hrvMs:                        .secondUnit(with: .milli)
        case .vo2Max:
            HKUnit(from: "ml/kg*min")
        case .weightKg, .leanBodyMassKg:    .gramUnit(with: .kilo)
        case .heightCm, .walkingStepLengthCm: .meterUnit(with: .centi)
        // HealthKit reports these as a 0...1 fraction. `scale(for:)` below
        // turns them into the percentage everything else in the app stores.
        case .bodyFatPercentage, .spo2Percentage, .walkingAsymmetryPercentage,
             .doubleSupportPercentage, .walkingSteadinessPercentage: .percent()
        case .respiratoryRate:              HKUnit.count().unitDivided(by: .minute())
        case .wristTemperatureCelsius, .bodyTemperatureCelsius,
             .basalBodyTemperatureCelsius:  .degreeCelsius()
        case .bloodPressureSystolic, .bloodPressureDiastolic: .millimeterOfMercury()
        case .bloodGlucoseMgDl:
            HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case .waterML:                      .literUnit(with: .milli)
        case .proteinG, .carbsG, .fatG:     .gram()
        case .caffeineMg:                   .gramUnit(with: .milli)
        case .walkingSpeedKmh:
            HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour())
        case .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes,
             .mindfulMinutes, .menstrualFlowLevel:
            nil
        }
    }

    /// What to multiply HealthKit's number by to get the unit the app stores.
    ///
    /// Only percentages need it, and they need it badly: `HKUnit.percent()`
    /// yields 0.98 for a 98% blood oxygen reading. The app stores percentages
    /// as percentages everywhere else, Whoop included, so a Health-sourced
    /// SpO2 was landing two orders of magnitude below a Whoop-sourced one and
    /// rendering as "1.0". It went unnoticed because Whoop owns that field and
    /// Health only fills its gaps.
    static func scale(for metric: HealthMetric) -> Double {
        unit(for: metric) == .percent() ? 100 : 1
    }

    /// Counts accumulate across the day; measurements are averaged over it.
    /// Summing a heart rate would produce a number in the thousands.
    static func option(for metric: HealthMetric) -> HKStatisticsOptions {
        switch metric {
        case .steps, .activeEnergyKcal, .restingEnergyKcal, .exerciseMinutes,
             .standMinutes, .distanceKm, .flightsClimbed, .waterML,
             .dietaryEnergyKcal, .proteinG, .carbsG, .fatG, .caffeineMg,
             .daylightMinutes:
            .cumulativeSum
        default:
            .discreteAverage
        }
    }
}
#endif
