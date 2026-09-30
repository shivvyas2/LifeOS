import Foundation
import SwiftData

/// Dependency injection container for third-party integrations.
///
/// Lives in `RootView` and the test suite, nowhere else. Views receive the
/// already-built view models, not this container: DI is a composition concern,
/// not a view concern.
///
/// Built once per app launch, rebuilt in tests with mock stores. Solves three
/// problems the default-argument approach cannot:
/// - Testing with mocks requires rewriting every view model's `init`
/// - Configuration lives scattered across view models rather than in one place
/// - Swapping implementations (e.g., using a different token store) means
///   changing every call site
@MainActor
final class IntegrationContainer {
    // MARK: - Stores (Injectable Dependencies)
    
    let whoopTokenStore: any WhoopTokenStoring
    let fitbitAuthStore: any FitbitAuthStoring
    let authSessionStore: any AuthSessionStoring
    let userDefaults: UserDefaults
    
    // MARK: - View Models (Products)
    
    private(set) lazy var whoop: WhoopConnectionViewModel = {
        WhoopConnectionViewModel(tokens: whoopTokenStore)
    }()
    
    private(set) lazy var fitbit: FitbitConnectionViewModel = {
        FitbitConnectionViewModel(
            pending: fitbitAuthStore,
            sessions: authSessionStore,
            defaults: userDefaults
        )
    }()
    
    private(set) lazy var plaid: PlaidConnectionViewModel = {
        PlaidConnectionViewModel()
    }()
    
    private(set) lazy var health: HealthConnectionViewModel = {
        HealthConnectionViewModel()
    }()
    
    // TODO: Add when OuraConnectionViewModel exists
    // private(set) lazy var oura: OuraConnectionViewModel = { ... }()
    
    // MARK: - Initialization
    
    /// Production container with real keychain and defaults.
    init(
        whoopTokenStore: any WhoopTokenStoring = KeychainWhoopTokenStore(),
        fitbitAuthStore: any FitbitAuthStoring = KeychainFitbitAuthStore(),
        authSessionStore: any AuthSessionStoring = KeychainAuthSessionStore(),
        userDefaults: UserDefaults = .currentAccount
    ) {
        self.whoopTokenStore = whoopTokenStore
        self.fitbitAuthStore = fitbitAuthStore
        self.authSessionStore = authSessionStore
        self.userDefaults = userDefaults
    }
    
    /// Test container with injectable mocks.
    ///
    /// Example:
    /// ```swift
    /// @Test func whoopConnection() async throws {
    ///     let mockTokenStore = MockWhoopTokenStore()
    ///     let container = IntegrationContainer.test(whoopTokenStore: mockTokenStore)
    ///     
    ///     container.whoop.connect()
    ///     #expect(mockTokenStore.savedToken != nil)
    /// }
    /// ```
    static func test(
        whoopTokenStore: any WhoopTokenStoring = MockWhoopTokenStore(),
        fitbitAuthStore: any FitbitAuthStoring = MockFitbitAuthStore(),
        authSessionStore: any AuthSessionStoring = MockAuthSessionStore(),
        userDefaults: UserDefaults = UserDefaults(suiteName: "test")!
    ) -> IntegrationContainer {
        IntegrationContainer(
            whoopTokenStore: whoopTokenStore,
            fitbitAuthStore: fitbitAuthStore,
            authSessionStore: authSessionStore,
            userDefaults: userDefaults
        )
    }
    
    // MARK: - Lifecycle
    
    /// Attaches all integration view models to the given model context.
    func attach(_ context: ModelContext) {
        whoop.attach(context)
        fitbit.attach(context)
        plaid.attach(context)
        health.attach(context)
    }
    
    /// Deactivates all integrations on sign out.
    func deactivateAll() {
        whoop.deactivate()
        fitbit.deactivate()
        plaid.deactivate()
        health.deactivate()
    }
    
    /// Syncs all integrations if needed.
    func syncIfDue() async {
        await whoop.syncIfStale()
        await health.syncIfConnected()
        await fitbit.syncIfDue()
        await plaid.syncIfDue()
    }
    
    /// Resolves stalled connections on foreground.
    func resolveStalled() async {
        await whoop.resolveStalledConnect()
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct IntegrationContainerKey: EnvironmentKey {
    @MainActor static let defaultValue = IntegrationContainer()
}

extension EnvironmentValues {
    var integrations: IntegrationContainer {
        get { self[IntegrationContainerKey.self] }
        set { self[IntegrationContainerKey.self] = newValue }
    }
}

extension View {
    /// Provides the integration container to this view and its descendants.
    ///
    /// Set once in `RootView`, read nowhere: views receive the built view
    /// models directly, not the container.
    func integrationContainer(_ container: IntegrationContainer) -> some View {
        environment(\.integrations, container)
    }
}
