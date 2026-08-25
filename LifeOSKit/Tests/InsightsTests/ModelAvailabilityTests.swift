import Testing
import FoundationModels
@testable import Insights

@Suite struct ModelAvailabilityTests {

    @Test func anAvailableModelIsAvailable() {
        #expect(ModelAvailability.from(.available) == .available)
    }

    /// Hardware eligibility cannot change while the app is running, so this
    /// answer is resolved once and cached.
    @Test func anIneligibleDeviceIsPermanentlyUnavailable() {
        #expect(ModelAvailability.from(.unavailable(.deviceNotEligible)) == .unavailablePermanently)
    }

    @Test func appleIntelligenceBeingOffIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.appleIntelligenceNotEnabled)) == .unavailableForNow)
    }

    @Test func aModelStillDownloadingIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.modelNotReady)) == .unavailableForNow)
    }

    @Test func onlyTheTransientCasesAreReChecked() {
        #expect(ModelAvailability.available.isWorthReChecking == false)
        #expect(ModelAvailability.unavailablePermanently.isWorthReChecking == false)
        #expect(ModelAvailability.unavailableForNow.isWorthReChecking == true)
    }
}
