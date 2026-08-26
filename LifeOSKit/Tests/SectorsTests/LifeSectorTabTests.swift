import Testing
import Persistence
@testable import Sectors

/// Pins exactly which sectors own a full tab elsewhere in the app, so the
/// answer `LifeBoardScreen` and `RootView` both read cannot drift apart.
@Suite struct LifeSectorTabTests {

    @Test func onlyBodyMoneyAndMissionOwnATab() {
        let owning = LifeSector.allCases.filter(\.ownsTab)
        #expect(Set(owning) == [.body, .money, .mission])
    }

    @Test func theOtherSixSectorsDoNotOwnATab() {
        let notOwning = LifeSector.allCases.filter { !$0.ownsTab }
        #expect(Set(notOwning) == [.family, .romance, .soul, .friends, .growth, .mind])
    }
}
