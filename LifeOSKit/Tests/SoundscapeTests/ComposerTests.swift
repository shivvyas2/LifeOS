import Testing
import Foundation
@testable import Soundscape

@Suite struct ComposerTests {
    func params(_ mood: Mood, hour: Int = 14) -> SoundParameters {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour))!
        return .make(.for(mood), Conditions(date: date, timeZone: TimeZone(identifier: "UTC")!))
    }

    func bars(_ mood: Mood, seed: UInt64, count: Int, hour: Int = 14) -> [[NoteEvent]] {
        var composer = Composer(recipe: .for(mood), seed: seed)
        var events: [NoteEvent] = []; events.reserveCapacity(128)
        let p = params(mood, hour: hour)
        return (0..<count).map { _ in composer.nextBar(p, into: &events); return events }
    }

    @Test(arguments: Mood.allCases)
    func theSameSeedWritesTheSamePiece(_ mood: Mood) {
        #expect(bars(mood, seed: 7, count: 60) == bars(mood, seed: 7, count: 60))
        #expect(bars(mood, seed: 7, count: 60) != bars(mood, seed: 8, count: 60))
    }

    @Test(arguments: Mood.allCases)
    func everyNoteIsInTheScale(_ mood: Mood) {
        let recipe = MoodRecipe.for(mood)
        for hour in [8, 14, 20] {
            let key = params(mood, hour: hour).keyOffset
            for event in bars(mood, seed: 3, count: 80, hour: hour).flatMap({ $0 }) {
                let pitchClass = ((event.midi - recipe.rootMidi - key) % 12 + 12) % 12
                #expect(recipe.scale.contains(pitchClass), "\(mood) \(event)")
            }
        }
    }

    @Test(arguments: Mood.allCases)
    func eventsAreSortedAndInsideTheBar(_ mood: Mood) {
        let bar = params(mood).barSeconds
        for events in bars(mood, seed: 11, count: 40) {
            #expect(events.map(\.offset) == events.map(\.offset).sorted())
            #expect(events.allSatisfy { $0.offset >= 0 && $0.offset < bar })
            #expect(events.allSatisfy { (24...100).contains($0.midi) })
        }
    }

    @Test func focusChangesChordEveryFiveToNineBars() {
        var composer = Composer(recipe: .for(.focus), seed: 5)
        var events: [NoteEvent] = []; events.reserveCapacity(128)
        var changes: [Int] = []
        for bar in 0..<200 {
            composer.nextBar(params(.focus), into: &events)
            if events.contains(where: { $0.layer == .pad }) { changes.append(bar) }
        }
        let gaps = zip(changes.dropFirst(), changes).map { $0 - $1 }
        #expect(!gaps.isEmpty && gaps.allSatisfy { (5...9).contains($0) })
    }

    @Test func focusHasAFourBeatPulseAndNoPlucks() {
        let events = bars(.focus, seed: 1, count: 1)[0]
        #expect(events.filter { $0.layer == .pulse }.count == 4)
        #expect(!events.contains { $0.layer == .pluck })
    }

    @Test func brainstormPlucksAndRelaxDoesNot() {
        #expect(bars(.brainstorm, seed: 2, count: 20).flatMap { $0 }.contains { $0.layer == .pluck })
        #expect(!bars(.relax, seed: 2, count: 20).flatMap { $0 }.contains { $0.layer == .pluck || $0.layer == .pulse })
    }

    @Test func focusBellsAreSparse() {
        let bells = bars(.focus, seed: 9, count: 400).flatMap { $0 }.filter { $0.layer == .bell }.count
        // One bell every two to four bars on average.
        #expect((100...200).contains(bells))
    }
}
