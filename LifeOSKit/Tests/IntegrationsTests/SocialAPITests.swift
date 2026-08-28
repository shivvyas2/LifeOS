import Testing
import Foundation
@testable import Integrations

/// Records every request it sees and answers with the next queued reply, so
/// tests can both assert on what was sent and script multi-call sequences
/// (the reverse-direction guard in `request(from:to:)` makes two calls).
final class SocialStubURLProtocol: URLProtocol {
    struct Seen { let method: String; let url: URL; let body: [String: Any]? }
    enum Reply { case ok(String), status(Int, String) }

    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var seen: [Seen] = []

    static func reset() { replies = []; seen = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
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
        let bodyJSON = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        Self.seen.append(Seen(method: request.httpMethod ?? "GET", url: request.url!, body: bodyJSON))

        let reply = Self.replies.isEmpty ? Reply.status(500, "{}") : Self.replies.removeFirst()
        switch reply {
        case .ok(let body): send(200, body)
        case .status(let code, let body): send(code, body)
        }
    }

    override func stopLoading() {}

    private func send(_ status: Int, _ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct SocialAPITests {
    private let baseURL = URL(string: "https://project.supabase.co")!
    private let anonKey = "anon-key"

    private func makeAPI(_ replies: [SocialStubURLProtocol.Reply]) -> SocialAPI {
        SocialStubURLProtocol.reset()
        SocialStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SocialStubURLProtocol.self]
        return SocialAPI(baseURL: baseURL, anonKey: anonKey, session: URLSession(configuration: configuration))
    }

    // A JWT with a real "sub" claim, header and signature are irrelevant here.
    private func accessToken(subject: UUID) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["sub": subject.uuidString])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    // MARK: - Decoding

    @Test func aProfileDecodesFromSnakeCaseJSON() throws {
        let userID = UUID()
        let json = #"{"user_id":"\#(userID.uuidString)","display_name":"Ada Lovelace"}"#
        let profile = try JSONDecoder().decode(SocialProfile.self, from: Data(json.utf8))
        #expect(profile.userID == userID)
        #expect(profile.displayName == "Ada Lovelace")
        #expect(profile.id == userID)
    }

    @Test func aFriendshipDecodesFromRealisticJSON() throws {
        let requester = UUID()
        let addressee = UUID()
        let json = """
        {"id": 42, "requester": "\(requester.uuidString)", "addressee": "\(addressee.uuidString)", "status": "pending"}
        """
        let friendship = try JSONDecoder().decode(Friendship.self, from: Data(json.utf8))
        #expect(friendship.id == 42)
        #expect(friendship.requester == requester)
        #expect(friendship.addressee == addressee)
        #expect(friendship.status == .pending)
    }

    @Test func aMessageDecodesFractionalSecondTimestamps() async throws {
        let sender = UUID()
        let recipient = UUID()
        let json = """
        {"id": 7, "sender": "\(sender.uuidString)", "recipient": "\(recipient.uuidString)",
         "body": "hey", "created_at": "2026-08-27T12:34:56.789012+00:00"}
        """
        let api = makeAPI([.ok("[\(json)]")])
        let messages = try await api.messages(with: recipient, accessToken: accessToken(subject: sender))
        let message = try #require(messages.first)
        #expect(message.id == 7)
        #expect(message.sender == sender)
        #expect(message.recipient == recipient)
        #expect(message.body == "hey")

        var expectedComponents = DateComponents()
        expectedComponents.year = 2026; expectedComponents.month = 8; expectedComponents.day = 27
        expectedComponents.hour = 12; expectedComponents.minute = 34; expectedComponents.second = 56
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let expected = calendar.date(from: expectedComponents)!
        #expect(abs(message.createdAt.timeIntervalSince(expected)) < 1)
    }

    // MARK: - URL construction

    @Test func searchEscapesWildcardCharactersOutOfTheQuery() {
        let request = SocialAPI.searchRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: "tok", query: "50% off * sale"
        )
        let query = request.url?.query ?? ""
        #expect(query.contains("display_name=ilike.*50%5C%25%20off%20%5C*%20sale*"))
    }

    @Test func searchSendsTheRequiredHeadersAndLimit() {
        let request = SocialAPI.searchRequest(baseURL: baseURL, anonKey: anonKey, accessToken: "tok", query: "ada")
        #expect(request.value(forHTTPHeaderField: "apikey") == anonKey)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.url?.path == "/rest/v1/profiles")
        #expect(request.url?.query?.contains("limit=20") == true)
    }

    @Test func profilesRequestFiltersByAnInList() {
        let a = UUID()
        let b = UUID()
        let request = SocialAPI.profilesRequest(baseURL: baseURL, anonKey: anonKey, accessToken: "tok", ids: [a, b])
        let query = request.url?.query ?? ""
        #expect(query.contains("user_id=in.(\(a.uuidString),\(b.uuidString))"))
    }

    @Test func messagesRequestFiltersByEitherPartyOrderedOldestFirst() {
        let them = UUID()
        let request = SocialAPI.messagesRequest(baseURL: baseURL, anonKey: anonKey, accessToken: "tok", userID: them)
        let query = request.url?.query ?? ""
        #expect(query.contains("or=(sender.eq.\(them.uuidString),recipient.eq.\(them.uuidString))"))
        #expect(query.contains("order=created_at.asc"))
        #expect(query.contains("limit=200"))
    }

    @Test func upsertMyProfileSendsMergeDuplicatesAndTheGivenFields() throws {
        let userID = UUID()
        let request = try SocialAPI.upsertProfileRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: "tok", userID: userID, displayName: "Ada"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["user_id"] as? String == userID.uuidString)
        #expect(json?["display_name"] as? String == "Ada")
    }

    @Test func acceptSendsOnlyTheStatusColumn() throws {
        let request = try SocialAPI.acceptFriendshipRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: "tok", friendshipID: 9
        )
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.query == "id=eq.9")
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?.count == 1)
        #expect(json?["status"] as? String == "accepted")
    }

    @Test func removeSendsADeleteScopedToTheID() {
        let request = SocialAPI.removeFriendshipRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: "tok", friendshipID: 3
        )
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.query == "id=eq.3")
    }

    // MARK: - Error mapping

    @Test func aNonSuccessStatusMapsToSocialAPIErrorStatus() async throws {
        let api = makeAPI([.status(403, "{}")])
        await #expect(throws: SocialAPIError.status(403, message: "")) {
            _ = try await api.friendships(accessToken: "tok")
        }
    }

    /// PostgREST says why it refused, in a `message` field. Throwing away that
    /// sentence is what turns every failure into an indistinguishable "Search
    /// failed": an expired token, a missing grant and a malformed filter all
    /// look identical from the outside, and none can be diagnosed from a
    /// screenshot.
    @Test func aRefusalCarriesTheReasonTheServerGave() async throws {
        let body = #"{"message":"JWT expired","code":"PGRST301"}"#
        let api = makeAPI([.status(401, body)])

        await #expect(throws: SocialAPIError.status(401, message: "JWT expired")) {
            _ = try await api.search("ada", accessToken: "tok")
        }
    }

    /// A body that is not the shape we expect must not lose the status code
    /// as well. HTML from a proxy is the common case.
    @Test func aRefusalWithNoParsableBodyStillCarriesItsStatus() async throws {
        let api = makeAPI([.status(502, "<html>bad gateway</html>")])

        await #expect(throws: SocialAPIError.status(502, message: "")) {
            _ = try await api.search("ada", accessToken: "tok")
        }
    }

    // MARK: - Reverse-direction guard

    @Test func requestingAFriendshipInsertsWhenNoRowLinksThePairYet() async throws {
        let me = UUID()
        let them = UUID()
        let api = makeAPI([.ok("[]"), .ok("{}")])
        try await api.request(from: me, to: them, accessToken: accessToken(subject: me))

        #expect(SocialStubURLProtocol.seen.count == 2)
        let insert = SocialStubURLProtocol.seen[1]
        #expect(insert.method == "POST")
        #expect(insert.body?["requester"] as? String == me.uuidString)
        #expect(insert.body?["addressee"] as? String == them.uuidString)
        #expect(insert.body?["status"] as? String == "pending")
    }

    @Test func requestingAFriendshipTheOtherPersonAlreadySentIsANoOp() async throws {
        let me = UUID()
        let them = UUID()
        let existing = """
        [{"id": 1, "requester": "\(them.uuidString)", "addressee": "\(me.uuidString)", "status": "pending"}]
        """
        let api = makeAPI([.ok(existing)])
        try await api.request(from: me, to: them, accessToken: accessToken(subject: me))

        // Only the friendships fetch happened; no insert was ever sent.
        #expect(SocialStubURLProtocol.seen.count == 1)
        #expect(SocialStubURLProtocol.seen[0].method == "GET")
    }

    @Test func requestingAFriendshipAlreadySentBySelfIsANoOp() async throws {
        let me = UUID()
        let them = UUID()
        let existing = """
        [{"id": 1, "requester": "\(me.uuidString)", "addressee": "\(them.uuidString)", "status": "pending"}]
        """
        let api = makeAPI([.ok(existing)])
        try await api.request(from: me, to: them, accessToken: accessToken(subject: me))

        #expect(SocialStubURLProtocol.seen.count == 1)
    }

    // MARK: - send() derives the sender from the access token

    @Test func sendDerivesTheSenderFromTheAccessTokenSubject() async throws {
        let me = UUID()
        let them = UUID()
        let api = makeAPI([.ok("{}")])
        try await api.send("hey there", to: them, accessToken: accessToken(subject: me))

        let sent = try #require(SocialStubURLProtocol.seen.first)
        #expect(sent.method == "POST")
        #expect(sent.body?["sender"] as? String == me.uuidString)
        #expect(sent.body?["recipient"] as? String == them.uuidString)
        #expect(sent.body?["body"] as? String == "hey there")
    }

    @Test func sendWithAnUnreadableTokenFailsBeforeReachingTheNetwork() async throws {
        let api = makeAPI([.ok("{}")])
        await #expect(throws: SocialAPIError.status(401, message: "The access token carries no subject claim")) {
            try await api.send("hey", to: UUID(), accessToken: "not-a-jwt")
        }
        #expect(SocialStubURLProtocol.seen.isEmpty)
    }
}
