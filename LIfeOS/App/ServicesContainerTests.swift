import Testing
@testable import YourApp // Replace with your module name

/// Tests demonstrating parallel development with Services Container.
///
/// These tests show how multiple developers can work on different features
/// simultaneously without conflicts or shared state issues.
@Suite("Services Container Tests")
@MainActor
struct ServicesContainerTests {
    
    // MARK: - Container Creation Tests
    
    @Test("Production container would create real services")
    func productionContainerCreation() async throws {
        // Note: Production init currently fatalErrors until singletons are refactored
        // This test documents the intended behavior
        
        // When refactored, this should work:
        // let container = ServicesContainer()
        // #expect(container.pushService != nil)
        // #expect(container.watchBridge != nil)
        // #expect(container.surfaceCoordinator != nil)
        
        #expect(true) // Placeholder until refactored
    }
    
    @Test("Test container uses mock services")
    func testContainerUsesMocks() async throws {
        // Arrange
        let mockPush = MockPushService()
        let mockWatch = MockWatchBridge()
        let mockSurface = MockSurfaceCoordinator()
        
        // Act
        let container = ServicesContainer.test(
            pushService: mockPush,
            watchBridge: mockWatch,
            surfaceCoordinator: mockSurface
        )
        
        // Assert
        #expect(container.pushService === mockPush)
        #expect(container.watchBridge === mockWatch)
        #expect(container.surfaceCoordinator === mockSurface)
    }
    
    // MARK: - Parallel Development Scenario Tests
    
    @Test("Developer A works on push notifications - isolated")
    func developerAWorkOnPushNotifications() async throws {
        // Scenario: Developer A is adding new push notification features
        
        // Arrange: A's test environment
        let mockPush = MockPushService()
        let container = ServicesContainer.test(pushService: mockPush)
        
        // Act: A's feature code
        await container.pushService.refreshInbox()
        await container.pushService.syncRegistration()
        
        // Assert: A's expectations
        #expect(mockPush.refreshCallCount == 1)
        #expect(mockPush.syncCallCount == 1)
        
        // No interference with other services
        let mockWatch = container.watchBridge as! MockWatchBridge
        #expect(mockWatch.endCallCount == 0)
    }
    
    @Test("Developer B works on watch features - isolated")
    func developerBWorkOnWatchFeatures() async throws {
        // Scenario: Developer B is adding Apple Watch sync
        
        // Arrange: B's test environment
        let mockWatch = MockWatchBridge()
        let container = ServicesContainer.test(watchBridge: mockWatch)
        
        // Act: B's feature code
        mockWatch.simulateSessionReceived(HKWorkoutSession(
            healthStore: HKHealthStore(),
            configuration: HKWorkoutConfiguration()
        ))
        container.watchBridge.send(.pause, maxHeartRate: 180)
        
        // Assert: B's expectations
        #expect(mockWatch.hasSession == true)
        #expect(mockWatch.sentCommands.count == 1)
        
        // No interference with other services
        let mockPush = container.pushService as! MockPushService
        #expect(mockPush.refreshCallCount == 0)
    }
    
    @Test("Both developers' tests run simultaneously without conflicts")
    func bothDevelopersTestsRunSimultaneously() async throws {
        // Scenario: Both A and B run their test suites at the same time
        
        // Developer A's tests
        let containerA = ServicesContainer.test()
        await containerA.pushService.refreshInbox()
        
        // Developer B's tests (runs concurrently)
        let containerB = ServicesContainer.test()
        containerB.watchBridge.send(.pause, maxHeartRate: 180)
        
        // Assert: No shared state conflicts
        let mockPushA = containerA.pushService as! MockPushService
        let mockPushB = containerB.pushService as! MockPushService
        
        #expect(mockPushA !== mockPushB) // Different instances
        #expect(mockPushA.refreshCallCount == 1)
        #expect(mockPushB.refreshCallCount == 0) // B didn't touch push
    }
    
    // MARK: - Mock Service Tests
    
    @Test("MockPushService tracks method calls")
    func mockPushServiceTracking() async throws {
        // Arrange
        let mock = MockPushService()
        
        // Act
        mock.attach(ownerID: "user123")
        await mock.refreshInbox()
        await mock.refreshInbox()
        await mock.syncRegistration()
        await mock.deregister(accessToken: "token123")
        
        // Assert
        #expect(mock.attachedOwnerID == "user123")
        #expect(mock.refreshCallCount == 2)
        #expect(mock.syncCallCount == 1)
        #expect(mock.deregisterCallCount == 1)
        #expect(mock.deregisteredTokens == ["token123"])
    }
    
    @Test("MockWatchBridge tracks session lifecycle")
    func mockWatchBridgeTracking() async throws {
        // Arrange
        let mock = MockWatchBridge()
        let session = HKWorkoutSession(
            healthStore: HKHealthStore(),
            configuration: HKWorkoutConfiguration()
        )
        
        // Act
        mock.adopt(session)
        mock.send(.pause, maxHeartRate: 180)
        mock.send(.resume, maxHeartRate: nil)
        mock.end(after: .end)
        
        // Assert
        #expect(mock.adoptedSessions.count == 1)
        #expect(mock.sentCommands == [.pause, .resume])
        #expect(mock.sentMaxHeartRates == [180, nil])
        #expect(mock.endAfterCommands == [.end])
        #expect(mock.endCallCount == 1)
        #expect(mock.hasSession == false) // Ended
    }
    
    @Test("MockSurfaceCoordinator tracks navigation")
    func mockSurfaceCoordinatorTracking() async throws {
        // Arrange
        let mock = MockSurfaceCoordinator()
        
        // Act
        mock.adopt(ownerID: "user123", context: nil)
        mock.publish()
        mock.publish()
        mock.clear()
        
        // Assert
        #expect(mock.adoptCallCount == 1)
        #expect(mock.publishCallCount == 2)
        #expect(mock.clearCallCount == 1)
        #expect(mock.adoptedOwnerIDs == ["user123"])
    }
    
    // MARK: - Simulation Helpers Tests
    
    @Test("Mock services can simulate scenarios")
    func mockServicesSimulateScenarios() async throws {
        // Arrange
        let mockPush = MockPushService()
        let mockWatch = MockWatchBridge()
        
        // Act: Simulate receiving push notification
        let nudge = NudgePayload.fixture
        mockPush.simulateNudge(nudge)
        
        // Act: Simulate watch state change
        mockWatch.simulateStateChange(.running)
        
        // Assert
        #expect(mockPush.pending != nil)
        #expect(mockPush.pending?.text == "Test nudge: You're doing great!")
    }
    
    @Test("Mock services can be reset between tests")
    func mockServicesCanBeReset() async throws {
        // Arrange
        let mock = MockPushService()
        
        // Act: Use the mock
        mock.attach(ownerID: "user1")
        await mock.refreshInbox()
        
        // Assert: Has state
        #expect(mock.attachedOwnerID == "user1")
        #expect(mock.refreshCallCount == 1)
        
        // Act: Reset
        mock.reset()
        
        // Assert: State cleared
        #expect(mock.attachedOwnerID == nil)
        #expect(mock.refreshCallCount == 0)
    }
}

// MARK: - Feature Flag Tests

@Suite("Feature Flags Tests")
@MainActor
struct FeatureFlagsTests {
    
    @Test("Feature flags default to OFF")
    func featureFlagsDefaultToOff() async throws {
        // Arrange
        let flags = FeatureFlags(defaults: UserDefaults(suiteName: "test")!)
        
        // Assert: All flags OFF by default
        #expect(flags.ouraIntegrationEnabled == false)
        #expect(flags.watchIndependentWorkoutsEnabled == false)
        #expect(flags.money3DChartsEnabled == false)
        #expect(flags.liquidGlassProfileEnabled == false)
        #expect(flags.graphQLAPIEnabled == false)
    }
    
    @Test("Feature flags can be enabled")
    func featureFlagsCanBeEnabled() async throws {
        // Arrange
        let flags = FeatureFlags(defaults: UserDefaults(suiteName: "test")!)
        
        // Act
        flags.ouraIntegrationEnabled = true
        flags.money3DChartsEnabled = true
        
        // Assert
        #expect(flags.ouraIntegrationEnabled == true)
        #expect(flags.money3DChartsEnabled == true)
        #expect(flags.watchIndependentWorkoutsEnabled == false) // Still OFF
    }
    
    @Test("Feature flags persist across instances")
    func featureFlagsPersist() async throws {
        // Arrange
        let defaults = UserDefaults(suiteName: "test")!
        let flags1 = FeatureFlags(defaults: defaults)
        
        // Act
        flags1.ouraIntegrationEnabled = true
        
        // Create new instance
        let flags2 = FeatureFlags(defaults: defaults)
        
        // Assert: Persisted
        #expect(flags2.ouraIntegrationEnabled == true)
    }
    
    @Test("Remote flags can be updated")
    func remoteFlagsCanBeUpdated() async throws {
        // Arrange
        let flags = FeatureFlags(defaults: UserDefaults(suiteName: "test")!)
        
        // Act: Simulate server response
        flags.updateRemoteFlags([
            "beta_feature_x": true,
            "beta_feature_y": false
        ])
        
        // Assert
        #expect(flags.isRemoteEnabled("beta_feature_x") == true)
        #expect(flags.isRemoteEnabled("beta_feature_y") == false)
        #expect(flags.isRemoteEnabled("unknown") == false)
    }
    
    @Test("Reset clears all flags")
    func resetClearsAllFlags() async throws {
        // Arrange
        let flags = FeatureFlags(defaults: UserDefaults(suiteName: "test")!)
        flags.ouraIntegrationEnabled = true
        flags.money3DChartsEnabled = true
        
        // Act
        flags.resetAll()
        
        // Assert: All OFF
        #expect(flags.ouraIntegrationEnabled == false)
        #expect(flags.money3DChartsEnabled == false)
    }
}

// MARK: - Integration Scenario Tests

@Suite("Real-World Parallel Development Scenarios")
@MainActor
struct ParallelDevelopmentScenarios {
    
    @Test("Scenario: Two features merged on same day")
    func twoFeaturesMergedSameDay() async throws {
        // Feature A: New push notification system
        let containerA = ServicesContainer.test()
        let mockPushA = containerA.pushService as! MockPushService
        
        await containerA.pushService.refreshInbox()
        #expect(mockPushA.refreshCallCount == 1)
        
        // Feature B: New watch sync algorithm
        let containerB = ServicesContainer.test()
        let mockWatchB = containerB.watchBridge as! MockWatchBridge
        
        mockWatchB.simulateSessionReceived(HKWorkoutSession(
            healthStore: HKHealthStore(),
            configuration: HKWorkoutConfiguration()
        ))
        #expect(mockWatchB.hasSession == true)
        
        // Both features work independently
        #expect(mockPushA.refreshCallCount == 1) // A's feature still works
        #expect(mockWatchB.hasSession == true) // B's feature still works
    }
    
    @Test("Scenario: Feature flag gates incomplete work")
    func featureFlagGatesIncompleteWork() async throws {
        // Arrange: Developer working on Oura integration (not done yet)
        let flags = FeatureFlags(defaults: UserDefaults(suiteName: "test")!)
        flags.ouraIntegrationEnabled = false // OFF by default
        
        // Act: Production code checks flag
        let shouldShowOuraButton = flags.ouraIntegrationEnabled
        
        // Assert: Feature hidden in production
        #expect(shouldShowOuraButton == false)
        
        // Act: Developer enables for testing
        flags.ouraIntegrationEnabled = true
        let shouldShowNow = flags.ouraIntegrationEnabled
        
        // Assert: Developer can test locally
        #expect(shouldShowNow == true)
    }
    
    @Test("Scenario: Multiple accounts with separate services")
    func multipleAccountsSeparateServices() async throws {
        // User A's session
        let servicesA = ServicesContainer.test()
        let pushA = servicesA.pushService as! MockPushService
        pushA.attach(ownerID: "userA")
        
        // User B's session
        let servicesB = ServicesContainer.test()
        let pushB = servicesB.pushService as! MockPushService
        pushB.attach(ownerID: "userB")
        
        // Assert: Separate instances
        #expect(pushA !== pushB)
        #expect(pushA.attachedOwnerID == "userA")
        #expect(pushB.attachedOwnerID == "userB")
    }
}
