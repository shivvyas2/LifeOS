import Testing
import Foundation
@testable import Soundscape

@Suite struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let classic = TimerPlan.pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: 4)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aPomodoroWalksThroughItsBlocks() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        #expect(timer.reading(at: at(0)).phase == .work(block: 1))
        #expect(timer.reading(at: at(0)).remaining == 1500)
        #expect(timer.reading(at: at(1500)).phase == .rest(afterBlock: 1))
        #expect(timer.reading(at: at(1800)).phase == .work(block: 2))
        #expect(timer.reading(at: at(1800)).completedBlocks == 1)
        #expect(timer.reading(at: at(1860)).focusedSeconds == 1560)
        #expect(timer.reading(at: at(6899)).phase == .work(block: 4))
        let done = timer.reading(at: at(6900))
        #expect(done.phase == .finished)
        #expect(done.completedBlocks == 4)
        #expect(done.focusedSeconds == 6000)
    }

    @Test func anOpenEndedPomodoroTakesALongBreakAfterEveryFourth() {
        let timer = FocusTimer(plan: .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: nil), startedAt: t0)
        // Four blocks and three short breaks: 6900 s.
        #expect(timer.reading(at: at(6900)).phase == .longRest(afterBlock: 4))
        #expect(timer.reading(at: at(6900)).remaining == 900)
        #expect(timer.reading(at: at(7800)).phase == .work(block: 5))
    }

    @Test func aLongGapLandsInTheRightPhase() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        // Locked for two hours: the session finished while the phone slept.
        #expect(timer.reading(at: at(7200)).phase == .finished)
        let open = FocusTimer(plan: .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: nil), startedAt: t0)
        // 3 h = 10800 s. One full cycle is 4*1500 + 3*300 + 900 = 7800 s; block 5 runs 7800 to 9300,
        // a break to 9600, then block 6 from 9600: 1200 s in, 300 s left.
        #expect(open.reading(at: at(10_800)).phase == .work(block: 6))
        #expect(open.reading(at: at(10_800)).remaining == 300)
    }

    @Test func skipAndPauseKeepTheClock() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(600))
        #expect(timer.reading(at: at(5000)).remaining == 900)
        #expect(timer.reading(at: at(5000)).isPaused)
        timer.resume(at: at(5000))
        #expect(timer.reading(at: at(5900)).phase == .rest(afterBlock: 1))
        timer.skip(at: at(5960))
        #expect(timer.reading(at: at(5960)).phase == .work(block: 2))
        #expect(timer.reading(at: at(5960)).remaining == 1500)
        #expect(timer.reading(at: at(5960)).focusedSeconds == 1500)
    }

    @Test func skippingWorkCountsWhatWasDone() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.skip(at: at(100))
        let r = timer.reading(at: at(100))
        #expect(r.phase == .rest(afterBlock: 1))
        #expect(r.focusedSeconds == 100)
    }

    @Test func skipWhilePausedStaysPaused() {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(200))
        timer.skip(at: at(400))
        #expect(timer.reading(at: at(900)).phase == .rest(afterBlock: 1))
        #expect(timer.reading(at: at(900)).remaining == 300)
    }

    @Test func countdownAndOpenEnded() {
        let twenty = FocusTimer(plan: .countdown(1200), startedAt: t0)
        #expect(twenty.reading(at: at(100)).phase == .open)
        #expect(twenty.reading(at: at(100)).remaining == 1100)
        #expect(twenty.reading(at: at(1200)).phase == .finished)
        let open = FocusTimer(plan: .countdown(nil), startedAt: t0)
        #expect(open.reading(at: at(100_000)).phase == .open)
        #expect(open.reading(at: at(100_000)).remaining == nil)
        #expect(open.reading(at: at(100)).focusedSeconds == 100)
    }

    @Test func sleepFadesThenFinishesAndAllNightNeverDoes() {
        let fade = FocusTimer(plan: .fade(1800), startedAt: t0)
        #expect(fade.reading(at: at(900)).phase == .fading)
        #expect(fade.reading(at: at(900)).progress == 0.5)
        #expect(fade.reading(at: at(1800)).phase == .finished)
        #expect(FocusTimer(plan: .fade(nil), startedAt: t0).reading(at: at(40_000)).phase == .open)
    }

    @Test func soundPhaseFollowsTheReading() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        #expect(SoundPhase(timer.reading(at: at(100))) == .work)
        #expect(SoundPhase(timer.reading(at: at(1470))) == .closing(0.5))
        #expect(SoundPhase(timer.reading(at: at(1600))) == .rest)
        #expect(SoundPhase(FocusTimer(plan: .fade(1000), startedAt: t0).reading(at: at(250))) == .fading(0.25))
        #expect(SoundPhase(timer.reading(at: at(99_999))) == .fading(1))
    }

    @Test func upcomingEndsListTheNextBoundaries() {
        let timer = FocusTimer(plan: classic, startedAt: t0)
        let ends = timer.upcomingEnds(after: at(10), limit: 12)
        #expect(ends.count == 7)
        #expect(ends[0] == PhaseEnd(ending: .work(block: 1), next: .rest(afterBlock: 1), at: at(1500)))
        #expect(ends.last == PhaseEnd(ending: .work(block: 4), next: .finished, at: at(6900)))
        var paused = timer; paused.pause(at: at(10))
        #expect(paused.upcomingEnds(after: at(10), limit: 12).isEmpty)
        #expect(FocusTimer(plan: .countdown(nil), startedAt: t0).upcomingEnds(after: at(0), limit: 12).isEmpty)
    }

    @Test func aTimerSurvivesEncoding() throws {
        var timer = FocusTimer(plan: classic, startedAt: t0)
        timer.pause(at: at(30))
        let copy = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
        #expect(copy == timer)
    }
}
