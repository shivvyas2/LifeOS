import Foundation
import SwiftData
import Integrations
import Persistence

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
    let githubTokens: any GitHubTokenStoring
    let googleTokens: any GoogleTokenStoring
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
    
    private(set) lazy var github: GitHubConnectionViewModel = {
        GitHubConnectionViewModel(tokens: githubTokens, sessions: authSessionStore, defaults: userDefaults)
    }()

    private(set) lazy var gmail: GmailConnectionViewModel = {
        GmailConnectionViewModel(tokens: googleTokens, defaults: userDefaults)
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
        githubTokens: any GitHubTokenStoring = KeychainGitHubTokenStore(),
        googleTokens: any GoogleTokenStoring = KeychainGoogleTokenStore(),
        authSessionStore: any AuthSessionStoring = KeychainAuthSessionStore(),
        userDefaults: UserDefaults = .currentAccount
    ) {
        self.whoopTokenStore = whoopTokenStore
        self.fitbitAuthStore = fitbitAuthStore
        self.githubTokens = githubTokens
        self.googleTokens = googleTokens
        self.authSessionStore = authSessionStore
        self.userDefaults = userDefaults
    }
    
    /// Test container with in-memory stores.
    static func test(
        whoopTokenStore: any WhoopTokenStoring = InMemoryWhoopTokenStore(),
        fitbitAuthStore: any FitbitAuthStoring = InMemoryFitbitAuthStore(),
        githubTokens: any GitHubTokenStoring = InMemoryGitHubTokenStore(),
        googleTokens: any GoogleTokenStoring = InMemoryGoogleTokenStore(),
        authSessionStore: any AuthSessionStoring = InMemoryAuthSessionStore(),
        userDefaults: UserDefaults = UserDefaults(suiteName: "test")!
    ) -> IntegrationContainer {
        IntegrationContainer(
            whoopTokenStore: whoopTokenStore,
            fitbitAuthStore: fitbitAuthStore,
            githubTokens: githubTokens,
            googleTokens: googleTokens,
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
        github.deactivate()
        gmail.deactivate()
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
