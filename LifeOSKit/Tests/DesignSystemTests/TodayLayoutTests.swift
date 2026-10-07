import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodayLayoutTests {
    @Test func theDefaultIsTheIPadEstate() {
        let layout = TodayLayout.standard
        #expect(layout.left == [.nextUp, .month, .tasks, .scheduledWorkout])
        #expect(layout.right == [.steps, .sleep, .weight, .recovery])
        #expect(layout.hidden == [.github, .weather, .spentToday, .fromLifo])
        #expect(layout.phoneOrder == layout.left + layout.right)
    }

    @Test func moveWithinAndAcross() {
        var layout = TodayLayout.standard
        layout.move(.month, to: .left, at: 0)
        #expect(layout.left == [.month, .nextUp, .tasks, .scheduledWorkout])
        layout.move(.tasks, to: .right, at: 1)
        #expect(layout.left == [.month, .nextUp, .scheduledWorkout])
        #expect(layout.right == [.steps, .tasks, .sleep, .weight, .recovery])
        layout.move(.weather, to: .left, at: 99)
        #expect(layout.left.last == .weather)
    }

    @Test func hideThenAddRoundTrips() {
        var layout = TodayLayout(left: [.nextUp], right: [])
        layout.hide(.nextUp)
        #expect(layout.left.isEmpty)
        #expect(layout.hidden.contains(.nextUp))
        layout.add(.nextUp, to: .left)
        layout.add(.nextUp, to: .right)
        #expect(layout.left == [.nextUp])
        #expect(layout.right.isEmpty)
    }

    @Test func addPicksTheShorterColumnCountingTilesAsHalf() {
        var layout = TodayLayout(left: [.nextUp, .month], right: [.steps, .sleep, .weight])
        layout.add(.weather)
        #expect(layout.right.last == .weather)
        var other = TodayLayout(left: [.nextUp], right: [.month, .tasks])
        other.add(.weather)
        #expect(other.left.last == .weather)
    }

    @Test func moveUpAndDownCrossTheColumns() {
        var layout = TodayLayout(left: [.nextUp, .month], right: [.steps, .sleep])
        layout.moveDown(.month)
        #expect(layout.left == [.nextUp])
        #expect(layout.right == [.month, .steps, .sleep])
        layout.moveUp(.month)
        #expect(layout.left == [.nextUp, .month])
        layout.moveUp(.nextUp)
        #expect(layout.left == [.nextUp, .month])
        layout.moveToOtherColumn(.nextUp)
        #expect(layout.right.first == .nextUp)
    }

    @Test func adjacentTilesPairUp() {
        #expect(TodayLayout.rows([.month, .steps, .sleep, .weight, .nextUp, .recovery])
                == [.single(.month), .pair(.steps, .sleep), .pair(.weight, nil), .single(.nextUp), .pair(.recovery, nil)])
    }

    @Test func aRowNamesItsModules() {
        #expect(TodayRow.single(.month).modules == [.month])
        #expect(TodayRow.pair(.steps, .sleep).modules == [.steps, .sleep])
        #expect(TodayRow.pair(.weight, nil).modules == [.weight])
    }

    @Test func decodingKeepsNewModulesHiddenAndDropsUnknownOnes() {
        let data = Data(#"{"left":["month","inbox","nextUp"],"right":["steps"]}"#.utf8)
        let layout = TodayLayout.decoded(data)
        #expect(layout.left == [.month, .nextUp])
        #expect(layout.right == [.steps])
        #expect(layout.hidden.contains(.tasks))
    }

    @Test func aModuleSavedTwiceIsKeptOnce() {
        let data = Data(#"{"left":["month"],"right":["month","steps"]}"#.utf8)
        let layout = TodayLayout.decoded(data)
        #expect(layout.left == [.month])
        #expect(layout.right == [.steps])
    }

    @Test func nothingSavedIsTheDefaultAndItRoundTrips() {
        #expect(TodayLayout.decoded(nil) == .standard)
        var layout = TodayLayout.standard
        layout.move(.month, to: .left, at: 0)
        #expect(TodayLayout.decoded(layout.encoded()) == layout)
    }

    @Test func gitHubIsOfferedOnceToTheLeft() {
        var layout = TodayLayout.standard
        layout.offerGitHub()
        layout.offerGitHub()
        #expect(layout.left.filter { $0 == .github }.count == 1)
        #expect(layout.left.last == .github)
    }

    @Test func titlesAndTiles() {
        #expect(TodayModule.tasks.title == "Today's tasks")
        #expect(TodayModule.fromLifo.title == "From LIFO")
        #expect(TodayModule.allCases.filter(\.isTile) == [.steps, .sleep, .weight, .recovery])
    }
}

@Suite struct TodayModuleSectionsTests {
    @Test func hiddenModulesLoadNothing() {
        #expect(TodayLayout.sections(for: [.nextUp, .month, .tasks]) == [.checklist])
        #expect(TodayLayout.sections(for: [.weather, .github, .spentToday, .fromLifo]) == [.weather, .project, .money, .nudges])
    }
}
