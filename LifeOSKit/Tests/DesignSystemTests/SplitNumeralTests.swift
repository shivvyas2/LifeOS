import Testing
@testable import DesignSystem

/// The pastel cards show a huge hero figure and a quieter remainder, the way
/// the reference paints "120 / 80". Sleep duration has to split the same way
/// or the hours collapse into a cramped "7h 12m" string.
@Suite struct SplitNumeralTests {
    @Test func aFullNightPutsHoursInTheHero() {
        let split = SplitNumeral.sleep(minutes: 432)
        #expect(split.hero == "7")
        #expect(split.remainder == "h 12m")
    }

    @Test func anExactHourDropsTheZeroMinutes() {
        let split = SplitNumeral.sleep(minutes: 120)
        #expect(split.hero == "2")
        #expect(split.remainder == "h")
    }

    @Test func underAnHourTheMinutesAreTheHero() {
        let split = SplitNumeral.sleep(minutes: 45)
        #expect(split.hero == "45")
        #expect(split.remainder == "m")
    }
}
