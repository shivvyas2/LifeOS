import Testing
import SwiftUI
@testable import DesignSystem

@Suite struct ProjectColourTests {
    @Test func sixColoursEachWithFiveLevels() {
        #expect(ProjectColour.allCases.map(\.rawValue) == ["tomato", "marigold", "moss", "lagoon", "iris", "rose"])
        for colour in ProjectColour.allCases {
            let levels = (0...4).map { colour.ramp(level: $0).light }
            #expect(Set(levels.map { "\($0)" }).count == 5, "\(colour) levels are not distinct")
        }
    }

    @Test func emptyIsTheSameForEveryColour() {
        let empties = Set(ProjectColour.allCases.map { "\($0.ramp(level: 0).light)" })
        #expect(empties.count == 1)
    }

    @Test func anUnknownNameFallsBackToTomato() {
        #expect(ProjectColour(named: "purple") == .tomato)
        #expect(ProjectColour(named: "moss") == .moss)
    }
}
