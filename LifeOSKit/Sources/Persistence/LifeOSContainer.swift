import Foundation
import SwiftData

public enum LifeOSContainer {
    public static let schema = Schema([
        DailyMetrics.self,
        UserGoals.self,
        WorkoutRecord.self,
        SleepRecord.self,
    ])

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
