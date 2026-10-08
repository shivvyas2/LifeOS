import Testing
import Foundation
@testable import Soundscape

@Suite struct FocusSetupTests {
    @Test func presetsMatchTheSpec() {
        #expect(Mood.focus.presets.map(\.id) == ["25-5", "50-10", "90-20"])
        #expect(Mood.brainstorm.presets.map(\.id) == ["25-5", "50-10", "90-20"])
        #expect(Mood.relax.presets.map(\.id) == ["10", "20", "30", "open"])
        #expect(Mood.sleep.presets.map(\.id) == ["15", "30", "60", "night"])
    }

    @Test func theDefaultFocusIsTwentyFiveFiveFourTimes() {
        let setup = FocusSetup.standard(for: .focus)
        #expect(setup.plan == .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: 4))
        #expect(setup.source == .soundscape && setup.texture == .auto)
    }

    @Test func plansFollowThePresetAndBlocks() {
        var setup = FocusSetup.standard(for: .brainstorm)
        setup.presetID = "90-20"; setup.blocks = nil
        #expect(setup.plan == .pomodoro(work: 5400, rest: 1200, longRest: 1800, longEvery: 4, blocks: nil))
        #expect(FocusSetup(mood: .relax, presetID: "open").plan == .countdown(nil))
        #expect(FocusSetup(mood: .relax, presetID: "20").plan == .countdown(1200))
        #expect(FocusSetup(mood: .sleep, presetID: "night").plan == .fade(nil))
        #expect(FocusSetup(mood: .sleep, presetID: "60").plan == .fade(3600))
    }

    @Test func anUnknownPresetFallsBackToTheMoodsDefault() {
        #expect(FocusSetup(mood: .sleep, presetID: "25-5").plan == .fade(1800))
    }

    @Test func preferencesRememberEachMoodAndTheLastOne() {
        let defaults = UserDefaults(suiteName: "FocusSetupTests-\(UUID())")!
        var prefs = FocusPreferences.load(from: defaults, key: "focus")
        #expect(prefs.lastMood == .focus)
        prefs.remember(FocusSetup(mood: .sleep, source: .appleMusic, presetID: "60", texture: .rain))
        prefs.save(to: defaults, key: "focus")
        let back = FocusPreferences.load(from: defaults, key: "focus")
        #expect(back.lastMood == .sleep)
        #expect(back.setup(for: .sleep).presetID == "60")
        #expect(back.setup(for: .sleep).texture == .rain)
        #expect(back.setup(for: .focus) == .standard(for: .focus))
    }

    @Test func appleMusicFallsBackWithANotice() {
        let ok = resolveSource(.appleMusic, music: .available)
        #expect(ok.source == .appleMusic && ok.notice == nil)
        let none = resolveSource(.appleMusic, music: .notSubscribed)
        #expect(none.source == .soundscape && none.notice == "Apple Music needs a subscription. Playing a soundscape instead.")
        let denied = resolveSource(.appleMusic, music: .denied)
        #expect(denied.source == .soundscape && denied.notice == "Allow Apple Music for Almanac in Settings. Playing a soundscape instead.")
        #expect(resolveSource(.appleMusic, music: .unknown).source == .soundscape)
        let silent = resolveSource(.silence, music: .denied)
        #expect(silent.source == .silence && silent.notice == nil)
    }
}
