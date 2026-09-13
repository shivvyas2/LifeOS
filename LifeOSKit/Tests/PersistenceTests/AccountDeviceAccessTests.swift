import Foundation
import Testing
@testable import Persistence

@Suite struct AccountDeviceAccessTests {
    @Test func systemPermissionDoesNotAuthorizeAnotherAccount() {
        let nameA = "test-access-a-\(UUID())", nameB = "test-access-b-\(UUID())"
        let alice = UserDefaults(suiteName: nameA)!, bob = UserDefaults(suiteName: nameB)!
        defer { alice.removePersistentDomain(forName: nameA); bob.removePersistentDomain(forName: nameB) }
        alice.set(true, forKey: AccountDeviceAccess.calendarKey)
        #expect(AccountDeviceAccess.allowsCalendar(defaults: alice, systemAuthorized: true))
        #expect(!AccountDeviceAccess.allowsCalendar(defaults: bob, systemAuthorized: true))
        #expect(!AccountDeviceAccess.allowsCalendar(defaults: alice, systemAuthorized: false))
        alice.removeObject(forKey: AccountDeviceAccess.calendarKey)
        #expect(!AccountDeviceAccess.allowsCalendar(defaults: alice, systemAuthorized: true))
    }
}
