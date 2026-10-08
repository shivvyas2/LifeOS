import Testing
import Foundation
@testable import Integrations

final class PlaidStubURLProtocol: URLProtocol {
    enum Reply { case ok(String), status(Int, String), offline }
    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var lastBody: Data?

    static func reset() { replies = []; lastBody = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        let reply = Self.replies.isEmpty ? Reply.status(500, "{}") : Self.replies.removeFirst()
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .ok(let body): send(200, body)
        case .status(let code, let body): send(code, body)
        }
    }

    override func stopLoading() {}

    private func send(_ status: Int, _ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct PlaidClientTests {
    private func makeClient(_ replies: [PlaidStubURLProtocol.Reply],
                            token: String? = "session-token") -> PlaidClient {
        PlaidStubURLProtocol.reset()
        PlaidStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaidStubURLProtocol.self]
        return PlaidClient(
            functionsBase: URL(string: "https://project.supabase.co/functions/v1")!,
            session: URLSession(configuration: configuration),
            accessToken: { token }
        )
    }

    @Test func aLinkTokenComesBackUnwrapped() async throws {
        let client = makeClient([.ok(#"{"link_token":"link-sandbox-abc"}"#)])
        #expect(try await client.createLinkToken() == "link-sandbox-abc")
    }

    @Test func aCardSessionAsksTheFunctionForCards() async throws {
        let client = makeClient([.ok(#"{"link_token":"link-sandbox-abc"}"#)])
        _ = try await client.createLinkToken(for: .creditCard)

        let body = try #require(PlaidStubURLProtocol.lastBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["kind"] as? String == "credit_card")
    }

    @Test func aBankSessionIsTheDefault() async throws {
        let client = makeClient([.ok(#"{"link_token":"link-sandbox-abc"}"#)])
        _ = try await client.createLinkToken()

        let body = try #require(PlaidStubURLProtocol.lastBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["kind"] as? String == "bank")
    }

    @Test func anExpiredBankLoginIsItsOwnErrorNotAGenericFailure() async throws {
        // The app has to tell "sign in again" apart from "try again later".
        // Collapsed into one error, the reconnect banner can never appear.
        let client = makeClient([.status(502, #"{"error":"item_login_required"}"#)])
        await #expect(throws: PlaidClientError.itemLoginRequired) {
            _ = try await client.sync(cursors: [:])
        }
    }

    @Test func connectingTheSameBankTwiceIsItsOwnError() async throws {
        let client = makeClient([.status(409, #"{"error":"institution_already_connected"}"#)])
        await #expect(throws: PlaidClientError.institutionAlreadyConnected) {
            _ = try await client.exchange(publicToken: "public-abc",
                                          institutionID: "ins_1", institutionName: "Chase")
        }
    }

    @Test func aMissingSessionNeverReachesTheNetwork() async throws {
        // Signed out, there is no user to scope a credential to. Failing here
        // rather than sending an unauthenticated request keeps the reason clear.
        let client = makeClient([.ok("{}")], token: nil)
        await #expect(throws: PlaidClientError.unauthorized) {
            _ = try await client.createLinkToken()
        }
        #expect(PlaidStubURLProtocol.lastBody == nil)
    }

    @Test func syncSendsTheCursorsItWasGiven() async throws {
        let client = makeClient([.ok(#"{"items":[]}"#)])
        _ = try await client.sync(cursors: ["item_a": "cursor_a"])

        let body = try #require(PlaidStubURLProtocol.lastBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let cursors = try #require(decoded?["cursors"] as? [String: String])
        #expect(cursors == ["item_a": "cursor_a"])
    }

    @Test func disconnectSucceedsOnTheStatusAloneWhateverTheBodySays() async throws {
        // The status is the outcome. Reading a field out of the body would let a
        // disconnect that actually worked be reported as a failure, and disconnect
        // is what stops an item billing every month.
        let client = makeClient([.ok("{}")])
        try await client.disconnect(itemID: "item_a")

        let body = try #require(PlaidStubURLProtocol.lastBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["item_id"] as? String == "item_a")
    }

    @Test func disconnectStillSurfacesARealFailure() async throws {
        let client = makeClient([.status(502, #"{"error":"upstream_failure"}"#)])
        await #expect(throws: PlaidClientError.upstream(502)) {
            try await client.disconnect(itemID: "item_a")
        }
    }
}
