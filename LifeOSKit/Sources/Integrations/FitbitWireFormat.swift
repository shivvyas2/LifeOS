import Foundation

/// Decoding for each Fitbit collection.
///
/// Every numeric field is optional. A Fitbit response omits what a device did
/// not record, and a non-optional field turns one missing number into a whole
/// failed range, which on screen is indistinguishable from a person having no
/// data at all.

// MARK: - Sleep

public struct FitbitSleepPayload: Decodable, Sendable, Equatable {
    public struct Night: Decodable, Sendable, Equatable {
        public let dateOfSleep: String
        public let efficiency: Double?
        public let minutesAsleep: Double?
        public let minutesAwake: Double?
        public let timeInBed: Double?
        public let type: String?
        /// Absent on a classic log, which has no stages at all. One unstaged
        /// night must not take the whole range down with it.
        public let levels: Levels?
    }
    public struct Levels: Decodable, Sendable, Equatable {
        public let summary: Summary
    }
    public struct Summary: Decodable, Sendable, Equatable {
        public let deep: Stage?
        public let light: Stage?
        public let rem: Stage?
        public let wake: Stage?
    }
    public struct Stage: Decodable, Sendable, Equatable {
        public let count: Int?
        public let minutes: Double?
    }
    public let sleep: [Night]
}

// MARK: - Interval collections

public struct FitbitHRVPayload: Decodable, Sendable, Equatable {
    public struct Day: Decodable, Sendable, Equatable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable, Equatable {
        public let dailyRmssd: Double?
        public let deepRmssd: Double?
    }
    public let hrv: [Day]
}

/// SpO2 by interval is a bare array, not an envelope. Fitbit is not consistent
/// about this across collections, and a wrapper struct here decodes to nothing
/// without raising anything.
public typealias FitbitSpO2Payload = [FitbitSpO2Day]

public struct FitbitSpO2Day: Decodable, Sendable, Equatable {
    public struct Value: Decodable, Sendable, Equatable {
        public let avg: Double?
        public let min: Double?
        public let max: Double?
    }
    public let dateTime: String
    public let value: Value
}

public struct FitbitBreathingPayload: Decodable, Sendable, Equatable {
    public struct Day: Decodable, Sendable, Equatable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable, Equatable {
        public let breathingRate: Double?
    }
    public let br: [Day]
}

public struct FitbitTemperaturePayload: Decodable, Sendable, Equatable {
    public struct Day: Decodable, Sendable, Equatable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable, Equatable {
        /// Fitbit reports skin temperature as a nightly *variation* from the
        /// user's own baseline, not an absolute reading. It is deliberately
        /// not mapped onto a body temperature, which it is not.
        public let nightlyRelative: Double?
    }
    public let tempSkin: [Day]
}

public struct FitbitHeartPayload: Decodable, Sendable, Equatable {
    public struct Day: Decodable, Sendable, Equatable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable, Equatable {
        public let restingHeartRate: Double?
    }
    /// The wire name is `activities-heart`, which is not a Swift identifier.
    public let days: [Day]

    private enum CodingKeys: String, CodingKey {
        case days = "activities-heart"
    }
}

public struct FitbitCardioPayload: Decodable, Sendable, Equatable {
    public struct Day: Decodable, Sendable, Equatable {
        public let dateTime: String
        public let value: Value
    }
    public struct Value: Decodable, Sendable, Equatable {
        /// Either a single number or a range like "40-44", depending on
        /// whether the user ran with GPS. Kept as the string it arrives as;
        /// the derivation takes the midpoint of a range.
        public let vo2Max: String?
    }
    public let cardioScore: [Day]
}

// MARK: - The whole response

/// One sync's worth of raw collections.
///
/// Every field optional: a collection refused for a declined scope is simply
/// absent, and the other six still land.
public struct FitbitPayloads: Decodable, Sendable, Equatable {
    public var sleep: FitbitSleepPayload?
    public var hrv: FitbitHRVPayload?
    public var spo2: FitbitSpO2Payload?
    public var breathing: FitbitBreathingPayload?
    public var skinTemperature: FitbitTemperaturePayload?
    public var restingHeartRate: FitbitHeartPayload?
    public var cardioFitness: FitbitCardioPayload?

    public init(
        sleep: FitbitSleepPayload? = nil, hrv: FitbitHRVPayload? = nil,
        spo2: FitbitSpO2Payload? = nil, breathing: FitbitBreathingPayload? = nil,
        skinTemperature: FitbitTemperaturePayload? = nil,
        restingHeartRate: FitbitHeartPayload? = nil,
        cardioFitness: FitbitCardioPayload? = nil
    ) {
        self.sleep = sleep
        self.hrv = hrv
        self.spo2 = spo2
        self.breathing = breathing
        self.skinTemperature = skinTemperature
        self.restingHeartRate = restingHeartRate
        self.cardioFitness = cardioFitness
    }
}

/// One day's worth of Fitbit readings, ready to merge.
public struct FitbitDay: Sendable, Equatable {
    public let date: Date
    public let values: [HealthMetric: Double]

    public init(date: Date, values: [HealthMetric: Double]) {
        self.date = date
        self.values = values
    }
}

/// The collections pulled by range.
///
/// Per-date collections (the activity summary, nutrition) are deliberately
/// absent: they cost one request per day against a quota of 150 per hour, so
/// they arrive with the resumable cursor rather than here.
public enum FitbitCollection: String, CaseIterable, Sendable {
    case sleep, hrv, spo2, breathing, skinTemperature, restingHeartRate, cardioFitness

    /// Fitbit's own cap. Exceeding it is a 400 that names nothing useful.
    public var maximumRangeDays: Int {
        switch self {
        case .sleep: 100
        case .restingHeartRate: 365
        case .hrv, .spo2, .breathing, .skinTemperature, .cardioFitness: 30
        }
    }
}
