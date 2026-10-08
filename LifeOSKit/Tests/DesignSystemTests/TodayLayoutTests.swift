import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodayLayoutTests {
    @Test func theDefaultIsTheIPadEstate() {
        let layout = TodayLayout.standard
        #expect(layout.left == [.nextUp, .month, .tasks, .focus, .scheduledWorkout])
        #expect(layout.right == [.steps, .sleep, .weight, .recovery])
        #expect(layout.hidden == [.github, .weather, .spentToday, .fromLifo, .projects, .inbox])
        #expect(layout.phoneOrder == layout.left + layout.right)
    }

    @Test func moveWithinAndAcross() {
        var layout = TodayLayout.standard
        layout.move(.month, to: .left, at: 0)
        #expect(layout.left == [.month, .nextUp, .tasks, .focus, .scheduledWorkout])
        layout.move(.tasks, to: .right, at: 1)
        #expect(layout.left == [.month, .nextUp, .focus, .scheduledWorkout])
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

    @Test func aDropLandsBeforeOrAfterItsTarget() {
        var layout = TodayLayout(left: [.nextUp, .month, .tasks], right: [.steps])
        layout.place(.nextUp, nextTo: .month, after: true)
        #expect(layout.left == [.month, .nextUp, .tasks])
        layout.place(.tasks, nextTo: .month, after: false)
        #expect(layout.left == [.tasks, .month, .nextUp])
        layout.place(.steps, nextTo: .nextUp, after: true)
        #expect(layout.left == [.tasks, .month, .nextUp, .steps])
        #expect(layout.right.isEmpty)
        layout.place(.month, nextTo: .month, after: true)
        #expect(layout.left == [.tasks, .month, .nextUp, .steps])
        layout.place(.weather, nextTo: .tasks, after: false)
        #expect(layout.left.first == .weather)
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
        let data = Data(#"{"left":["month","notAModule","nextUp"],"right":["steps"]}"#.utf8)
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

    @Test func aLayoutSavedBeforeProjectsKeepsItHidden() {
        let data = Data(#"{"left":["month","nextUp"],"right":["steps"]}"#.utf8)
        #expect(TodayLayout.decoded(data).hidden.contains(.projects))
        #expect(TodayModule.projects.title == "Projects")
        #expect(TodayModule.projects.daySection == nil)
    }

    @Test func aLayoutSavedBeforeFocusKeepsItHidden() {
        let data = Data(#"{"left":["month","nextUp"],"right":["steps"]}"#.utf8)
        #expect(TodayLayout.decoded(data).hidden.contains(.focus))
        #expect(TodayModule.focus.title == "Focus")
        #expect(TodayModule.focus.daySection == nil)
    }

    @Test func aLayoutSavedBeforeTheInboxKeepsItHiddenUntilOffered() {
        let data = Data(#"{"left":["month","nextUp"],"right":["steps"]}"#.utf8)
        var layout = TodayLayout.decoded(data)
        #expect(layout.hidden.contains(.inbox))
        #expect(TodayModule.inbox.title == "Inbox")
        #expect(TodayModule.inbox.daySection == nil)
        layout.offerInbox()
        layout.offerInbox()
        #expect(layout.left.filter { $0 == .inbox }.count == 1)
        #expect(layout.left.last == .inbox)
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
