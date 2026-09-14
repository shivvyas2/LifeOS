import Foundation
import Testing
@testable import Persistence

struct WorkoutSetsTests {
    @Test func setsRoundTripThroughData() {
        let row = WorkoutRecord(externalID: "t", start: .now, durationMinutes: 20, activityName: "Strength")
        #expect(row.sets.isEmpty && row.setsData == nil)
        row.sets = [12, 10, 8]
        #expect(row.sets == [12, 10, 8])
        row.sets = []
        #expect(row.setsData == nil)
    }
}
