import Testing
@testable import DesignSystem

@Suite struct TokensTests {
    @Test func everyModuleHasADistinctHue() {
        let names = Set(ModuleHue.allCases.map(\.rawValue))
        #expect(names.count == ModuleHue.allCases.count)
        #expect(names == ["body", "activity", "recovery", "nutrition", "money", "habits"])
    }
}
