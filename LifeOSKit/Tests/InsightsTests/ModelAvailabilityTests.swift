import Testing
import FoundationModels
@testable import Insights

@Suite struct ModelAvailabilityTests {

    @Test func anAvailableModelIsAvailable() {
        #expect(ModelAvailability.from(.available) == .available)
    }

    /// Hardware eligibility cannot change while the app is running, so this
    /// is the one answer the router is allowed to remember.
    @Test func anIneligibleDeviceIsPermanentlyUnavailable() {
        #expect(ModelAvailability.from(.unavailable(.deviceNotEligible)) == .unavailablePermanently)
    }

    @Test func appleIntelligenceBeingOffIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.appleIntelligenceNotEnabled)) == .unavailableForNow)
    }

    @Test func aModelStillDownloadingIsWorthReChecking() {
        #expect(ModelAvailability.from(.unavailable(.modelNotReady)) == .unavailableForNow)
    }
}
