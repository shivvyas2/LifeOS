import Testing
import Foundation
@testable import Integrations

@Suite(.serialized) struct SharedStatsClientTests {
    private let baseURL = URL(string: "https://project.supabase.co")!
    private let anonKey = "anon-key"
    private let token = "access-token"

    private func body(of request: URLRequest) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [[String: Any]] ?? []
    }

    // MARK: - Push

    @Test func sharingOnSendsTheFigures() throws {
        let userID = UUID()
        let request = try SharedStatsClient.pushRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            stats: SharedStats(userID: userID, shares: true, streak: 12, daysTracked: 90, workouts: 34)
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/profile_stats")
        // Without merge-duplicates an upsert of an existing row is a conflict,
        // and every push after the first would fail.
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")

        let row = try #require(body(of: request).first)
        #expect(row["user_id"] as? String == userID.uuidString)
        #expect(row["shares"] as? Bool == true)
        #expect(row["streak"] as? Int == 12)
        #expect(row["days_tracked"] as? Int == 90)
        #expect(row["workouts"] as? Int == 34)
    }

    /// The point of the whole feature: turning sharing off must remove the
    /// numbers from the server, not merely stop refreshing them. An upsert
    /// leaves omitted columns standing, so these have to be explicit nulls.
    @Test func sharingOffNullsTheFiguresRatherThanOmittingThem() throws {
        let request = try SharedStatsClient.pushRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            stats: SharedStats(userID: UUID(), shares: false, streak: 12, daysTracked: 90, workouts: 34)
        )

        let row = try #require(body(of: request).first)
        #expect(row["shares"] as? Bool == false)
        #expect(row["streak"] is NSNull)
        #expect(row["days_tracked"] is NSNull)
        #expect(row["workouts"] is NSNull)
    }

    @Test func aFigureNeverMeasuredIsSentAsNull() throws {
        let request = try SharedStatsClient.pushRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: token,
            stats: SharedStats(userID: UUID(), shares: true, streak: 3, daysTracked: nil, workouts: nil)
        )

        let row = try #require(body(of: request).first)
        #expect(row["streak"] as? Int == 3)
        #expect(row["days_tracked"] is NSNull)
        #expect(row["workouts"] is NSNull)
    }

    // MARK: - Read

    @Test func idsGoOutAsOneInFilter() {
        let first = UUID()
        let second = UUID()
        let request = SharedStatsClient.statsRequest(
            baseURL: baseURL, anonKey: anonKey, accessToken: token, ids: [first, second]
        )
        let query = request.url?.query ?? ""
        #expect(query.contains("user_id=in."))
        #expect(query.contains(first.uuidString))
        #expect(query.contains(second.uuidString))
    }

    @Test func statsDecodeFromSnakeCaseJSON() throws {
        let userID = UUID()
        let json = """
        [{"user_id":"\(userID.uuidString)","shares":true,"streak":7,"days_tracked":40,"workouts":11}]
        """
        let rows = try JSONDecoder().decode([SharedStats].self, from: Data(json.utf8))
        let stats = try #require(rows.first)
        #expect(stats.userID == userID)
        #expect(stats.streak == 7)
        #expect(stats.daysTracked == 40)
        #expect(stats.workouts == 11)
        #expect(stats.hasFigures)
    }

    /// Sharing on with nothing pushed yet is not the same as declining, but
    /// both draw a profile with no panel on it.
    @Test func sharingWithNoFiguresYetHasNothingToDraw() {
        let stats = SharedStats(userID: UUID(), shares: true)
        #expect(stats.shares)
        #expect(!stats.hasFigures)
    }

    @Test func figuresWithoutSharingHaveNothingToDraw() {
        let stats = SharedStats(userID: UUID(), shares: false, streak: 9)
        #expect(!stats.hasFigures)
    }

    @Test func anEmptyIDListNeverLeavesTheDevice() async throws {
        let client = SharedStatsClient(baseURL: baseURL, anonKey: anonKey)
        let result = try await client.stats(ids: [], accessToken: token)
        #expect(result.isEmpty)
    }
}
