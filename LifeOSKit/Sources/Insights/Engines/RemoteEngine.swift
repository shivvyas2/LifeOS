import Foundation

/// What the cloud tier can fail with.
///
/// Separate from `AuthError` and from the router's own vocabulary, because two
/// of these mean something the UI has to say differently: a spent budget is
/// not a broken connection, and a refusal is not a failure at all.
public enum RemoteEngineError: Error, Equatable {
    /// The day's token allowance is gone. Retrying will not help until
    /// tomorrow, so the UI must not offer a retry.
    case exhausted
    /// The model declined, with its own words. Not an error to retry either.
    case refused(String)
    /// Transient: no network, a timeout, an upstream fault. Retry is right.
    case unavailable
    /// No session, so there is no one to bill or to answer about. A guest.
    case notSignedIn
    /// A task with no server-side name was sent to the cloud. A programmer
    /// error rather than anything a user did.
    case unsupportedTask
}

/// The wire format, kept out of the engine so every decision it makes is
/// testable without a network. The engine below is transport and nothing else.
public enum RemoteWire {

    public static func request(
        baseURL: URL, anonKey: String, accessToken: String,
        taskName: String, prompt: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/lifo-agent"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        // Both are required and they are not the same thing: the apikey admits
        // the app to the project, the bearer token says which user is asking.
        // The function bills and answers the second one.
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "task": taskName, "prompt": prompt,
        ])
        return request
    }

    /// Hoisted out of `result` rather than nested inside it: Swift does not
    /// allow a type declaration inside a generic function.
    private struct Reply<T: Decodable>: Decodable { let output: T }
    fileprivate struct Failure: Decodable {
        let error: String
        let message: String?
    }

    /// The error a response describes, or nil when it describes success.
    ///
    /// Shared with the chat path rather than copied into it. Two mappings
    /// that are meant to agree and are written twice do not stay agreeing:
    /// the day someone adds a status here, the other one is silently a
    /// version behind.
    public static func failure(data: Data, status: Int) -> RemoteEngineError? {
        guard !(200..<300).contains(status) else { return nil }
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        switch (status, failure?.error) {
        case (429, _), (_, "exhausted"):
            return .exhausted
        case (403, _), (_, "refused"):
            return .refused(failure?.message ?? "LIFO declined that one.")
        default:
            return .unavailable
        }
    }

    /// Decodes a reply, or throws the error the status describes.
    ///
    /// Status first, body second. A 429 is the budget whatever the body says,
    /// and a body that fails to parse on a failure response must still produce
    /// the right error rather than collapsing into "unavailable".
    public static func result<Output: Decodable>(data: Data, status: Int) throws -> Output {
        if let error = failure(data: data, status: status) { throw error }
        do {
            return try JSONDecoder().decode(Reply<Output>.self, from: data).output
        } catch {
            // A 200 whose body does not fit the shape is the server being
            // wrong, which the user can do nothing about and a retry might
            // fix. It is never surfaced as a refusal.
            throw RemoteEngineError.unavailable
        }
    }
}

/// The cloud tier.
///
/// Sends the off-device render of a task to the `lifo-agent` Edge Function and
/// decodes the structured reply. It holds no key: the function does, and the
/// only credential that travels from here is the user's own session token.
public struct RemoteEngine: Engine {
    private let baseURL: URL
    private let anonKey: String
    private let accessToken: @Sendable () -> String?
    private let session: URLSession

    /// `accessToken` is a closure rather than a value because the session is
    /// refreshed while the app runs, and an engine built at launch holding a
    /// copy would present an hour-old token for the rest of the process.
    public init(baseURL: URL, anonKey: String,
                accessToken: @escaping @Sendable () -> String?,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.session = session
    }

    public func run<T: CoachTask>(_ task: T, _ context: T.Context) async throws -> T.Output {
        guard let name = task.remoteName else { throw RemoteEngineError.unsupportedTask }
        guard let token = accessToken(), !token.isEmpty else { throw RemoteEngineError.notSignedIn }

        // `.offDevice` is the whole point of the audience parameter: the
        // on-device render carries raw Whoop series, and this is the method
        // that would put them on the wire.
        let request = try RemoteWire.request(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            taskName: name, prompt: task.prompt(context, for: .offDevice)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Offline, DNS, timeout. Transient by nature, and the router turns
            // this into the state that offers a retry.
            throw RemoteEngineError.unavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try RemoteWire.result(data: data, status: status)
    }
}
