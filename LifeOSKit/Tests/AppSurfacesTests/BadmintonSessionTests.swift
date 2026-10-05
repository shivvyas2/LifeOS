import Foundation
import Testing
@testable import AppSurfaces

struct BadmintonSessionTests {
    @Test func aDoublesMatchKeepsItsPartnerAndTwoOpponents() {
        let value = BadmintonSession(kind: .match, format: .doubles, teammate: "  Priya ",
                                     opponents: ["Sam", "Alex", "Extra"])
        #expect(value.teammate == "Priya")
        #expect(value.opponents == ["Sam", "Alex"])
        #expect(value.score != nil)
        #expect(value.isValid)
    }

    @Test func singlesHasNoPartnerAndOneOpponent() {
        let value = BadmintonSession(format: .singles, teammate: "Priya", opponents: ["Sam", "Alex"])
        #expect(value.teammate == nil)
        #expect(value.opponents == ["Sam"])
        #expect(value.isValid)
    }

    @Test func practiceHasAFocusAndNoScore() {
        var value = BadmintonSession(kind: .practice, focus: "Net play")
        #expect(value.score == nil)
        value.record(.us) // ignored, not a crash
        #expect(value.summary == "Practice · Net play")
        #expect(value.isValid)
    }

    @Test func blankAndOverlongNamesAreCleaned() {
        let value = BadmintonSession(format: .doubles, teammate: "   ",
                                     opponents: [String(repeating: "x", count: 90)])
        #expect(value.teammate == nil)
        #expect(value.opponents.first?.count == BadmintonSession.nameLimit)
    }

    @Test func theSummaryReadsLikeAResult() {
        var value = BadmintonSession()
        #expect(value.summary == "Unfinished")
        for _ in 0..<21 { value.record(.us) }
        for _ in 0..<5 { value.record(.them) }
        #expect(value.summary == "Unfinished 21-0 0-5")
        for _ in 0..<21 { value.record(.us) }
        #expect(value.summary == "Won 21-0 21-5")
    }

    @Test func aTamperedSessionIsRejected() throws {
        var value = BadmintonSession(format: .singles)
        value.teammate = "Smuggled"
        #expect(!value.isValid)
        value = BadmintonSession(kind: .practice)
        value.score = BadmintonScore()
        #expect(!value.isValid)
        let back = try JSONDecoder().decode(BadmintonSession.self,
                                            from: JSONEncoder().encode(BadmintonSession(format: .doubles, teammate: "Priya")))
        #expect(back.isValid)
    }
}
