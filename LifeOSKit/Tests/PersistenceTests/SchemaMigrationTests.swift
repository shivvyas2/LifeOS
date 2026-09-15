import Foundation
import SwiftData
import Testing
@testable import Persistence

/// A field added to an entity that already has rows on people's devices must
/// carry a default, or the store refuses to migrate in place ("Validation
/// error missing attribute values on mandatory destination attribute") and the
/// app opens no store at all.
struct SchemaMigrationTests {
    @Test func fieldsAddedToTheGoalsRowHaveDefaults() throws {
        let goals = try #require(LifeOSContainer.schema.entities.first { $0.name == "UserGoals" })
        let added = ["trainingGoal", "equipmentRaw", "sessionMinutes"]
        for name in added {
            let attribute = try #require(goals.attributesByName[name], "missing \(name)")
            #expect(attribute.isOptional || attribute.defaultValue != nil, "\(name) has no default and is not optional")
        }
    }
}
