import Foundation
import SwiftData
import OSLog
import HealthKit
import AppSurfaces
import Integrations

/// Dependency injection container for all app services.
///
/// **Replaces singletons** to enable:
/// - Parallel development (no shared state)
/// - Easy testing (inject mocks)
/// - Multiple instances (multi-account support)
///
/// **Usage in production:**
/// ```swift
/// @State private var services = ServicesContainer()
/// ```
///
/// **Usage in tests:**
/// ```swift
/// let services = ServicesContainer.test(
///     pushService: MockPushService()
/// )
/// ```
@MainActor
final class ServicesContainer {
    
    // MARK: - Services (Injectable)
    
    let pushService: PushServiceProtocol
    let watchBridge: WatchBridgeProtocol
    let surfaceCoordinator: SurfaceCoordinatorProtocol
    
    // MARK: - Initialization
    
    /// Production container with real services.
    init(
        pushService: PushServiceProtocol,
        watchBridge: WatchBridgeProtocol,
        surfaceCoordinator: SurfaceCoordinatorProtocol
    ) {
        self.pushService = pushService
        self.watchBridge = watchBridge
        self.surfaceCoordinator = surfaceCoordinator
    }
    
    /// Convenience init with default production services.
    convenience init() {
        // These would be the actual implementations
        // For now, we'll need to refactor existing singletons
        fatalError("Production services not yet refactored. Use test() for now.")
    }
    
    /// Test container with injectable mocks.
    ///
    /// Example:
    /// ```swift
    /// @Test func pushNotification() async throws {
    ///     let mockPush = MockPushService()
    ///     let services = ServicesContainer.test(
    ///         pushService: mockPush
    ///     )
    ///     
    ///     await services.pushService.refreshInbox()
    ///     #expect(mockPush.refreshCallCount == 1)
    /// }
    /// ```
    static func test(
        pushService: PushServiceProtocol = MockPushService(),
        watchBridge: WatchBridgeProtocol = MockWatchBridge(),
        surfaceCoordinator: SurfaceCoordinatorProtocol = MockSurfaceCoordinator()
    ) -> ServicesContainer {
        ServicesContainer(
            pushService: pushService,
            watchBridge: watchBridge,
            surfaceCoordinator: surfaceCoordinator
        )
    }
}

// MARK: - Push Service Protocol

@MainActor
protocol PushServiceProtocol: AnyObject {
    var pending: NudgePayload? { get set }
    
    func attach(ownerID: String?)
    func refreshInbox() async
    func syncRegistration() async
    func deregister(accessToken: String) async
}

// MARK: - Watch Bridge Protocol

@MainActor
protocol WatchBridgeProtocol: AnyObject {
    var hasSession: Bool { get }
    var placeholderSessionID: UUID? { get }
    
    var onSession: ((HKWorkoutSession) -> Void)? { get set }
    var onPacket: ((Data) -> Void)? { get set }
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)? { get set }
    
    func adopt(_ session: HKWorkoutSession)
    func send(_ command: PhoneCommand, maxHeartRate: Int?)
    func end(after command: PhoneCommand)
    func end()
    func clearPlaceholder()
}

// MARK: - Surface Coordinator Protocol

@MainActor
protocol SurfaceCoordinatorProtocol: AnyObject {
    var pendingRoute: SurfaceRoute? { get set }
    
    func adopt(ownerID: String?, context: ModelContext?)
    func clear()
    func publish()
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct ServicesContainerKey: EnvironmentKey {
    @MainActor static let defaultValue = ServicesContainer.test()
}

extension EnvironmentValues {
    var services: ServicesContainer {
        get { self[ServicesContainerKey.self] }
        set { self[ServicesContainerKey.self] = newValue }
    }
}

extension View {
    /// Provides the services container to this view and its descendants.
    ///
    /// Set once in `AppShell`, access via environment in child views.
    func servicesContainer(_ container: ServicesContainer) -> some View {
        environment(\.services, container)
    }
}
