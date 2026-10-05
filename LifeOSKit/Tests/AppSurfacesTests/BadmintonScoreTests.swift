import Foundation
import Testing
@testable import AppSurfaces

struct BadmintonScoreTests {
    func score(_ rallies: [BadmintonSide], firstServer: BadmintonSide = .us) -> BadmintonScore {
        var value = BadmintonScore(firstServer: firstServer)
        for side in rallies { value.record(side) }
        return value
    }
    func repeated(_ side: BadmintonSide, _ count: Int) -> [BadmintonSide] { Array(repeating: side, count: count) }

    @Test func aGameIsWonAtTwentyOne() {
        let value = score(repeated(.us, 21))
        #expect(value.games == [BadmintonGame(us: 21, them: 0)])
        #expect(value.gamesWon(by: .us) == 1)
        #expect(value.current == BadmintonGame(us: 0, them: 0))
        #expect(!value.isOver)
    }

    @Test func atTwentyAllAGameNeedsATwoPointLead() {
        let deuce = repeated(.us, 20) + repeated(.them, 20)
        var value = score(deuce + [.us])
        #expect(value.current == BadmintonGame(us: 21, them: 20))
        #expect(value.games.isEmpty)
        value.record(.us)
        #expect(value.games == [BadmintonGame(us: 22, them: 20)])
    }

    @Test func atTwentyNineAllTheThirtiethPointWins() {
        var value = score(repeated(.us, 20) + repeated(.them, 20))
        for _ in 0..<9 { value.record(.us); value.record(.them) } // 29-29
        #expect(value.current == BadmintonGame(us: 29, them: 29))
        value.record(.them)
        #expect(value.games == [BadmintonGame(us: 29, them: 30)])
    }

    @Test func theMatchIsBestOfThree() {
        var value = score(repeated(.us, 21) + repeated(.them, 21))
        #expect(value.games.count == 2)
        #expect(!value.isOver)
        for _ in 0..<21 { value.record(.us) }
        #expect(value.isOver)
        #expect(value.winner == .us)
        // Nothing is recorded once the match is decided.
        value.record(.them)
        #expect(value.games.count == 3)
        #expect(value.current == BadmintonGame(us: 0, them: 0))
    }

    @Test func aStraightGamesWinEndsTheMatchAfterTwo() {
        let value = score(repeated(.them, 42))
        #expect(value.isOver)
        #expect(value.winner == .them)
        #expect(value.games.count == 2)
    }

    @Test func theRallyWinnerServesNext() {
        var value = BadmintonScore(firstServer: .us)
        #expect(value.server == .us)
        value.record(.them)
        #expect(value.server == .them)
        value.record(.them)
        #expect(value.server == .them)
        value.record(.us)
        #expect(value.server == .us)
    }

    @Test func theServerServesFromTheRightOnAnEvenScore() {
        var value = BadmintonScore(firstServer: .us)
        #expect(value.serviceCourt == .right) // 0
        value.record(.us)
        #expect(value.serviceCourt == .left) // 1
        value.record(.them)
        #expect(value.serviceCourt == .left) // they serve on their 1
        value.record(.them)
        #expect(value.serviceCourt == .right) // they serve on their 2
    }

    @Test func theWinnerOfAGameServesFirstInTheNext() {
        let value = score(repeated(.them, 21), firstServer: .us)
        #expect(value.server == .them)
    }

    @Test func endsChangeAtElevenInTheDecidingGameOnly() {
        var value = score(repeated(.us, 10))
        value.record(.us)
        #expect(!value.changesEndsNow) // game one
        value = score(repeated(.us, 21) + repeated(.them, 21) + repeated(.us, 10))
        #expect(!value.changesEndsNow)
        value.record(.us)
        #expect(value.changesEndsNow)
        value.record(.them)
        #expect(!value.changesEndsNow)
    }

    @Test func undoRemovesTheLastRallyAcrossAGameBoundary() {
        var value = score(repeated(.us, 21))
        #expect(value.games.count == 1)
        value.undo()
        #expect(value.games.isEmpty)
        #expect(value.current == BadmintonGame(us: 20, them: 0))
        #expect(value.server == .us)
        value = BadmintonScore(firstServer: .them)
        value.undo() // nothing to undo is not a crash
        #expect(value.rallies.isEmpty)
    }

    @Test func aScoreSurvivesTheWireIntact() throws {
        let value = score([.us, .them, .them, .us, .us])
        let back = try JSONDecoder().decode(BadmintonScore.self, from: JSONEncoder().encode(value))
        #expect(back == value)
        #expect(back.current == BadmintonGame(us: 3, them: 2))
    }

    @Test func aTamperedScoreIsRejected() throws {
        var value = score([.us])
        value.firstServer = .them
        #expect(value.isValid)
        let data = Data(#"{"firstServer":"us","rallies":["us","sideways"]}"#.utf8)
        #expect((try? JSONDecoder().decode(BadmintonScore.self, from: data)) == nil)
        let long = BadmintonScore(firstServer: .us, rallies: Array(repeating: .us, count: BadmintonScore.rallyLimit + 1))
        #expect(!long.isValid)
    }
}
