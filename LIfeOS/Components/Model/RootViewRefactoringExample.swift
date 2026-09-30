import AppSurfaces
import SwiftData
import DesignSystem
import Persistence
import Insights
import Integrations
import OSLog

// MARK: - Example: Updated RootView using IntegrationContainer

/// Example showing how to refactor `RootView` to use `IntegrationContainer`.
///
/// Before:
/// ```swift
/// @Bindable var whoop: WhoopConnectionViewModel
/// @Bindable var fitbit: FitbitConnectionViewModel
/// ```
///
/// After:
/// ```swift
/// @State private var integrations = IntegrationContainer()
/// 
/// var body: some View {
///     // Access via container
///     TabView {
///         HealthTab()
///             .environmentObject(integrations.whoop)
///             .environmentObject(integrations.fitbit)
///     }
///     .onAppear {
///         integrations.attach(context)
///     }
/// }
/// ```
///
/// Benefits:
/// - Single source of truth for all integration dependencies
/// - Easy to swap in test doubles
/// - Clear lifecycle management (attach/deactivate)
/// - View models no longer need default arguments in their init

struct RootViewRefactoringExample {
    
    // MARK: Option 1: Minimal Change (Keep Existing API)
    
    /// Keep the same public API but build view models from container internally.
    /// Good for gradual migration.
    struct RootView_V1: View {
        // Still accept view models as parameters for backwards compatibility
        @Bindable var whoop: WhoopConnectionViewModel
        @Bindable var fitbit: FitbitConnectionViewModel
        @Bindable var plaid: PlaidConnectionViewModel
        @Bindable var health: HealthConnectionViewModel
        var onSignOut: () -> Void = {}
        
        @Environment(\.modelContext) private var context
        
        // Parent creates container and passes in the view models:
        // let container = IntegrationContainer()
        // RootView_V1(whoop: container.whoop, fitbit: container.fitbit, ...)
        
        var body: some View {
            Text("Content")
                .onAppear {
                    // View models already attached by parent
                }
        }
    }
    
    // MARK: Option 2: Full DI (Recommended)
    
    /// Accept the container instead of individual view models.
    /// Cleaner API, better encapsulation.
    struct RootView_V2: View {
        let integrations: IntegrationContainer
        @Bindable var plaid: PlaidConnectionViewModel
        @Bindable var health: HealthConnectionViewModel
        var onSignOut: () -> Void = {}
        
        @Environment(\.modelContext) private var context
        
        var body: some View {
            Text("Content")
                .onAppear {
                    integrations.attach(context)
                }
                // Pass view models down as needed
                .sheet(isPresented: .constant(false)) {
                    ConnectionsScreen(
                        model: OnboardingViewModel(),
                        whoop: integrations.whoop,
                        fitbit: integrations.fitbit,
                        health: health,
                        plaid: plaid,
                        onFinish: {}
                    )
                }
        }
    }
    
    // MARK: Option 3: Full Container Ownership
    
    /// Container owns ALL integrations, not just third-party.
    /// Most consistent, but biggest refactor.
    struct RootView_V3: View {
        @State private var integrations = IntegrationContainer()
        var onSignOut: () -> Void = {}
        
        @Environment(\.modelContext) private var context
        
        var body: some View {
            TabView {
                // Pass individual view models to screens
                SettingsScreen(
                    whoop: integrations.whoop,
                    fitbit: integrations.fitbit,
                    onSignOut: onSignOut
                )
            }
            .onAppear {
                integrations.attach(context)
            }
            .onDisappear {
                integrations.deactivateAll()
            }
        }
    }
}

// MARK: - Test Example

import Testing

@Suite("Integration Container Tests")
struct IntegrationContainerTests {
    
    @Test("Whoop connection with mocked token store")
    @MainActor
    func whoopConnectionWithMock() async throws {
        // Arrange: Create container with mock
        let mockTokenStore = MockWhoopTokenStore()
        mockTokenStore.simulateConnected()
        
        let container = IntegrationContainer(whoopTokenStore: mockTokenStore)
        
        // Act: Use the view model
        container.whoop.refreshState()
        
        // Assert: Verify behavior
        #expect(container.whoop.isConnected == true)
        #expect(mockTokenStore.loadCallCount > 0)
    }
    
    @Test("Fitbit connection lifecycle")
    @MainActor
    func fitbitConnectionLifecycle() async throws {
        // Arrange
        let mockAuthStore = MockFitbitAuthStore()
        let container = IntegrationContainer(fitbitAuthStore: mockAuthStore)
        
        // Act: Simulate connecting
        // container.fitbit.connect() // would trigger OAuth
        
        // Deactivate
        container.deactivateAll()
        
        // Assert
        #expect(mockAuthStore.savedPending == nil)
    }
    
    @Test("Integration container provides isolated test instances")
    @MainActor
    func isolatedTestInstances() async throws {
        let container1 = IntegrationContainer.test()
        let container2 = IntegrationContainer.test()
        
        // Each container gets its own view models
        #expect(container1.whoop !== container2.whoop)
        #expect(container1.fitbit !== container2.fitbit)
    }
}
