import Testing
import Foundation
@testable import Soundscape

@Suite struct SoundParametersTests {
    let utc = TimeZone(identifier: "UTC")!

    func at(_ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 8; c.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.date(from: c)!
    }

    func conditions(_ hour: Int = 14, hr: Double? = nil, resting: Double? = 60, phase: SoundPhase = .work,
                    weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil, texture: Texture = .auto) -> Conditions {
        Conditions(date: at(hour), timeZone: utc, heartRate: hr, restingHeartRate: resting, phase: phase,
                   weather: weather, recovery: recovery, texture: texture)
    }

    func make(_ mood: Mood, _ c: Conditions) -> SoundParameters { SoundParameters.make(.for(mood), c) }

    @Test func middayIsTheRecipeAsWritten() {
        let p = make(.focus, conditions(14))
        #expect(p.keyOffset == 0)
        #expect(p.brightness == 0.5)
        #expect(p.density == 0.25)
        #expect(p.tempo == 66)
    }

    @Test func morningRaisesAndOpens() {
        let p = make(.focus, conditions(8))
        #expect(p.keyOffset == 2)
        #expect(abs(p.brightness - 0.65) < 1e-9)
        #expect(p.tempo > 66)
    }

    @Test func eveningLowersAndDarkens() {
        let p = make(.focus, conditions(19))
        #expect(p.keyOffset == -2)
        #expect(abs(p.brightness - 0.35) < 1e-9)
    }

    @Test func lateNightCapsBrightnessForFocusAndBrainstorm() {
        let rest = make(.brainstorm, conditions(23, phase: .rest))
        #expect(rest.brightness <= MoodRecipe.for(.brainstorm).brightness - 0.15 + 1e-9)
    }

    @Test func aRacingHeartThinsFocusButKeepsTempo() {
        let calm = make(.focus, conditions(hr: 60))
        let racing = make(.focus, conditions(hr: 100))
        #expect(racing.density < calm.density)
        #expect(racing.tempo == calm.tempo)
        #expect(racing.density >= calm.density * 0.4)
    }

    @Test func aHighPulseSlowsTheBreathingInRelaxAndSleep() {
        let calm = make(.relax, conditions(hr: 54))
        let high = make(.relax, conditions(hr: 80))
        #expect(calm.breathPeriod == 10)
        #expect(high.breathPeriod! > 10)
        #expect(high.breathPeriod! <= 13 + 1e-9)
    }

    @Test func missingRestingRateUsesSixty() {
        #expect(make(.focus, conditions(hr: 90, resting: nil)) == make(.focus, conditions(hr: 90, resting: 60)))
    }

    @Test func breaksLiftAndDropThePulse() {
        let p = make(.focus, conditions(phase: .rest))
        #expect(p.gains[Layer.pulse.rawValue] == 0)
        #expect(p.brightness > 0.5)
        #expect(p.density < 0.25)
    }

    @Test func theClosingMinuteEasesDown() {
        let start = make(.focus, conditions(phase: .closing(0)))
        let end = make(.focus, conditions(phase: .closing(1)))
        #expect(end.density < start.density)
        #expect(end.master < start.master)
    }

    @Test func sleepFadeDropsLayersInOrder() {
        let early = make(.sleep, conditions(23, phase: .fading(0.3)))
        #expect(early.gains[Layer.bell.rawValue] == 0)
        #expect(early.gains[Layer.pad.rawValue] > 0)
        let mid = make(.sleep, conditions(23, phase: .fading(0.6)))
        #expect(mid.gains[Layer.pad.rawValue] == 0)
        #expect(mid.gains[Layer.bed.rawValue] > 0)
        let late = make(.sleep, conditions(23, phase: .fading(0.8)))
        #expect(late.gains[Layer.bed.rawValue] == 0)
        #expect(late.gains[Layer.drone.rawValue] > 0)
        #expect(late.master < mid.master)
        #expect(make(.sleep, conditions(23, phase: .fading(1))).master < 1e-6)
    }

    @Test func sleepNoiseEasesFromPinkToBrown() {
        #expect(make(.sleep, conditions(23, phase: .fading(0))).bedColour == 0)
        #expect(make(.sleep, conditions(23, phase: .fading(0.5))).bedColour == 0.5)
        #expect(make(.focus, conditions()).bedColour == 1)
    }

    @Test func autoTextureFollowsTheWeather() {
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5))).texture == .rain)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .snow, windKph: 5))).texture == .hiss)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .clear, windKph: 40))).texture == .wind)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .clear, windKph: 5))).texture == .none)
        #expect(make(.focus, conditions(weather: nil)).texture == .none)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5))).gains[Layer.texture.rawValue] > 0)
    }

    @Test func aChosenTextureOverridesTheWeather() {
        let p = make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5), texture: .brown))
        #expect(p.texture == .brown)
        #expect(make(.focus, conditions(weather: WeatherInput(kind: .rain, windKph: 5), texture: .none)).texture == .none)
    }

    @Test func aRedRecoveryDayIsSlowerAndSofter() {
        let normal = make(.focus, conditions())
        let low = make(.focus, conditions(recovery: .low))
        #expect(abs(low.tempo - normal.tempo * 0.92) < 1e-9)
        #expect(abs(low.brightness - (normal.brightness - 0.1)) < 1e-9)
    }

    @Test func weatherSymbolsMapToKinds() {
        #expect(WeatherKind(symbol: "cloud.rain") == .rain)
        #expect(WeatherKind(symbol: "cloud.drizzle.fill") == .rain)
        #expect(WeatherKind(symbol: "cloud.bolt.rain") == .rain)
        #expect(WeatherKind(symbol: "cloud.snow") == .snow)
        #expect(WeatherKind(symbol: "cloud.sleet") == .snow)
        #expect(WeatherKind(symbol: "sun.max") == .clear)
        #expect(WeatherKind(symbol: "cloud.fog") == .other)
        #expect(WeatherInput(symbol: "cloud", windKph: 3, rainChanceNow: 0.7).kind == .rain)
    }

    @Test func recoveryBandsMatchTheApp() {
        #expect(RecoveryLevel(percentage: 33) == .low)
        #expect(RecoveryLevel(percentage: 34) == .moderate)
        #expect(RecoveryLevel(percentage: 67) == .high)
    }

    @Test(arguments: Mood.allCases)
    func extremeInputsStayInRange(_ mood: Mood) {
        let cases: [Conditions] = [
            conditions(0, hr: 0, resting: nil), conditions(3, hr: 250, resting: 40),
            conditions(23, hr: 250, resting: 0, phase: .fading(1), weather: WeatherInput(kind: .snow, windKph: 200), recovery: .low),
            conditions(12, hr: -5, phase: .closing(2)), conditions(6, phase: .fading(-1)),
        ]
        for c in cases {
            let p = make(mood, c)
            for v in [p.density, p.brightness, p.reverb, p.master, p.bedColour] {
                #expect(v.isFinite && (0...1).contains(v))
            }
            #expect(p.tempo.isFinite && p.tempo > 0)
            #expect(p.barSeconds.isFinite && p.barSeconds > 0)
            for layer in Layer.allCases { #expect((0...1).contains(p.gains[layer.rawValue])) }
        }
    }
}
