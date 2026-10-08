import Testing
@testable import Soundscape

@Suite struct MoodRecipeTests {
    @Test(arguments: Mood.allCases)
    func everyRecipeIsWellFormed(_ mood: Mood) {
        let recipe = MoodRecipe.for(mood)
        #expect(recipe.mood == mood)
        #expect(!recipe.scale.isEmpty && recipe.scale.first == 0)
        #expect(recipe.scale.allSatisfy { (0..<12).contains($0) })
        #expect(!recipe.chords.isEmpty)
        #expect(recipe.chords.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 >= 0 } })
        #expect(recipe.barsPerChord.lowerBound >= 1)
        #expect(recipe.tempo.lowerBound > 0)
        for layer in Layer.allCases { #expect((0...1).contains(recipe.gains[layer.rawValue])) }
    }

    @Test func pulsedMoodsHaveABeatAndUnpulsedOnesBreathe() {
        #expect(MoodRecipe.for(.focus).gains[Layer.pulse.rawValue] > 0)
        #expect(MoodRecipe.for(.brainstorm).gains[Layer.pluck.rawValue] > 0)
        #expect(MoodRecipe.for(.relax).breathing == Breathing(inhale: 4, exhale: 6))
        #expect(MoodRecipe.for(.relax).gains[Layer.pulse.rawValue] == 0)
        #expect(MoodRecipe.for(.sleep).breathing != nil)
        #expect(MoodRecipe.for(.sleep).gains[Layer.pulse.rawValue] == 0)
    }

    @Test func tempoRangesMatchTheSpec() {
        #expect(MoodRecipe.for(.focus).tempo == 60...72)
        #expect(MoodRecipe.for(.brainstorm).tempo == 76...92)
    }

    @Test func brainstormIsLydian() {
        #expect(MoodRecipe.for(.brainstorm).scale == [0, 2, 4, 6, 7, 9, 11])
        #expect(MoodRecipe.for(.focus).scale == [0, 2, 4, 7, 9])
    }
}
