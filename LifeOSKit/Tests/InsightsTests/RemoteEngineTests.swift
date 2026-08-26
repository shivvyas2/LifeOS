import Foundation
import Testing
@testable import Insights

@Suite struct RemoteWireTests {

    private let base = URL(string: "https://example.supabase.co")!

    @Test func theRequestCarriesTheTaskThePromptAndBothCredentials() throws {
        let request = try RemoteWire.request(
            baseURL: base, anonKey: "anon-key", accessToken: "jwt-token",
            taskName: "answer", prompt: "Question: how did I sleep?"
        )
        #expect(request.url?.path.hasSuffix("/functions/v1/lifo-agent") == true)
        #expect(request.httpMethod == "POST")
        // The two credentials do different jobs and both are required: the
        // apikey admits the app, the bearer says who is asking.
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")

        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody))
        let fields = try #require(body as? [String: String])
        #expect(fields == ["task": "answer", "prompt": "Question: how did I sleep?"])
    }

    @Test func aGoodReplyDecodesIntoTheOutputType() throws {
        let data = Data(#"{"output":{"answer":"Seven hours."},"tokens":300}"#.utf8)
        let answer: CoachAnswer = try RemoteWire.result(data: data, status: 200)
        #expect(answer.answer == "Seven hours.")
    }

    /// A spent budget is not a broken connection. It has its own case so the
    /// UI can decline to offer a retry that cannot succeed until tomorrow.
    @Test func aSpentBudgetIsItsOwnError() {
        let data = Data(#"{"error":"exhausted"}"#.utf8)
        #expect(throws: RemoteEngineError.exhausted) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 429)
        }
    }

    /// A refusal carries the model's own words through to the screen, because
    /// "LIFO declined" without a reason invites the same question again.
    @Test func aRefusalKeepsItsMessage() {
        let data = Data(#"{"error":"refused","message":"That is outside what I cover."}"#.utf8)
        #expect(throws: RemoteEngineError.refused("That is outside what I cover.")) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 403)
        }
    }

    @Test func aRefusalWithNoMessageStillReadsAsOne() {
        let data = Data(#"{"error":"refused"}"#.utf8)
        #expect(throws: RemoteEngineError.refused("LIFO declined that one.")) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 403)
        }
    }

    @Test func anUpstreamFailureIsUnavailable() {
        let data = Data(#"{"error":"upstream_failure"}"#.utf8)
        #expect(throws: RemoteEngineError.unavailable) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 502)
        }
    }

    /// The status decides even when the body is unreadable. A failure whose
    /// body does not parse must not fall through to a success path.
    @Test func aFailureWithAnUnreadableBodyStillFails() {
        let data = Data("<html>gateway timeout</html>".utf8)
        #expect(throws: RemoteEngineError.exhausted) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 429)
        }
        #expect(throws: RemoteEngineError.unavailable) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 500)
        }
    }

    /// A 200 whose body is the wrong shape is the server being wrong. The user
    /// can do nothing about it and a retry might fix it, so it is never
    /// surfaced as a refusal.
    @Test func aWellFormedButWrongShapedSuccessIsUnavailable() {
        let data = Data(#"{"unexpected":true}"#.utf8)
        #expect(throws: RemoteEngineError.unavailable) {
            let _: CoachAnswer = try RemoteWire.result(data: data, status: 200)
        }
    }
}

@Suite struct RemoteEngineTests {

    private let base = URL(string: "https://example.supabase.co")!

    /// A guest has no session, so there is nobody to bill and nobody to answer
    /// about. It fails before any request is built.
    @Test func aSignedOutUserNeverReachesTheNetwork() async {
        let engine = RemoteEngine(baseURL: base, anonKey: "anon", accessToken: { nil })
        await #expect(throws: RemoteEngineError.notSignedIn) {
            _ = try await engine.run(AnswerTask(question: "hi"), ContextBundle(digest: .empty))
        }
    }

    @Test func anEmptyTokenCountsAsSignedOut() async {
        let engine = RemoteEngine(baseURL: base, anonKey: "anon", accessToken: { "" })
        await #expect(throws: RemoteEngineError.notSignedIn) {
            _ = try await engine.run(AnswerTask(question: "hi"), ContextBundle(digest: .empty))
        }
    }

    /// A task with no server-side name has no model behind it. Sending one is
    /// a programmer error, and it must not reach the wire.
    @Test func aDeviceOnlyTaskIsRefusedBeforeTheWire() async {
        let engine = RemoteEngine(baseURL: base, anonKey: "anon", accessToken: { "token" })
        await #expect(throws: RemoteEngineError.unsupportedTask) {
            _ = try await engine.run(BriefTask(), MetricsDigest.empty)
        }
    }
}

private extension MetricsDigest {
    static var empty: MetricsDigest {
        MetricsDigest(
            days: [],
            averages: MetricsDigest.Averages(
                recoveryPct: nil, sleepMinutes: nil, steps: nil,
                hrvMs: nil, restingHR: nil, strain: nil, sleepDebtMinutes: nil
            )
        )
    }
}
