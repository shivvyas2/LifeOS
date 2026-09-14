import Testing
import Foundation
@testable import Integrations

final class GroupStubURLProtocol: URLProtocol {
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


@Suite(.serialized) struct GroupAPITests {
    private let group = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let user = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private var token: String {
        let data = try! JSONSerialization.data(withJSONObject: ["sub": user.uuidString])
        return "header." + data.base64EncodedString() + ".signature"
    }
    private func api(_ replies: [GroupStubURLProtocol.Reply]) -> GroupAPI {
        GroupStubURLProtocol.reset(); GroupStubURLProtocol.replies = replies
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupStubURLProtocol.self]
        return GroupAPI(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "test-key", session: URLSession(configuration: config))
    }

    @Test func invitationDecodesAndGroupsAreScopedToCaller() async throws {
        let client = api([.ok("""
        [{"id":"\(group)","name":"Morning crew","description":"Walk together","owner_id":"\(user)",
          "group_members":[{"group_id":"\(group)","user_id":"\(user)","status":"invited","shares_activity":false}]}]
        """)])
        let result = try await client.groups(token: token)
        #expect(result.first?.isInvitation == true)
        #expect(result.first?.members.first?.sharesActivity == false)
        let items = URLComponents(url: try #require(GroupStubURLProtocol.seen.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains(URLQueryItem(name: "group_members.user_id", value: "eq.\(user)")) == true)
    }

    @Test func invalidSessionNeverMakesGroupRequest() async {
        let client = api([])
        do { _ = try await client.groups(token: "invalid"); Issue.record("Expected a session error") }
        catch { #expect(GroupStubURLProtocol.seen.isEmpty) }
    }

    @Test func messagePagesReadNewestFirstAndDisplayChronologically() async throws {
        let clientID = UUID()
        let client = api([.ok("""
        [{"id":8,"group_id":"\(group)","sender":"\(user)","body":"Newer","client_id":"\(clientID)","created_at":"2026-09-14T10:00:00.123Z"},
         {"id":7,"group_id":"\(group)","sender":"\(user)","body":"Older","client_id":"\(UUID())","created_at":"2026-09-14T09:00:00Z"}]
        """)])
        let messages = try await client.messages(group: group, before: 9, token: token)
        #expect(messages.map(\.id) == [7, 8])
        let items = URLComponents(url: try #require(GroupStubURLProtocol.seen.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.contains(URLQueryItem(name: "id", value: "lt.9")) == true)
        #expect(items?.contains(URLQueryItem(name: "order", value: "id.desc")) == true)
        #expect(items?.contains(URLQueryItem(name: "limit", value: "50")) == true)
    }

    @Test func retryPreservesServerIdempotencyKey() async throws {
        let client = api([.ok("42"), .ok("42")])
        let id = UUID()
        let first = try await client.send(group: group, body: "Hello", clientID: id, token: token)
        let second = try await client.send(group: group, body: "Hello", clientID: id, token: token)
        #expect(first == second)
        #expect(GroupStubURLProtocol.seen.count == 2)
        for request in GroupStubURLProtocol.seen {
            #expect(request.body?["p_client_id"] as? String == id.uuidString)
            #expect(request.body?["sender"] == nil)
            #expect(request.url.path.hasSuffix("/rpc/send_group_message"))
        }
    }

    @Test func createCarriesStableIDAndExplicitInvitations() async throws {
        let client = api([.ok("\"\(group)\"")])
        let result = try await client.create(id: group, name: "Crew", description: "Walks", invitees: [user], token: token)
        #expect(result == group)
        let body = try #require(GroupStubURLProtocol.seen.first?.body)
        #expect(body["p_id"] as? String == group.uuidString)
        #expect(body["p_invitees"] as? [String] == [user.uuidString])
        #expect(body["owner_id"] == nil)
    }

    @Test func sharingIsExplicitAndPerGroup() async throws {
        let client = api([.ok("null")])
        try await client.share(group: group, enabled: false, token: token)
        let body = try #require(GroupStubURLProtocol.seen.first?.body)
        #expect(body["p_group"] as? String == group.uuidString)
        #expect(body["p_shares"] as? Bool == false)
    }

    @Test func leaderboardDecodesServerRanksAndFreshness() async throws {
        let client = api([.ok("""
        [{"user_id":"\(user)","display_name":"Alex","avatar_path":null,"score":0,"rank_position":1,"updated_at":"2026-09-14T10:00:00.123456+00:00","source":"appleHealth","day":"2026-09-14"}]
        """)])
        let rows = try await client.leaderboard(group: group, metric: .effort, day: "2026-09-14", token: token)
        #expect(rows.first?.score == 0)
        #expect(rows.first?.position == 1)
        #expect(rows.first?.sourceName == "Apple Health")
        #expect(GroupStubURLProtocol.seen.first?.body?["p_day"] as? String == "2026-09-14")
        #expect(GroupStubURLProtocol.seen.first?.body?["p_metric"] as? String == "effort")
    }

    @Test func wellnessUploadCarriesDaySourceAndNoRawSignals() async throws {
        let client = api([.ok("null")])
        let day = SocialWellnessDay(day: "2026-09-14", effort: 0, recharge: nil, rest: 90,
            effortSource: "appleHealth", rechargeSource: nil, restSource: "fitbit", observedAt: Date(timeIntervalSince1970: 1789387200))
        try await client.publish(.init(streak: 1, daysTracked: 20, workouts: 5, wellness: [day]), token: token)
        let request = try #require(GroupStubURLProtocol.seen.first)
        #expect(request.url.path.hasSuffix("/rpc/publish_group_wellness"))
        let sent = try #require((request.body?["p_days"] as? [[String: Any]])?.first)
        #expect(sent["day"] as? String == "2026-09-14")
        #expect(sent["effort"] as? Int == 0)
        #expect(sent["rest_source"] as? String == "fitbit")
        #expect(sent["hrv"] == nil && sent["restingHR"] == nil && sent["user_id"] == nil)
    }

    @Test func membershipDenialIsNotAnEmptySuccess() async {
        let client = api([.status(403, #"{"message":"Join this group first"}"#)])
        do { _ = try await client.members(group: group, token: token); Issue.record("Expected refusal") }
        catch let error as SocialAPIError { #expect(error == .status(403, message: "Join this group first")) }
        catch { Issue.record("Unexpected error: \(error)") }
    }
}
