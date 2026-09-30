import Foundation
import SwiftUI

/// Feature flags for gradual rollout and parallel development.
///
/// **For contributors:**
/// - Add your feature flag here with documentation
/// - Keep it OFF by default until complete
/// - Only enable when tested and reviewed
///
/// **For reviewers:**
/// - Check that new features are gated
/// - Verify flag is documented with owner and issue
/// - Test both ON and OFF states
///
/// **For release managers:**
/// - Gradually enable for beta testers
/// - Monitor crash reports and feedback
/// - Enable for all users when stable
@MainActor
final class FeatureFlags {
    
    /// Singleton for convenience, but can be injected for testing
    static let shared = FeatureFlags()
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Integration Features
    
    /// Oura Ring integration
    ///
    /// **Status:** In Development
    /// **Owner:** TBD
    /// **Issue:** TBD
    /// **Testing:** Enable in debug menu
    var ouraIntegrationEnabled: Bool {
        get { defaults.bool(forKey: "feature.oura.enabled") }
        set { defaults.set(newValue, forKey: "feature.oura.enabled") }
    }
    
    /// Apple Watch independent workouts (without iPhone)
    ///
    /// **Status:** Alpha
    /// **Owner:** TBD
    /// **Issue:** TBD
    /// **Testing:** Requires watchOS 9.0+
    var watchIndependentWorkoutsEnabled: Bool {
        get { defaults.bool(forKey: "feature.watch.independent") }
        set { defaults.set(newValue, forKey: "feature.watch.independent") }
    }
    
    /// Garmin integration
    ///
    /// **Status:** Planned
    /// **Owner:** TBD
    /// **Issue:** TBD
    var garminIntegrationEnabled: Bool {
        get { defaults.bool(forKey: "feature.garmin.enabled") }
        set { defaults.set(newValue, forKey: "feature.garmin.enabled") }
    }
    
    // MARK: - UI Features
    
    /// New money charts with 3D visualization
    ///
    /// **Status:** Beta
    /// **Owner:** TBD
    /// **Issue:** TBD
    /// **Requires:** iOS 18.0+ (Swift Charts 3D)
    var money3DChartsEnabled: Bool {
        get { defaults.bool(forKey: "feature.money.3d-charts") }
        set { defaults.set(newValue, forKey: "feature.money.3d-charts") }
    }
    
    /// Redesigned profile screen with Liquid Glass material
    ///
    /// **Status:** Ready for Beta
    /// **Owner:** TBD
    /// **Issue:** TBD
    /// **Requires:** iOS 18.0+
    var liquidGlassProfileEnabled: Bool {
        get { defaults.bool(forKey: "feature.profile.liquid-glass") }
        set { defaults.set(newValue, forKey: "feature.profile.liquid-glass") }
    }
    
    /// Social features (groups, sharing, leaderboards)
    ///
    /// **Status:** In Development
    /// **Owner:** TBD
    /// **Issue:** TBD
    var socialFeaturesEnabled: Bool {
        get { defaults.bool(forKey: "feature.social.enabled") }
        set { defaults.set(newValue, forKey: "feature.social.enabled") }
    }
    
    // MARK: - Data Features
    
    /// Use new GraphQL API instead of REST
    ///
    /// **Status:** Experimental
    /// **Owner:** TBD
    /// **Issue:** TBD
    /// **Note:** Backend must be deployed first
    var graphQLAPIEnabled: Bool {
        get { defaults.bool(forKey: "feature.api.graphql") }
        set { defaults.set(newValue, forKey: "feature.api.graphql") }
    }
    
    /// Offline mode with local-first architecture
    ///
    /// **Status:** Planning
    /// **Owner:** TBD
    /// **Issue:** TBD
    var offlineModeEnabled: Bool {
        get { defaults.bool(forKey: "feature.offline.enabled") }
        set { defaults.set(newValue, forKey: "feature.offline.enabled") }
    }
    
    // MARK: - Debug Features (Always Available in Debug Builds)
    
    #if DEBUG
    /// Shows feature flags toggle screen
    ///
    /// **Access:** Long press profile avatar 5 times
    var showFeatureFlagsScreen: Bool { true }
    
    /// Enables verbose logging for all subsystems
    var verboseLoggingEnabled: Bool {
        get { defaults.bool(forKey: "debug.verbose-logging") }
        set { defaults.set(newValue, forKey: "debug.verbose-logging") }
    }
    
    /// Uses mock data instead of real API calls
    ///
    /// **Useful for:** UI development without backend
    var useMockData: Bool {
        get { defaults.bool(forKey: "debug.mock-data") }
        set { defaults.set(newValue, forKey: "debug.mock-data") }
    }
    
    /// Simulates slow network (2 second delay on all requests)
    var simulateSlowNetwork: Bool {
        get { defaults.bool(forKey: "debug.slow-network") }
        set { defaults.set(newValue, forKey: "debug.slow-network") }
    }
    
    /// Shows SwiftData model inspector
    var showDataInspector: Bool {
        get { defaults.bool(forKey: "debug.data-inspector") }
        set { defaults.set(newValue, forKey: "debug.data-inspector") }
    }
    #endif
    
    // MARK: - Remote Flags (Server-Controlled)
    
    /// Server-controlled flags (for A/B testing, gradual rollout, kill switches)
    private var remoteFlags: [String: Bool] = [:]
    
    /// Updates remote flags from server response
    ///
    /// Called after successful API handshake with feature flag payload
    func updateRemoteFlags(_ flags: [String: Bool]) {
        remoteFlags = flags
    }
    
    /// Checks if a remote flag is enabled
    ///
    /// Example:
    /// ```swift
    /// if featureFlags.isRemoteEnabled("beta_feature_x") {
    ///     // Show beta feature
    /// }
    /// ```
    func isRemoteEnabled(_ key: String) -> Bool {
        remoteFlags[key] ?? false
    }
    
    // MARK: - Reset
    
    /// Resets all feature flags to default (OFF) state
    ///
    /// **Warning:** Only use this for testing or debugging
    func resetAll() {
        let keys = [
            "feature.oura.enabled",
            "feature.watch.independent",
            "feature.garmin.enabled",
            "feature.money.3d-charts",
            "feature.profile.liquid-glass",
            "feature.social.enabled",
            "feature.api.graphql",
            "feature.offline.enabled",
        ]
        
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        
        #if DEBUG
        defaults.removeObject(forKey: "debug.verbose-logging")
        defaults.removeObject(forKey: "debug.mock-data")
        defaults.removeObject(forKey: "debug.slow-network")
        defaults.removeObject(forKey: "debug.data-inspector")
        #endif
        
        remoteFlags = [:]
    }
}

// MARK: - SwiftUI Environment

private struct FeatureFlagsKey: EnvironmentKey {
    @MainActor static let defaultValue = FeatureFlags.shared
}

extension EnvironmentValues {
    var featureFlags: FeatureFlags {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Conditionally shows view based on feature flag
    ///
    /// Example:
    /// ```swift
    /// OuraConnectionButton()
    ///     .featureGated(\.ouraIntegrationEnabled)
    /// ```
    func featureGated(_ keyPath: KeyPath<FeatureFlags, Bool>) -> some View {
        modifier(FeatureGateModifier(keyPath: keyPath))
    }
    
    /// Shows alternative view when feature is disabled
    ///
    /// Example:
    /// ```swift
    /// NewMoneyCharts()
    ///     .featureGated(\.money3DChartsEnabled) {
    ///         LegacyMoneyCharts()
    ///     }
    /// ```
    func featureGated<FallbackContent: View>(
        _ keyPath: KeyPath<FeatureFlags, Bool>,
        @ViewBuilder fallback: () -> FallbackContent
    ) -> some View {
        modifier(FeatureGateFallbackModifier(keyPath: keyPath, fallback: fallback()))
    }
}

// MARK: - View Modifiers

private struct FeatureGateModifier: ViewModifier {
    let keyPath: KeyPath<FeatureFlags, Bool>
    @Environment(\.featureFlags) private var flags
    
    func body(content: Content) -> some View {
        if flags[keyPath: keyPath] {
            content
        } else {
            EmptyView()
        }
    }
}

private struct FeatureGateFallbackModifier<FallbackContent: View>: ViewModifier {
    let keyPath: KeyPath<FeatureFlags, Bool>
    let fallback: FallbackContent
    @Environment(\.featureFlags) private var flags
    
    func body(content: Content) -> some View {
        if flags[keyPath: keyPath] {
            content
        } else {
            fallback
        }
    }
}
