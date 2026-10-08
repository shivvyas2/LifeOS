import Testing
import Foundation
@testable import Soundscape

@Suite struct RendererTests {
    func params(_ mood: Mood, phase: SoundPhase = .work, texture: Texture = .auto, weather: WeatherInput? = nil) -> SoundParameters {
        .make(.for(mood), Conditions(date: Date(timeIntervalSince1970: 1_791_460_800), timeZone: TimeZone(identifier: "UTC")!,
                                     phase: phase, weather: weather, texture: texture))
    }

    @Test(arguments: Mood.allCases)
    func everyMoodMakesSoundUnderZeroDecibels(_ mood: Mood) {
        let r = SoundscapeRenderer(mood: mood, seed: 4, parameters: params(mood, weather: WeatherInput(kind: .rain, windKph: 40)))
        let (l, rr) = r.render(seconds: 20)
        #expect(l.count == 960_000 && rr.count == 960_000)
        #expect(l.allSatisfy { $0.isFinite && abs($0) < 1 })
        #expect(rr.allSatisfy { $0.isFinite && abs($0) < 1 })
        let rms = sqrt(l.map { Double($0 * $0) }.reduce(0, +) / Double(l.count))
        #expect(rms > 0.01, "\(mood) is nearly silent: \(rms)")
    }

    @Test func theSameSeedRendersTheSameAudio() {
        let a = SoundscapeRenderer(mood: .focus, seed: 9, parameters: params(.focus)).render(seconds: 5)
        let b = SoundscapeRenderer(mood: .focus, seed: 9, parameters: params(.focus)).render(seconds: 5)
        #expect(a.left == b.left)
    }

    @Test func aFinishedFadeIsSilent() {
        let r = SoundscapeRenderer(mood: .sleep, seed: 1, parameters: params(.sleep, phase: .fading(1)))
        let (l, _) = r.render(seconds: 2)
        #expect(l.map(abs).max()! < 1e-3)
    }

    @Test func newParametersGlideRatherThanJump() {
        let r = SoundscapeRenderer(mood: .focus, seed: 2, parameters: params(.focus))
        _ = r.render(seconds: 10)
        r.set(params(.focus, phase: .fading(1)))
        let (l, _) = r.render(seconds: 12)
        let firstHalfSecond = l[0..<24_000].map(abs).max()!
        let last = l[(l.count - 24_000)...].map(abs).max()!
        #expect(firstHalfSecond > 0.01)
        #expect(last < firstHalfSecond * 0.1)
    }

    @Test func lightModeDropsStruckLayersAndStillPlays() {
        let r = SoundscapeRenderer(mood: .brainstorm, seed: 3, parameters: params(.brainstorm))
        r.setLight(true)
        let (l, _) = r.render(seconds: 10)
        #expect(r.isLight)
        #expect(l.contains { abs($0) > 0.01 })
    }

    @Test func aChimeIsHeardEvenWhenBellsAreMuted() {
        // Bells are muted this late in a fade and the master is low: the chime
        // has its own gain and sits after the master.
        let quiet = SoundscapeRenderer(mood: .sleep, seed: 1, parameters: params(.sleep, phase: .fading(0.9)))
        _ = quiet.render(seconds: 8)
        quiet.chime()
        let (l, _) = quiet.render(seconds: 1)
        #expect(l.map(abs).max()! > 0.05)
    }

    @Test func rendersFasterThanRealTimeEvenInDebug() {
        let r = SoundscapeRenderer(mood: .brainstorm, seed: 5, parameters: params(.brainstorm, weather: WeatherInput(kind: .rain, windKph: 5)))
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = r.render(seconds: 120) }
        // Two minutes of the busiest mood in under two minutes on an unoptimised
        // build; release builds are several times faster.
        #expect(elapsed < .seconds(120), "\(elapsed)")
    }

    @Test func wavHeaderIsStandard() {
        let data = WAVWriter.data(left: [0, 0.5, -0.5], right: [0, 0.5, -0.5], sampleRate: 48_000)
        #expect(data.count == 44 + 3 * 4)
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(String(data: data[36..<40], encoding: .ascii) == "data")
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 48_000)
    }
}
