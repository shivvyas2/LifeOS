import Testing
@testable import Persistence

@Suite struct MoneyPartsTests {
    @Test func aPlainAmountSplitsIntoWholeAndCents() {
        let parts = MoneyParts(1_894.37)
        #expect(parts.whole == 1_894)
        #expect(parts.cents == 37)
        #expect(parts.wholeText == "1,894")
        #expect(parts.centsText == "37")
        #expect(!parts.isNegative)
    }

    @Test func aHalfCentCarriesIntoTheWholeInsteadOfRenderingAsAHundredCents() {
        // The bug this type exists to prevent: 19.995 is "$20.00", never "$19.100".
        let parts = MoneyParts(19.995)
        #expect(parts.whole == 20)
        #expect(parts.cents == 0)
    }

    @Test func nineNinetyNineNineCarriesAllTheWayUp() {
        let parts = MoneyParts(999.999)
        #expect(parts.whole == 1_000)
        #expect(parts.cents == 0)
        #expect(parts.wholeText == "1,000")
    }

    @Test func floatNoiseDoesNotReachTheCents() {
        // 0.1 + 0.2 is 0.30000000000000004 in a Double. It is thirty cents.
        let parts = MoneyParts(0.1 + 0.2)
        #expect(parts.whole == 0)
        #expect(parts.cents == 30)

        // A month of 19.99 charges summed one at a time.
        let month = (0..<30).reduce(0.0) { total, _ in total + 19.99 }
        let summed = MoneyParts(month)
        #expect(summed.whole == 599)
        #expect(summed.cents == 70)
    }

    @Test func singleDigitCentsAreZeroPadded() {
        #expect(MoneyParts(25.05).centsText == "05")
        #expect(MoneyParts(25.5).centsText == "50")
        #expect(MoneyParts(25).centsText == "00")
    }

    @Test func theSignIsCarriedAndZeroIsNeverNegative() {
        let out = MoneyParts(-25.55)
        #expect(out.isNegative)
        #expect(out.whole == 25)
        #expect(out.cents == 55)

        // -0.004 rounds to no cents at all, and "-$0.00" is a lie.
        #expect(!MoneyParts(-0.004).isNegative)
        #expect(!MoneyParts(-0.0).isNegative)
    }

    @Test func amountsThatAreExactInBinaryStayExact() {
        #expect(MoneyParts(6.75).cents == 75)
        #expect(MoneyParts(3_200).whole == 3_200)
        #expect(MoneyParts(3_200).cents == 0)
    }

    @Test func largeBalancesGroupCorrectly() {
        let parts = MoneyParts(48_260.14)
        #expect(parts.wholeText == "48,260")
        #expect(parts.centsText == "14")
    }
}
