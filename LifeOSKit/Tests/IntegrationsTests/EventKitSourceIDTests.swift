import Testing
import Foundation
@testable import Integrations

@Suite struct EventKitSourceIDTests {
    private let start = Date(timeIntervalSince1970: 1_756_200_000)

    @Test func aRecurringOccurrenceGetsAKeyQualifiedByItsStart() {
        let first = EventKitSource.sourceID(identifier: "ABC", startDate: start, isRecurring: true)
        let second = EventKitSource.sourceID(identifier: "ABC", startDate: start.addingTimeInterval(7 * 86_400), isRecurring: true)
        #expect(first != second)
        #expect(first.hasPrefix("ABC#"))
    }

    @Test func aOneOffEventKeepsItsRawIdentifier() {
        #expect(EventKitSource.sourceID(identifier: "ABC", startDate: start, isRecurring: false) == "ABC")
    }
}
