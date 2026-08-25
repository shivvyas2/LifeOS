import Testing
@testable import DesignSystem

@Suite struct TokensTests {
    @Test func everyModuleHasADistinctHue() {
        let names = Set(ModuleHue.allCases.map(\.rawValue))
        #expect(names.count == ModuleHue.allCases.count)
        #expect(names == ["body", "activity", "recovery", "nutrition", "money", "habits"])
    }

    @Test func pastelHuesAreDefinedAndDistinctFromSaturated() {
        for hue in ModuleHue.allCases {
            #expect(hue.pastel != hue.top)
            #expect(hue.pastelDark != hue.darkTop)
        }
    }

    @Test func alertColorsDifferByScheme() {
        #expect(LifeOSTokens.alertBackground.resolve(.light) != LifeOSTokens.alertBackground.resolve(.dark))
        #expect(LifeOSTokens.alertText.resolve(.light) != LifeOSTokens.alertText.resolve(.dark))
    }

    /// The plus used to paint a white glyph on `primaryText`. In dark mode
    /// `primaryText` is itself near-white, so the button vanished. Fill and
    /// glyph have to stay opposite in both schemes.
    @Test func fabFillAndGlyphStayOppositeInBothSchemes() {
        #expect(LifeOSTokens.fabFill.resolve(.light) != LifeOSTokens.fabGlyph.resolve(.light))
        #expect(LifeOSTokens.fabFill.resolve(.dark) != LifeOSTokens.fabGlyph.resolve(.dark))
        #expect(LifeOSTokens.fabFill.resolve(.light) != LifeOSTokens.fabFill.resolve(.dark))
    }
}
