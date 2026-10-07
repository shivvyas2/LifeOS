import Testing
import Foundation
@testable import Persistence

@Suite struct ProjectProgressTests {
    @Test func emptyIsZero() {
        let progress = ProjectProgress.of([])
        #expect(progress.done == 0 && progress.total == 0)
        #expect(progress.fraction == 0)
    }

    @Test func counts() {
        let progress = ProjectProgress.of([.done, .todo, .doing, .done, .todo])
        #expect(progress.done == 2 && progress.total == 5)
        #expect(progress.fraction == 0.4)
    }
}

@Suite struct BoardMoveTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func card(_ n: Int, _ status: ProjectStatus, _ position: Int, doneAt: Date? = nil) -> BoardCard {
        BoardCard(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!, status: status, position: position, doneAt: doneAt)
    }

    @Test func withinAColumn() {
        let cards = [card(1, .todo, 0), card(2, .todo, 1), card(3, .todo, 2)]
        let moved = BoardMove.move(cards[2].id, to: .todo, at: 0, in: cards, now: now)
        let order = moved.filter { $0.status == .todo }.sorted { $0.position < $1.position }.map(\.id)
        #expect(order == [cards[2].id, cards[0].id, cards[1].id])
    }

    @Test func acrossColumnsRenumbersBoth() {
        let cards = [card(1, .todo, 0), card(2, .todo, 1), card(3, .doing, 0)]
        let moved = BoardMove.move(cards[0].id, to: .doing, at: 1, in: cards, now: now)
        let todo = moved.filter { $0.status == .todo }.sorted { $0.position < $1.position }
        let doing = moved.filter { $0.status == .doing }.sorted { $0.position < $1.position }
        #expect(todo.map(\.id) == [cards[1].id])
        #expect(todo.map(\.position) == [0])
        #expect(doing.map(\.id) == [cards[2].id, cards[0].id])
        #expect(doing.map(\.position) == [0, 1])
    }

    @Test func doneStampsAndLeavingClears() {
        let cards = [card(1, .doing, 0)]
        let done = BoardMove.move(cards[0].id, to: .done, at: 0, in: cards, now: now)
        #expect(done.first { $0.id == cards[0].id }?.doneAt == now)
        let back = BoardMove.move(cards[0].id, to: .todo, at: 0, in: done, now: now)
        #expect(back.first { $0.id == cards[0].id }?.doneAt == nil)
    }
}

@Suite struct ScheduleLayoutTests {
    private func at(_ hour: Double) -> Date { Date(timeIntervalSince1970: hour * 3_600) }

    @Test func alone() {
        let a = TimeBlock(id: UUID(), start: at(9), end: at(10))
        let lanes = ScheduleLayout.lanes([a])
        #expect(lanes[a.id]?.lane == 0)
        #expect(lanes[a.id]?.lanes == 1)
    }

    @Test func overlapsShareLanes() {
        let a = TimeBlock(id: UUID(), start: at(9), end: at(11))
        let b = TimeBlock(id: UUID(), start: at(10), end: at(12))
        let c = TimeBlock(id: UUID(), start: at(11.5), end: at(12.5))
        let lanes = ScheduleLayout.lanes([c, a, b])
        #expect(lanes[a.id]?.lane == 0)
        #expect(lanes[b.id]?.lane == 1)
        #expect(lanes[c.id]?.lane == 0)
        #expect([a, b, c].allSatisfy { lanes[$0.id]?.lanes == 2 })
    }
}

@Suite struct ContributionScaleTests {
    @Test func levels() {
        #expect(ContributionScale.levels([0, 1, 2, 3, 4, 8]) == [0, 1, 1, 2, 3, 4])
        #expect(ContributionScale.levels([0, 0]) == [0, 0])
    }
}

@Suite struct ProjectMergeTests {
    private let t = Date(timeIntervalSince1970: 1_000)

    @Test func aNewerLocalEditSurvives() {
        #expect(ProjectMerge.keepLocal(localUpdatedAt: t.addingTimeInterval(60), localSyncedAt: t, remoteUpdatedAt: t.addingTimeInterval(30)))
    }

    @Test func aSyncedLocalLoses() {
        #expect(!ProjectMerge.keepLocal(localUpdatedAt: t, localSyncedAt: t, remoteUpdatedAt: t.addingTimeInterval(30)))
        #expect(!ProjectMerge.keepLocal(localUpdatedAt: t.addingTimeInterval(10), localSyncedAt: nil, remoteUpdatedAt: t.addingTimeInterval(30)))
    }
}
