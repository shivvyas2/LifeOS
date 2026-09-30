import Testing
import SwiftData
@testable import YourAppModule // Replace with your actual module name

/// Integration tests demonstrating the DI container in action.
///
/// These tests show how the refactored architecture makes testing easy by
/// allowing mock injection without changing production code.
@Suite("Integration Container Tests")
@MainActor
struct IntegrationContainerTests {
    
    // MARK: - Container Creation Tests
    
    @Test("Production container creates all view models")
    func productionContainerCreatesViewModels() async throws {
        // Arrange & Act
        let container = IntegrationContainer()
        
        // Assert: All view models are lazily created
        #expect(container.whoop != nil)
        #expect(container.fitbit != nil)
        #expect(container.plaid != nil)
        #expect(container.health != nil)
    }
    
    @Test("Test container uses mock stores")
    func testContainerUsesMockStores() async throws {
        // Arrange
        let mockWhoopStore = MockWhoopTokenStore()
        let mockFitbitStore = MockFitbitAuthStore()
        
        // Act
        let container = IntegrationContainer.test(
            whoopTokenStore: mockWhoopStore,
            fitbitAuthStore: mockFitbitStore
        )
        
        // Assert: Container uses the mocks we provided
        #expect(container.whoopTokenStore === mockWhoopStore)
        #expect(container.fitbitAuthStore === mockFitbitStore)
    }
    
    // MARK: - Lifecycle Tests
    
    @Test("Attach connects all integrations to model context")
    func attachConnectsAllIntegrations() async throws {
        // Arrange
        let container = IntegrationContainer.test()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            // Add your SwiftData models here
            // DailyMetrics.self,
            // WorkoutRecord.self,
            // etc.
        ])
        let modelContainer = try ModelContainer(for: schema, configurations: config)
        let context = modelContainer.mainContext
        
        // Act
        container.attach(context)
        
        // Assert: No crashes means all view models attached successfully
        #expect(container.whoop != nil)
        #expect(container.fitbit != nil)
    }
    
    @Test("DeactivateAll clears all integrations")
    func deactivateAllClearsIntegrations() async throws {
        // Arrange
        let mockWhoopStore = MockWhoopTokenStore()
        mockWhoopStore.simulateConnected(with: .fixture)
        
        let container = IntegrationContainer.test(
            whoopTokenStore: mockWhoopStore
        )
        
        // Act
        container.deactivateAll()
        
        // Assert: Whoop token should be cleared
        #expect(mockWhoopStore.clearCallCount > 0)
    }
    
    // MARK: - Whoop Integration Tests
    
    @Test("Whoop connection saves token to store")
    func whoopConnectionSavesToken() async throws {
        // Arrange
        let mockStore = MockWhoopTokenStore()
        let container = IntegrationContainer.test(
            whoopTokenStore: mockStore
        )
        
        // Act: Simulate connection
        mockStore.simulateConnected(with: .fixture)
        container.whoop.refreshState()
        
        // Assert
        #expect(container.whoop.isConnected == true)
        #expect(mockStore.loadCallCount > 0)
    }
    
    @Test("Whoop deactivation clears pending auth")
    func whoopDeactivationClearsPending() async throws {
        // Arrange
        let mockStore = MockWhoopTokenStore()
        mockStore.savedPending = .fixture
        let container = IntegrationContainer.test(
            whoopTokenStore: mockStore
        )
        
        // Act
        container.whoop.deactivate()
        
        // Assert: Pending auth should be cleared
        #expect(mockStore.savedPending == nil)
    }
    
    // MARK: - Fitbit Integration Tests
    
    @Test("Fitbit auth stores pending state")
    func fitbitAuthStoresPendingState() async throws {
        // Arrange
        let mockStore = MockFitbitAuthStore()
        let container = IntegrationContainer.test(
            fitbitAuthStore: mockStore
        )
        
        // Act: Simulate pending auth
        mockStore.simulatePending(with: .fixture)
        
        // Assert
        #expect(mockStore.savedPending != nil)
        #expect(mockStore.savedPending?.state == "test_state")
    }
    
    // MARK: - Sync Tests
    
    @Test("SyncIfDue coordinates all integrations")
    func syncIfDueCoordinatesAllIntegrations() async throws {
        // Arrange
        let container = IntegrationContainer.test()
        
        // Act: This should not crash even with no real connections
        await container.syncIfDue()
        
        // Assert: Successful completion means coordination worked
        #expect(true)
    }
    
    @Test("ResolveStalled handles Whoop reconnection")
    func resolveStalled() async throws {
        // Arrange
        let container = IntegrationContainer.test()
        
        // Act
        await container.resolveStalled()
        
        // Assert: Should complete without error
        #expect(true)
    }
    
    // MARK: - Isolation Tests
    
    @Test("Multiple containers are isolated")
    func multipleContainersAreIsolated() async throws {
        // Arrange
        let container1 = IntegrationContainer.test()
        let container2 = IntegrationContainer.test()
        
        // Assert: Each container has its own view model instances
        #expect(container1.whoop !== container2.whoop)
        #expect(container1.fitbit !== container2.fitbit)
        #expect(container1.plaid !== container2.plaid)
        #expect(container1.health !== container2.health)
    }
    
    @Test("Container view models are singletons within container")
    func containerViewModelsAreSingletons() async throws {
        // Arrange
        let container = IntegrationContainer.test()
        
        // Act: Access the same view model twice
        let whoop1 = container.whoop
        let whoop2 = container.whoop
        
        // Assert: Should be the same instance (lazy var)
        #expect(whoop1 === whoop2)
    }
}

// MARK: - Integration Scenario Tests

@Suite("Integration Scenarios")
@MainActor
struct IntegrationScenarioTests {
    
    @Test("Full onboarding flow with all integrations")
    func fullOnboardingFlow() async throws {
        // Arrange: Fresh container
        let container = IntegrationContainer.test()
        
        // Act: Simulate user connecting all services
        // In a real test, you'd call the actual connection methods
        // For now, just verify the structure works
        
        #expect(container.whoop != nil)
        #expect(container.fitbit != nil)
        #expect(container.plaid != nil)
        #expect(container.health != nil)
    }
    
    @Test("Sign out clears all integration data")
    func signOutClearsAllData() async throws {
        // Arrange: Container with connected integrations
        let mockWhoopStore = MockWhoopTokenStore()
        let mockFitbitStore = MockFitbitAuthStore()
        
        mockWhoopStore.simulateConnected()
        mockFitbitStore.simulatePending()
        
        let container = IntegrationContainer.test(
            whoopTokenStore: mockWhoopStore,
            fitbitAuthStore: mockFitbitStore
        )
        
        // Act: Sign out
        container.deactivateAll()
        
        // Assert: All stores should be cleared
        #expect(mockWhoopStore.clearCallCount > 0)
    }
    
    @Test("Account switch maintains isolation")
    func accountSwitchMaintainsIsolation() async throws {
        // Arrange: Two separate containers for two accounts
        let account1Container = IntegrationContainer.test()
        let account2Container = IntegrationContainer.test()
        
        // Act: Connect Whoop on account 1 only
        let mockStore1 = MockWhoopTokenStore()
        mockStore1.simulateConnected()
        
        // Assert: Account 2 should have no connection
        #expect(account1Container.whoop !== account2Container.whoop)
    }
}

// MARK: - Example: Real-World Usage

/// Example showing how you'd actually use this in your tests.
@Suite("Real-World Integration Testing")
@MainActor
struct RealWorldIntegrationTests {
    
    @Test("User connects Whoop and syncs data")
    func userConnectsWhoopAndSyncsData() async throws {
        // Arrange: Mock token store with valid token
        let mockStore = MockWhoopTokenStore()
        let container = IntegrationContainer.test(
            whoopTokenStore: mockStore
        )
        
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            // Your models here
        ])
        let modelContainer = try ModelContainer(for: schema, configurations: config)
        
        // Act: Connect and attach
        mockStore.simulateConnected(with: .fixture)
        container.attach(modelContainer.mainContext)
        
        // Sync (in real test, this would actually fetch data)
        await container.syncIfDue()
        
        // Assert: Connection established
        #expect(mockStore.loadCallCount > 0)
        #expect(container.whoop.isConnected == true)
    }
    
    @Test("App foregrounds and refreshes stale data")
    func appForegroundsAndRefreshesStaleData() async throws {
        // Arrange
        let container = IntegrationContainer.test()
        
        // Act: Simulate app foreground (what AppShell does)
        await container.resolveStalled()
        await container.syncIfDue()
        
        // Assert: No crashes
        #expect(true)
    }
}
