import Foundation

/// Wire shapes for the Whoop developer API.
///
/// **These field names are the one unverified part of this integration.** They
/// follow the documented v2 shape, but nothing here has been exercised against
/// a live token, so treat a decode failure as "the API moved", not "the app is
/// broken". Everything downstream works on `WhoopRecoverySample` and friends,
/// so a correction is confined to this file.
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
        }
    }

    struct SleepRecord: Decodable {
        let start: Date
        let end: Date
        let nap: Bool?
        let score_state: String?
        let score: Score?

        struct Score: Decodable {
            let sleep_performance_percentage: Double?
            let stage_summary: Stages?

            struct Stages: Decodable {
                let total_in_bed_time_milli: Double?
                let total_awake_time_milli: Double?
            }
        }
    }

    struct CycleRecord: Decodable {
        let start: Date
        let score_state: String?
        let score: Score?

        struct Score: Decodable {
            let strain: Double?
        }
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

    /// Whoop timestamps carry milliseconds — `2026-08-10T06:16:16.180Z`.
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
        let page: WhoopDTOs.Page<WhoopDTOs.RecoveryRecord> =
            try await get("recovery", accessToken: accessToken, since: since, until: until)
        return page.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map {
                WhoopRecoverySample(
                    date: $0.created_at,
                    recoveryPercentage: $0.score?.recovery_score,
                    restingHeartRate: $0.score?.resting_heart_rate,
                    hrvMilliseconds: $0.score?.hrv_rmssd_milli
                )
            }
    }

    public func sleeps(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopSleepSample] {
        let page: WhoopDTOs.Page<WhoopDTOs.SleepRecord> =
            try await get("activity/sleep", accessToken: accessToken, since: since, until: until)
        return page.records
            // Naps are not the night's sleep and must not overwrite it.
            .filter { $0.nap != true && WhoopDTOs.isScored($0.score_state) }
            .map { record in
                let inBed = record.score?.stage_summary?.total_in_bed_time_milli ?? 0
                let awake = record.score?.stage_summary?.total_awake_time_milli ?? 0
                let asleep = max(inBed - awake, 0)
                return WhoopSleepSample(
                    start: record.start,
                    end: record.end,
                    performancePercentage: record.score?.sleep_performance_percentage,
                    asleepMinutes: asleep > 0 ? Int(asleep / 60_000) : nil
                )
            }
    }

    public func cycles(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopCycleSample] {
        let page: WhoopDTOs.Page<WhoopDTOs.CycleRecord> =
            try await get("cycle", accessToken: accessToken, since: since, until: until)
        return page.records
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map { WhoopCycleSample(date: $0.start, dayStrain: $0.score?.strain) }
    }

    private func get<T: Decodable>(
        _ path: String, accessToken: String, since: Date, until: Date
    ) async throws -> T {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        let formatter = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "start", value: formatter.string(from: since)),
            URLQueryItem(name: "end", value: formatter.string(from: until)),
            URLQueryItem(name: "limit", value: "25"),
        ]

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

        do {
            return try WhoopClient.decoder.decode(T.self, from: data)
        } catch {
            // Distinguished from a transport failure so a field-name drift is
            // obvious rather than looking like a network problem.
            throw WhoopAPIError.decoding(String(describing: error))
        }
    }
}

public enum WhoopAPIError: Error, Equatable {
    case transport
    case unauthorized
    case rateLimited
    case status(Int)
    case decoding(String)
}
