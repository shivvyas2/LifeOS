import Foundation

/// PostgREST over `URLSession`.
///
/// The same reasoning as `SupabaseAuth`: the calls this app makes against the
/// database are an upsert and a filtered select, and the official client would
/// pull in a great deal more surface than that to provide them.
///
/// Every request carries the user's access token, never the anon key alone, so
/// Row Level Security resolves `auth.uid()` to a real user. A call made with
/// only the anon key would authenticate as nobody and quietly return zero rows,
/// which is the worst possible failure: it looks exactly like an empty account.
public struct SupabaseREST: Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    public enum RESTError: Error, Equatable {
        case transport
        case server(status: Int, message: String)
        case encoding
    }

    /// Inserts or replaces rows, keyed on the primary key.
    ///
    /// `resolution=merge-duplicates` is what makes a push idempotent: a client
    /// that pushed, lost the response and retried must not create a second copy
    /// of every page it owns.
    ///
    /// Takes bytes rather than a dictionary because a `[String: Any]` is not
    /// `Sendable` and this call crosses an isolation boundary. Serialising in
    /// the caller, where the rows were built, is the honest fix; the
    /// alternative is a Sendable-shaped JSON type that exists only to be
    /// converted back into the same bytes.
    public func upsert(table: String, body: Data, accessToken: String) async throws {
        guard !body.isEmpty else { return }

        var request = try authorized(path: "rest/v1/\(table)", accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        _ = try await perform(request)
    }

    /// Serialises rows for `upsert`. Static so the caller can do it on its own
    /// actor before handing over the bytes.
    public static func encode(_ rows: [[String: Any]]) throws -> Data {
        guard !rows.isEmpty else { return Data() }
        guard JSONSerialization.isValidJSONObject(rows) else { throw RESTError.encoding }
        return try JSONSerialization.data(withJSONObject: rows)
    }

    /// Parses what `fetch` returned. Same reasoning in reverse: the bytes cross
    /// the boundary, the dictionaries do not.
    public static func decode(_ data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Rows changed at or after `since`, oldest first.
    ///
    /// Ordered by `updated_at` rather than by id so a pull that is interrupted
    /// halfway can resume from the last row it actually stored, and inclusive
    /// of the cursor instant so a row written in the same millisecond as the
    /// previous page's last row is not skipped. Re-reading one row is free;
    /// missing one is silent data loss.
    public func fetch(
        table: String,
        since: Date?,
        accessToken: String,
        limit: Int = 500
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let since {
            query.append(URLQueryItem(name: "updated_at", value: "gte.\(SupabaseREST.timestamp(since))"))
        }
        components?.queryItems = query

        guard let url = components?.url else { throw RESTError.encoding }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        return try await perform(request)
    }

    private func authorized(path: String, accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RESTError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw RESTError.transport }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let message = (json["message"] as? String)
                ?? (json["hint"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw RESTError.server(status: http.statusCode, message: message)
        }
        return data
    }

    /// PostgREST wants ISO 8601 with fractional seconds. Formatting is stated
    /// here once because a cursor formatted two different ways in two call
    /// sites is a bug that only shows up under a millisecond of clock skew.
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public static func date(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }

        // Postgres renders `timestamptz` without a T when the client asks for
        // it, and a bare `date` column has no time at all. Both reach here.
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd HH:mm:ssZZZZZ", "yyyy-MM-dd"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: string) { return date }
        }
        return nil
    }

    /// A calendar day, for `date` columns. Sent without a time so the server
    /// cannot shift it into the neighbouring day.
    ///
    /// Formatted in the device's own timezone, not UTC. A journal entry's date
    /// is a local midnight; rendering that in UTC would file every entry
    /// written east of Greenwich under the previous day.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        dayFormatter(timeZone).string(from: date)
    }

    /// The inverse, landing on local midnight for the same reason.
    public static func day(from string: String, timeZone: TimeZone = .current) -> Date? {
        dayFormatter(timeZone).date(from: string)
    }

    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
