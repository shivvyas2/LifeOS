import Testing
import Foundation
@testable import Integrations

final class MemoryBeaconKeychain: BeaconKeychain, @unchecked Sendable {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@Suite(.serialized)
struct SharedSignInTests {
    init() { SharedSignIn.accessGroup = "test.group" }

    private func session(_ id: String, expiresIn: TimeInterval) -> AuthSession {
        AuthSession(accessToken: "tok-\(id)", refreshToken: "never-shared", expiresAt: .now.addingTimeInterval(expiresIn),
                    userID: id, phone: nil, email: "\(id)@example.com", hasProfile: true)
    }

    @Test func publishesTheAccessTokenAndNeverTheRefreshToken() throws {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        let raw = String(decoding: try #require(keychain.data), as: UTF8.self)
        #expect(raw.contains("tok-u1"))
        #expect(!raw.contains("never-shared"))
    }

    @Test func ignoresExpiredBeacon() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 90), keychain: keychain)
        // Less than the two minutes a handoff round trip needs.
        #expect(SharedSignIn.current(keychain: keychain) == nil)
    }

    @Test func returnsAFreshBeacon() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain)?.userID == "u1")
        #expect(SharedSignIn.current(keychain: keychain)?.label == "u1@example.com")
    }

    @Test func withdrawOnlyClearsItsOwnAccount() {
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        SharedSignIn.withdraw(userID: "u2", keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain) != nil)
        SharedSignIn.withdraw(userID: "u1", keychain: keychain)
        #expect(SharedSignIn.current(keychain: keychain) == nil)
    }

    @Test func doesNothingWithoutAGroup() {
        SharedSignIn.accessGroup = nil
        defer { SharedSignIn.accessGroup = "test.group" }
        let keychain = MemoryBeaconKeychain()
        SharedSignIn.publish(session("u1", expiresIn: 3600), keychain: keychain)
        #expect(keychain.data == nil)
    }
}
