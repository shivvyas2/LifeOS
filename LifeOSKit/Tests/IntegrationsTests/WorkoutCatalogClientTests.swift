import Foundation
import Testing
import Persistence
@testable import Integrations

struct WorkoutCatalogClientTests {
    @Test func requestCarriesBothKeysAndSelectsEverything() {
        let request = WorkoutCatalogClient.request(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon", accessToken: "tok")
        #expect(request.url?.absoluteString == "https://x.supabase.co/rest/v1/workout_videos?select=*&order=updated_at.asc")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }
    @Test func decodesArraysAndKeepsUnknownSplitAsText() throws {
        let json = #"[{"youtube_id":"abcdefghijk","title":"T","channel":"C","duration_s":1800,"goal":["strength"],"split":"glutes","muscles":["glutes"],"equipment":["bands"],"intensity":2,"verified_at":"2026-09-15T09:00:00Z","updated_at":"2026-09-15T09:00:00Z"}]"#
        let rows = try WorkoutCatalogClient.decode(Data(json.utf8))
        #expect(rows.count == 1 && rows[0].split == "glutes" && rows[0].equipment == ["bands"] && rows[0].durationS == 1800)
    }
}
