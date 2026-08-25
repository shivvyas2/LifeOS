import Foundation
import OSLog

private let whoopClientLog = Logger(subsystem: "com.shivvyas.lifeos", category: "whoop-client")

/// Wire shapes for the Whoop developer API.
///
/// Recovery, sleep and cycle are fixture-backed: `WhoopWireFormatTests` holds
/// payloads captured from a live v2 response, so a decode failure in those three
/// means the API moved, not that the app was guessed wrong. Workout is the one
/// collection with no captured fixture yet.
enum WhoopDTOs {
    struct Page<Record: Decodable>: Decodable {
        let records: [Record]
        let next_token: String?
    }

    /// v2 attaches a scoring state to every record. `PENDING_SCORE` and
    /// `UNSCORABLE` carry no usable numbers, and treating them as zero would be
    /// exactly the false zero this app refuses to render.
    static func isScored(_ state: String?) -> Bool {
        state == nil || state == "SCORED"
    }

    struct RecoveryRecord: Decodable {
        let created_at: Date
        let score_state: String?
        let score: Score?

        struct Score: Decodable {
            let recovery_score: Double?
            let resting_heart_rate: Double?
            let hrv_rmssd_milli: Double?
            let spo2_percentage: Double?
            let skin_temp_celsius: Double?
            let user_calibrating: Bool?
        }
    }

    struct SleepRecord: Decodable {
        let id: String?
        let start: Date
        let end: Date
        let nap: Bool?
        let score_state: String?
        let score: Score?

        struct Score: Decodable {
            let sleep_performance_percentage: Double?
            let sleep_consistency_percentage: Double?
            let sleep_efficiency_percentage: Double?
            let respiratory_rate: Double?
            let sleep_needed: Needed?
            let stage_summary: Stages?

            struct Needed: Decodable {
                let baseline_milli: Double?
                let need_from_sleep_debt_milli: Double?
            }

            struct Stages: Decodable {
                let total_in_bed_time_milli: Double?
                let total_awake_time_milli: Double?
                let total_light_sleep_time_milli: Double?
                let total_rem_sleep_time_milli: Double?
                let total_slow_wave_sleep_time_milli: Double?
                let total_no_data_time_milli: Double?
                let sleep_cycle_count: Int?
                let disturbance_count: Int?
            }
        }
    }

    struct CycleRecord: Decodable {
        let id: Int?
        let start: Date
        let score_state: String?
        let score: Score?

        struct Score: Decodable {
            let strain: Double?
            let kilojoule: Double?
            let average_heart_rate: Double?
            let max_heart_rate: Double?
        }
    }

    struct WorkoutRecord: Decodable {
        let id: String?
        let start: Date
        let end: Date
        let sport_name: String?
        let sport_id: Int?
        let score_state: String?
        let score: Score?

        // `zone_durations` is deliberately not decoded. The published sample shows
        // it as an empty object with no documented member names, so there is
        // nothing to decode into. It is still captured in the raw archive, which
        // is exactly the case the archive exists for.
        struct Score: Decodable {
            let strain: Double?
            let kilojoule: Double?
            let average_heart_rate: Double?
            let max_heart_rate: Double?
            let percent_recorded: Double?
            let distance_meter: Double?
            let altitude_gain_meter: Double?
            let altitude_change_meter: Double?
        }
    }

    /// `/v2/user/measurement/body` returns one object, not a paged collection:
    /// there is exactly one of these per user, not one per day.
    struct BodyMeasurement: Decodable {
        let height_meter: Double?
        let weight_kilogram: Double?
        let max_heart_rate: Double?
    }
}

/// One mapping per DTO, shared by the live client and `WhoopDerivation.rederive`.
/// Duplicating this by hand in two places is exactly how `rederive` drifted from
/// `WhoopClient.sleeps()`/`recoveries()` before: fields added to one copy and not
/// the other silently degraded a rebuilt row relative to a synced one.
extension WhoopDTOs.RecoveryRecord {
    var sample: WhoopRecoverySample {
        WhoopRecoverySample(
            date: created_at,
            recoveryPercentage: score?.recovery_score,
            restingHeartRate: score?.resting_heart_rate,
            hrvMilliseconds: score?.hrv_rmssd_milli,
            spo2Percentage: score?.spo2_percentage,
            skinTempCelsius: score?.skin_temp_celsius,
            isCalibrating: score?.user_calibrating
        )
    }
}

extension WhoopDTOs.SleepRecord {
    var sample: WhoopSleepSample {
        let stages = score?.stage_summary
        let need = score?.sleep_needed
        return WhoopSleepSample(
            externalID: id,
            start: start,
            end: end,
            // Naps are returned rather than filtered out. The derivation
            // layer decides what a nap may write; dropping them here meant
            // a real record vanished with no trace.
            isNap: nap == true,
            performancePercentage: score?.sleep_performance_percentage,
            consistencyPercentage: score?.sleep_consistency_percentage,
            efficiencyPercentage: score?.sleep_efficiency_percentage,
            respiratoryRate: score?.respiratory_rate,
            sleepNeedMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.baseline_milli),
            sleepDebtMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.need_from_sleep_debt_milli),
            asleepMinutes: WhoopSleepMath.asleepMinutes(from: stages),
            lightMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_light_sleep_time_milli),
            remMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_rem_sleep_time_milli),
            swsMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_slow_wave_sleep_time_milli),
            awakeMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_awake_time_milli),
            noDataMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_no_data_time_milli),
            sleepCycleCount: stages?.sleep_cycle_count,
            disturbanceCount: stages?.disturbance_count
        )
    }
}

extension WhoopDTOs.CycleRecord {
    var sample: WhoopCycleSample {
        WhoopCycleSample(
            date: start,
            dayStrain: score?.strain,
            // Kilojoules to kilocalories. The divisor is exact.
            calories: score?.kilojoule.map { $0 / 4.184 },
            averageHR: score?.average_heart_rate,
            maxHR: score?.max_heart_rate
        )
    }
}

extension WhoopDTOs.WorkoutRecord {
    var sample: WhoopWorkoutSample? {
        // A workout with no id cannot be upserted, and inserting it anyway would
        // add a duplicate on every sync.
        guard let id else { return nil }
        return WhoopWorkoutSample(
            externalID: id,
            start: start,
            end: end,
            sportName: sport_name ?? "Workout",
            sportID: sport_id,
            strain: score?.strain,
            energyKcal: score?.kilojoule.map { $0 / 4.184 },
            averageHR: score?.average_heart_rate,
            maxHR: score?.max_heart_rate,
            percentRecorded: score?.percent_recorded,
            distanceMeters: score?.distance_meter,
            altitudeGainMeters: score?.altitude_gain_meter,
            altitudeChangeMeters: score?.altitude_change_meter
        )
    }
}

/// Extracted once `rederive` gained a second call site for this DTO: the
/// mapping used to be inlined in `WhoopClient.bodyMeasurement` alone, which
/// was fine while there was exactly one place decoding it. A second place
/// decoding the same DTO is exactly the condition rule 1 exists for.
extension WhoopDTOs.BodyMeasurement {
    var sample: WhoopBodySample {
        WhoopBodySample(
            heightMeters: height_meter,
            weightKilograms: weight_kilogram,
            maxHeartRate: max_heart_rate
        )
    }
}

public struct WhoopClient: Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public init(baseURL: URL = URL(string: "https://api.prod.whoop.com/developer/v2")!) {
            self.baseURL = baseURL
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration = .init(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Whoop timestamps carry milliseconds, as in `2026-08-10T06:16:16.180Z`.
    /// `JSONDecoder.DateDecodingStrategy.iso8601` rejects fractional seconds
    /// outright, so it failed on every record: the sync error was a date parse,
    /// not a missing field. Both forms are accepted because the fractional part
    /// is not guaranteed on every field.
    static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) { return date }
            if let date = plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unrecognised Whoop timestamp: \(text)")
            )
        }
        return decoder
    }()

    public func recoveries(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopRecoverySample] {
        try await recoveriesRaw(accessToken: accessToken, since: since, until: until).samples
    }

    public func sleeps(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopSleepSample] {
        try await sleepsRaw(accessToken: accessToken, since: since, until: until).samples
    }

    public func cycles(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopCycleSample] {
        try await cyclesRaw(accessToken: accessToken, since: since, until: until).samples
    }

    public func workouts(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopWorkoutSample] {
        try await workoutsRaw(accessToken: accessToken, since: since, until: until).samples
    }

    /// `/v2/user/measurement/body` returns a single object, so it does not go
    /// through `get`, which pages a collection over a start/end range. This still
    /// reuses the same status-code handling as every other endpoint.
    ///
    /// Returns the raw bytes alongside the sample, the same shape the `...Raw`
    /// collection methods use, so a sync can archive exactly what arrived
    /// without a second request.
    public func bodyMeasurement(accessToken: String) async throws -> (sample: WhoopBodySample, rawPayload: Data) {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(WhoopCollection.body.path))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhoopAPIError.transport }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw WhoopAPIError.unauthorized
        case 429: throw WhoopAPIError.rateLimited
        default:  throw WhoopAPIError.status(http.statusCode)
        }

        do {
            let body = try WhoopClient.decoder.decode(WhoopDTOs.BodyMeasurement.self, from: data)
            return (body.sample, data)
        } catch {
            throw WhoopAPIError.decoding(String(describing: error))
        }
    }

    /// Returns both the mapped samples and the raw page bytes they came from,
    /// so a sync can archive exactly what arrived at no extra request cost.
    /// Reuses the same `sample` computed property as the plain method above:
    /// there is exactly one DTO-to-sample mapping, not a second copy here.
    public func recoveriesRaw(accessToken: String, since: Date, until: Date = .now)
        async throws -> (samples: [WhoopRecoverySample], rawPages: [Data]) {
        let fetched: Fetched<WhoopDTOs.RecoveryRecord> =
            try await get(WhoopCollection.recovery.path, accessToken: accessToken, since: since, until: until)
        let samples = fetched.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)
        return (samples, fetched.rawPages)
    }

    public func sleepsRaw(accessToken: String, since: Date, until: Date = .now)
        async throws -> (samples: [WhoopSleepSample], rawPages: [Data]) {
        let fetched: Fetched<WhoopDTOs.SleepRecord> =
            try await get(WhoopCollection.sleep.path, accessToken: accessToken, since: since, until: until)
        let samples = fetched.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)
        return (samples, fetched.rawPages)
    }

    public func cyclesRaw(accessToken: String, since: Date, until: Date = .now)
        async throws -> (samples: [WhoopCycleSample], rawPages: [Data]) {
        let fetched: Fetched<WhoopDTOs.CycleRecord> =
            try await get(WhoopCollection.cycle.path, accessToken: accessToken, since: since, until: until)
        let samples = fetched.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)
        return (samples, fetched.rawPages)
    }

    public func workoutsRaw(accessToken: String, since: Date, until: Date = .now)
        async throws -> (samples: [WhoopWorkoutSample], rawPages: [Data]) {
        let fetched: Fetched<WhoopDTOs.WorkoutRecord> =
            try await get(WhoopCollection.workout.path, accessToken: accessToken, since: since, until: until)
        let samples = fetched.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .compactMap(\.sample)
        return (samples, fetched.rawPages)
    }

    /// Whoop returns at most `limit` records per page and a `next_token` for the
    /// rest. The token used to be decoded and dropped, which was invisible while
    /// only daily records were fetched, twenty five being more than fourteen days
    /// of them. Workouts do not fit, and a silent partial sync reads exactly like a
    /// quiet fortnight.
    private static let pageLimit = 25
    /// Bounds a server that keeps handing back a token. Hitting this is logged,
    /// because a silent truncation reads as a complete sync.
    private static let pageCap = 20

    private func get<Record: Decodable>(
        _ path: String, accessToken: String, since: Date, until: Date
    ) async throws -> Fetched<Record> {
        var all: [Record] = []
        var rawPages: [Data] = []
        var nextToken: String?
        var pages = 0

        repeat {
            var components = URLComponents(
                url: configuration.baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )!
            let formatter = ISO8601DateFormatter()
            var items = [
                URLQueryItem(name: "start", value: formatter.string(from: since)),
                URLQueryItem(name: "end", value: formatter.string(from: until)),
                URLQueryItem(name: "limit", value: String(Self.pageLimit)),
            ]
            if let nextToken { items.append(URLQueryItem(name: "nextToken", value: nextToken)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WhoopAPIError.transport }

            switch http.statusCode {
            case 200..<300: break
            case 401: throw WhoopAPIError.unauthorized      // caller refreshes and retries
            case 429: throw WhoopAPIError.rateLimited
            default:  throw WhoopAPIError.status(http.statusCode)
            }

            let page: WhoopDTOs.Page<Record>
            do {
                page = try WhoopClient.decoder.decode(WhoopDTOs.Page<Record>.self, from: data)
            } catch {
                // Distinguished from a transport failure so a field-name drift is
                // obvious rather than looking like a network problem.
                throw WhoopAPIError.decoding(String(describing: error))
            }

            all.append(contentsOf: page.records)
            rawPages.append(data)
            nextToken = page.next_token
            pages += 1

            if pages >= Self.pageCap, nextToken != nil {
                whoopClientLog.error(
                    "\(path, privacy: .public): stopped at the \(Self.pageCap, privacy: .public) page cap with a token still pending; the sync is partial"
                )
                break
            }
        } while nextToken != nil

        return Fetched(records: all, rawPages: rawPages)
    }
}

private struct Fetched<Record: Decodable> {
    let records: [Record]
    let rawPages: [Data]
}

public enum WhoopAPIError: Error, Equatable {
    case transport
    case unauthorized
    case rateLimited
    case status(Int)
    case decoding(String)
}
