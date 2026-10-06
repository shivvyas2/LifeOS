import Testing
import Foundation
@testable import AppSurfaces

@Suite struct BadmintonDemoScriptTests {
    let script = BadmintonDemoScript()

    @Test func swingsAreOrderedWithinTheDemoAndUnderTheReplayLimit() {
        #expect(!script.swings.isEmpty)
        #expect(script.swings.count <= SwingAnalysis.eventLimit)
        #expect(script.swings.map(\.time) == script.swings.map(\.time).sorted())
        #expect(script.swings.allSatisfy { $0.time >= 1 && $0.time <= BadmintonDemoScript.length })
    }

    @Test func theFullAnalysisPassesTheReviewsValidation() {
        let analysis = script.analysis(through: BadmintonDemoScript.length)
        #expect(analysis.isValid(elapsed: BadmintonDemoScript.length))
        #expect(analysis.events.count == script.swings.count)
        #expect(analysis.sampledSeconds == BadmintonDemoScript.length)
        #expect(analysis.events.allSatisfy { $0.frames.count == 8 && $0.twist != nil })
    }

    @Test func aPartialAnalysisKeepsOnlyEarlierSwingsRenumbered() {
        let analysis = script.analysis(through: 300)
        #expect(analysis.isValid(elapsed: 300))
        #expect(analysis.events.allSatisfy { $0.time <= 300 })
        #expect(analysis.events.map(\.id) == Array(0..<analysis.events.count))
        #expect(analysis.events.count == script.swings.filter { $0.time <= 300 }.count)
    }

    @Test func bothStrokeSidesAppearSoTheReviewCanCompareThem() {
        let twists = script.swings.compactMap(\.twist)
        #expect(twists.contains { $0 > 1 } && twists.contains { $0 < -1 })
    }

    @Test func stateCountsSwingsMonotonicallyAndTracksThePeak() {
        var previous = 0
        for second in stride(from: 0.0, through: BadmintonDemoScript.length, by: 10) {
            let state = script.state(at: second)
            #expect(state.swingCount >= previous)
            previous = state.swingCount
            #expect(state.swingCount == script.swings.filter { $0.time <= second }.count)
            let expectedPeak = script.swings.filter { $0.time <= second }.map(\.peakRotation).max()
            #expect(state.peakRotation == expectedPeak)
            #expect((95...185).contains(state.heartRate))
        }
        #expect(script.state(at: 0).swingCount == 0)
        #expect(script.state(at: BadmintonDemoScript.length).swingCount == script.swings.count)
    }

    @Test func energyNeverGoesDown() {
        var last = 0.0
        for second in stride(from: 0.0, through: BadmintonDemoScript.length, by: 30) {
            let energy = script.state(at: second).energyKcal
            #expect(energy >= last); last = energy
        }
        #expect(last > 50)
    }

    @Test func ralliesFinishAtLeastOneGameOfTheDemoMatch() {
        #expect(script.rallies.map(\.time) == script.rallies.map(\.time).sorted())
        var match = BadmintonDemoScript.match
        for rally in script.rallies { match.record(rally.winner) }
        #expect(match.kind == .match && match.format == .doubles && match.teammate != nil)
        #expect((match.score?.games.count ?? 0) >= 1)
        #expect(match.isValid)
        #expect(script.state(at: BadmintonDemoScript.length).rallyWins.count == script.rallies.count)
        #expect(script.state(at: 100).rallyWins == script.rallies.filter { $0.time <= 100 }.map(\.winner))
    }

    @Test func theSameSeedGivesTheSameDemo() {
        #expect(BadmintonDemoScript(seed: 3) == BadmintonDemoScript(seed: 3))
        #expect(BadmintonDemoScript(seed: 3) != BadmintonDemoScript(seed: 4))
    }
}

@Suite struct SwingAnalysisStatusTests {
    @Test func noProfileMeansOffAndPointsAtSetup() {
        let status = SwingAnalysisStatus.describe(nil)
        #expect(!status.isOn)
        #expect(status.text.contains("Your activity setup"))
    }
    @Test func theToggleOffIsNamedAsTheReason() {
        let status = SwingAnalysisStatus.describe(ActivityAthleteProfile(playingHand: .right, watchWrist: .right, motionEnabled: false))
        #expect(!status.isOn)
        #expect(status.text.lowercased().contains("turn on"))
    }
    @Test func aWatchOnTheOtherWristIsNamedAsTheReason() {
        let status = SwingAnalysisStatus.describe(ActivityAthleteProfile(playingHand: .right, watchWrist: .left, motionEnabled: true))
        #expect(!status.isOn)
        #expect(status.text.lowercased().contains("racket wrist"))
    }
    @Test func onSaysWhichWristToWearItOn() {
        let status = SwingAnalysisStatus.describe(ActivityAthleteProfile(playingHand: .left, watchWrist: .left, motionEnabled: true))
        #expect(status.isOn)
        #expect(status.text.lowercased().contains("left wrist"))
    }
}

@Suite struct BadmintonSessionStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func aReadableReviewNeedsNoReason() {
        #expect(BadmintonSessionStatus.reason(externalID: "almanac-watch:X", start: now, motion: .readable, now: now) == nil)
    }
    @Test func unreadableMotionSaysSo() {
        let reason = BadmintonSessionStatus.reason(externalID: "almanac-watch:X", start: now, motion: .unreadable, now: now)
        #expect(reason?.contains("could not be read") == true)
    }
    @Test func aRecentWatchSessionWithoutMotionIsStillSyncing() {
        let reason = BadmintonSessionStatus.reason(externalID: "almanac-watch:X", start: now.addingTimeInterval(-3600), motion: .none, now: now)
        #expect(reason?.contains("Waiting for your Watch") == true)
    }
    @Test func anOldWatchSessionWithoutMotionStoppedWaiting() {
        let reason = BadmintonSessionStatus.reason(externalID: "almanac-watch:X", start: now.addingTimeInterval(-2 * 86400), motion: .none, now: now)
        #expect(reason?.contains("Waiting") == false && reason?.contains("Watch") == true)
    }
    @Test func aPhoneOnlySessionNamesThePhone() {
        let reason = BadmintonSessionStatus.reason(externalID: "almanac:X", start: now, motion: .none, now: now)
        #expect(reason?.contains("iPhone") == true)
    }
    @Test func anImportedSessionNamesTheImport() {
        let reason = BadmintonSessionStatus.reason(externalID: "1234-whoop", start: now, motion: .none, now: now)
        #expect(reason?.contains("Imported") == true)
    }
}
