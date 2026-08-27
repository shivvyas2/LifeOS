import Foundation

/// A field Almanac can read out of Apple Health.
///
/// Deliberately its own enum rather than a set of HealthKit types: this file
/// carries the vocabulary and the merge rules, and must stay importable,
/// testable and buildable without the HealthKit framework. `HealthKitReader`
/// owns the translation to `HKQuantityType`.
///
/// Adding a metric is four lines here plus a mapping in the reader. Nothing
/// else changes: storage is keyed by `rawValue`, and the screens list whatever
/// the day actually holds, so a new metric appears on its own the first time
/// there is a reading for it.
public enum HealthMetric: String, CaseIterable, Sendable, Identifiable {
    // Movement
    case steps
    case activeEnergyKcal
    case restingEnergyKcal
    case exerciseMinutes
    case standMinutes
    case distanceKm
    case flightsClimbed

    // Heart and fitness
    case restingHR
    case walkingHR
    case hrvMs
    case vo2Max
    case cardioRecoveryBpm

    // Body
    case weightKg
    case bodyFatPercentage
    case leanBodyMassKg
    case heightCm

    // Sleep. `sleepMinutes` is the night's total; the rest break it down and
    // come from the same query, so they cost nothing extra to read.
    case sleepMinutes
    case deepSleepMinutes
    case remSleepMinutes
    case coreSleepMinutes
    case awakeMinutes
    case timeInBedMinutes

    // Vitals
    case spo2Percentage
    case respiratoryRate
    case wristTemperatureCelsius
    case bodyTemperatureCelsius
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bloodGlucoseMgDl

    // Intake
    case waterML
    case dietaryEnergyKcal
    case proteinG
    case carbsG
    case fatG
    case caffeineMg

    // Mind
    case mindfulMinutes
    case daylightMinutes

    // Gait. The phone records these passively, so most people have them
    // whether or not they ever went looking.
    case walkingSpeedKmh
    case walkingStepLengthCm
    case walkingAsymmetryPercentage
    case doubleSupportPercentage
    case walkingSteadinessPercentage

    // Cycle
    case basalBodyTemperatureCelsius
    case menstrualFlowLevel

    public var id: String { rawValue }

    /// Measured by a strap worn on the body, so a wearable outranks the phone.
    ///
    /// The phone infers these from a wrist it is not on, or does not measure
    /// them at all. Everything else on the list is counted passively by the
    /// phone itself, where the phone is the better authority.
    ///
    /// Sleep stages are deliberately absent for now: nothing writes them but
    /// Apple Health today, and they join this list in slice 3 when Fitbit
    /// starts reporting them.
    public var claimedByWearable: Bool {
        switch self {
        case .restingHR, .hrvMs, .spo2Percentage, .respiratoryRate, .sleepMinutes:
            true
        default:
            false
        }
    }

    /// A person can type this into the app, so a background sync must not
    /// replace what they entered on purpose.
    public var acceptsManualEntry: Bool {
        switch self {
        case .weightKg, .waterML: true
        default: false
        }
    }

    /// Health is the top authority among syncing sources: nothing else measures
    /// this and nobody types it, so the latest reading is simply the truth.
    /// This is what lets an afternoon sync correct the morning's step count.
    public var healthIsAuthoritative: Bool {
        !claimedByWearable && !acceptsManualEntry
    }

    /// Which panel the metric belongs to on screen.
    public enum Group: String, CaseIterable, Sendable {
        case movement, heart, body, sleep, vitals, intake, mind, gait, cycle

        public var title: String {
            switch self {
            case .movement: "Movement"
            case .heart:    "Heart and fitness"
            case .body:     "Body"
            case .sleep:    "Sleep"
            case .vitals:   "Vitals"
            case .intake:   "Intake"
            case .mind:     "Mind"
            case .gait:     "Walking"
            case .cycle:    "Cycle"
            }
        }
    }

    public var group: Group {
        switch self {
        case .steps, .activeEnergyKcal, .restingEnergyKcal, .exerciseMinutes,
             .standMinutes, .distanceKm, .flightsClimbed:
            .movement
        case .restingHR, .walkingHR, .hrvMs, .vo2Max, .cardioRecoveryBpm:
            .heart
        case .weightKg, .bodyFatPercentage, .leanBodyMassKg, .heightCm:
            .body
        case .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes:
            .sleep
        case .spo2Percentage, .respiratoryRate, .wristTemperatureCelsius,
             .bodyTemperatureCelsius, .bloodPressureSystolic,
             .bloodPressureDiastolic, .bloodGlucoseMgDl:
            .vitals
        case .waterML, .dietaryEnergyKcal, .proteinG, .carbsG, .fatG, .caffeineMg:
            .intake
        case .mindfulMinutes, .daylightMinutes:
            .mind
        case .walkingSpeedKmh, .walkingStepLengthCm, .walkingAsymmetryPercentage,
             .doubleSupportPercentage, .walkingSteadinessPercentage:
            .gait
        case .basalBodyTemperatureCelsius, .menstrualFlowLevel:
            .cycle
        }
    }

    public var title: String {
        switch self {
        case .steps:                        "Steps"
        case .activeEnergyKcal:             "Active energy"
        case .restingEnergyKcal:            "Resting energy"
        case .exerciseMinutes:              "Exercise"
        case .standMinutes:                 "Stand time"
        case .distanceKm:                   "Distance"
        case .flightsClimbed:               "Flights climbed"
        case .restingHR:                    "Resting heart rate"
        case .walkingHR:                    "Walking heart rate"
        case .hrvMs:                        "HRV"
        case .vo2Max:                       "VO2 max"
        case .cardioRecoveryBpm:            "Cardio recovery"
        case .weightKg:                     "Weight"
        case .bodyFatPercentage:            "Body fat"
        case .leanBodyMassKg:               "Lean mass"
        case .heightCm:                     "Height"
        case .sleepMinutes:                 "Asleep"
        case .deepSleepMinutes:             "Deep"
        case .remSleepMinutes:              "REM"
        case .coreSleepMinutes:             "Core"
        case .awakeMinutes:                 "Awake"
        case .timeInBedMinutes:             "In bed"
        case .spo2Percentage:               "Blood oxygen"
        case .respiratoryRate:              "Respiratory rate"
        case .wristTemperatureCelsius:      "Wrist temperature"
        case .bodyTemperatureCelsius:       "Body temperature"
        case .bloodPressureSystolic:        "Systolic"
        case .bloodPressureDiastolic:       "Diastolic"
        case .bloodGlucoseMgDl:             "Blood glucose"
        case .waterML:                      "Water"
        case .dietaryEnergyKcal:            "Calories eaten"
        case .proteinG:                     "Protein"
        case .carbsG:                       "Carbohydrate"
        case .fatG:                         "Fat"
        case .caffeineMg:                   "Caffeine"
        case .mindfulMinutes:               "Mindful minutes"
        case .daylightMinutes:              "Daylight"
        case .walkingSpeedKmh:              "Walking speed"
        case .walkingStepLengthCm:          "Step length"
        case .walkingAsymmetryPercentage:   "Asymmetry"
        case .doubleSupportPercentage:      "Double support"
        case .walkingSteadinessPercentage:  "Steadiness"
        case .basalBodyTemperatureCelsius:  "Basal temperature"
        case .menstrualFlowLevel:           "Flow"
        }
    }

    /// The suffix shown after the number. Empty where the number speaks for
    /// itself, as a step count does.
    public var unitLabel: String {
        switch self {
        case .steps, .flightsClimbed:                       ""
        case .activeEnergyKcal, .restingEnergyKcal, .dietaryEnergyKcal: "kcal"
        case .exerciseMinutes, .standMinutes, .mindfulMinutes, .daylightMinutes,
             .sleepMinutes, .deepSleepMinutes, .remSleepMinutes,
             .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes:      "min"
        case .distanceKm:                                   "km"
        case .restingHR, .walkingHR, .cardioRecoveryBpm,
             .bloodPressureSystolic, .bloodPressureDiastolic:          "bpm"
        case .hrvMs:                                        "ms"
        case .vo2Max:                                       "ml/kg·min"
        case .weightKg, .leanBodyMassKg:                    "kg"
        case .heightCm, .walkingStepLengthCm:               "cm"
        case .bodyFatPercentage, .spo2Percentage,
             .walkingAsymmetryPercentage, .doubleSupportPercentage,
             .walkingSteadinessPercentage:                  "%"
        case .respiratoryRate:                              "br/min"
        case .wristTemperatureCelsius, .bodyTemperatureCelsius,
             .basalBodyTemperatureCelsius:                  "°C"
        case .bloodGlucoseMgDl:                             "mg/dL"
        case .waterML:                                      "ml"
        case .proteinG, .carbsG, .fatG:                     "g"
        case .caffeineMg:                                   "mg"
        case .walkingSpeedKmh:                              "km/h"
        case .menstrualFlowLevel:                           ""
        }
    }

    /// Decimal places. A step count with a decimal point is noise; a body
    /// temperature without one is useless.
    public var decimals: Int {
        switch self {
        case .distanceKm, .vo2Max, .weightKg, .leanBodyMassKg,
             .walkingSpeedKmh, .spo2Percentage, .bodyFatPercentage,
             .respiratoryRate, .walkingAsymmetryPercentage,
             .doubleSupportPercentage, .walkingSteadinessPercentage:
            1
        case .wristTemperatureCelsius, .bodyTemperatureCelsius,
             .basalBodyTemperatureCelsius:
            2
        default:
            0
        }
    }

    /// Blood pressure only means anything as a pair, and flow is an ordinal
    /// dressed as a number. Both are rendered by hand rather than by the
    /// generic row.
    /// Cycle data is asked for separately, and only when it applies.
    ///
    /// Not because it is more private than a heart rate, but because a
    /// permission sheet that asks every person for menstrual data is telling
    /// most of them the app has misread who they are. It is requested in a
    /// second prompt, after the first, and only when cycle tracking is on.
    public var needsCycleConsent: Bool { group == .cycle }

    /// The metrics read in the first authorisation request: everything that
    /// applies to everyone.
    public static var universal: [HealthMetric] {
        allCases.filter { !$0.needsCycleConsent }
    }

    public static var cycleOnly: [HealthMetric] {
        allCases.filter(\.needsCycleConsent)
    }

    public var rendersAsPlainNumber: Bool {
        self != .menstrualFlowLevel
    }

    public func formatted(_ value: Double) -> String {
        if self == .menstrualFlowLevel {
            return Self.flowTitle(Int(value.rounded()))
        }
        let number = String(format: "%.\(decimals)f", value)
        return unitLabel.isEmpty ? number : "\(number) \(unitLabel)"
    }

    /// HealthKit's menstrual flow is an ordinal, and the raw values are not in
    /// an order anyone would guess: unspecified sits above heavy.
    static func flowTitle(_ level: Int) -> String {
        switch level {
        case 1: "None"
        case 2: "Light"
        case 3: "Medium"
        case 4: "Heavy"
        default: "Recorded"
        }
    }
}
