import Foundation
import HealthKit
import SwiftData
import AppSurfaces
import Integrations

/// Mock implementations of app services for testing.
///
/// These mocks track method calls and allow simulation of various scenarios
/// without requiring real network calls, keychain access, or Apple Watch hardware.

// MARK: - Mock Push Service

@MainActor
final class MockPushService: PushServiceProtocol {
    var pending: NudgePayload?
    
    private(set) var attachedOwnerID: String?
    private(set) var refreshCallCount = 0
    private(set) var syncCallCount = 0
    private(set) var deregisterCallCount = 0
    private(set) var deregisteredTokens: [String] = []
    
    func attach(ownerID: String?) {
        attachedOwnerID = ownerID
    }
    
    func refreshInbox() async {
        refreshCallCount += 1
    }
    
    func syncRegistration() async {
        syncCallCount += 1
    }
    
    func deregister(accessToken: String) async {
        deregisterCallCount += 1
        deregisteredTokens.append(accessToken)
    }
    
    /// Test helper: Simulate receiving a nudge
    func simulateNudge(_ nudge: NudgePayload) {
        pending = nudge
    }
    
    /// Test helper: Clear all tracking
    func reset() {
        attachedOwnerID = nil
        refreshCallCount = 0
        syncCallCount = 0
        deregisterCallCount = 0
        deregisteredTokens = []
        pending = nil
    }
}

// MARK: - Mock Watch Bridge

@MainActor
final class MockWatchBridge: WatchBridgeProtocol {
    var hasSession: Bool = false
    var placeholderSessionID: UUID?
    
    var onSession: ((HKWorkoutSession) -> Void)?
    var onPacket: ((Data) -> Void)?
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?
    
    private(set) var adoptedSessions: [HKWorkoutSession] = []
    private(set) var sentCommands: [PhoneCommand] = []
    private(set) var sentMaxHeartRates: [Int?] = []
    private(set) var endCallCount = 0
    private(set) var endAfterCommands: [PhoneCommand] = []
    
    func adopt(_ session: HKWorkoutSession) {
        adoptedSessions.append(session)
        hasSession = true
        onSession?(session)
    }
    
    func send(_ command: PhoneCommand, maxHeartRate: Int? = nil) {
        sentCommands.append(command)
        sentMaxHeartRates.append(maxHeartRate)
    }
    
    func end(after command: PhoneCommand) {
        endAfterCommands.append(command)
        end()
    }
    
    func end() {
        hasSession = false
        endCallCount += 1
    }
    
    func clearPlaceholder() {
        placeholderSessionID = nil
    }
    
    /// Test helper: Simulate receiving a session from watch
    func simulateSessionReceived(_ session: HKWorkoutSession) {
        adopt(session)
    }
    
    /// Test helper: Simulate session state change
    func simulateStateChange(_ state: HKWorkoutSessionState, date: Date = .now) {
        onStateChange?(state, date)
    }
    
    /// Test helper: Simulate receiving data packet from watch
    func simulatePacketReceived(_ data: Data) {
        onPacket?(data)
    }
    
    /// Test helper: Clear all tracking
    func reset() {
        hasSession = false
        placeholderSessionID = nil
        adoptedSessions = []
        sentCommands = []
        sentMaxHeartRates = []
        endCallCount = 0
        endAfterCommands = []
        onSession = nil
        onPacket = nil
        onStateChange = nil
    }
}

// MARK: - Mock Surface Coordinator

@MainActor
final class MockSurfaceCoordinator: SurfaceCoordinatorProtocol {
    var pendingRoute: SurfaceRoute?
    
    private(set) var adoptedOwnerIDs: [String?] = []
    private(set) var adoptCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var publishCallCount = 0
    
    func adopt(ownerID: String?, context: ModelContext?) {
        adoptedOwnerIDs.append(ownerID)
        adoptCallCount += 1
    }
    
    func clear() {
        clearCallCount += 1
        pendingRoute = nil
    }
    
    func publish() {
        publishCallCount += 1
    }
    
    /// Test helper: Simulate deep link route
    func simulateRoute(_ route: SurfaceRoute) {
        pendingRoute = route
    }
    
    /// Test helper: Clear all tracking
    func reset() {
        pendingRoute = nil
        adoptedOwnerIDs = []
        adoptCallCount = 0
        clearCallCount = 0
        publishCallCount = 0
    }
}

// MARK: - Test Fixtures

extension NudgePayload {
    /// Test fixture for push notifications
    static let fixture = NudgePayload(
        text: "Test nudge: You're doing great!",
        trigger: "test",
        day: "2026-09-30"
    )
}

extension PhoneCommand {
    /// Test fixture for watch commands
    static let pauseFixture = PhoneCommand.pause
    static let resumeFixture = PhoneCommand.resume
    static let endFixture = PhoneCommand.end
}
