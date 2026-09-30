import SwiftUI

#if DEBUG
/// Debug screen for toggling feature flags.
///
/// **Access Methods:**
/// - Long press profile avatar 5 times
/// - Shake device to show debug menu
/// - Launch argument: `-showFeatureFlags YES`
///
/// **Usage:**
/// ```swift
/// .sheet(isPresented: $showFeatureFlags) {
///     FeatureFlagsScreen()
/// }
/// ```
struct FeatureFlagsScreen: View {
    @Environment(\.featureFlags) private var flags
    @Environment(\.dismiss) private var dismiss
    
    @State private var showResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                integrationSection
                uiSection
                dataSection
                debugSection
                actionsSection
            }
            .navigationTitle("Feature Flags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset All Flags?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    flags.resetAll()
                }
            } message: {
                Text("This will turn off all feature flags and return to defaults.")
            }
        }
    }
    
    // MARK: - Sections
    
    private var integrationSection: some View {
        Section {
            FlagToggle(
                "Oura Integration",
                systemImage: "circle.fill",
                isOn: Binding(
                    get: { flags.ouraIntegrationEnabled },
                    set: { flags.ouraIntegrationEnabled = $0 }
                ),
                status: "In Development",
                description: "Connect Oura Ring for sleep and recovery data"
            )
            
            FlagToggle(
                "Watch Independent Workouts",
                systemImage: "applewatch",
                isOn: Binding(
                    get: { flags.watchIndependentWorkoutsEnabled },
                    set: { flags.watchIndependentWorkoutsEnabled = $0 }
                ),
                status: "Alpha",
                description: "Start workouts on Apple Watch without iPhone"
            )
            
            FlagToggle(
                "Garmin Integration",
                systemImage: "figure.run",
                isOn: Binding(
                    get: { flags.garminIntegrationEnabled },
                    set: { flags.garminIntegrationEnabled = $0 }
                ),
                status: "Planned",
                description: "Connect Garmin devices"
            )
        } header: {
            Text("Integrations")
        }
    }
    
    private var uiSection: some View {
        Section {
            FlagToggle(
                "3D Money Charts",
                systemImage: "chart.bar.xaxis",
                isOn: Binding(
                    get: { flags.money3DChartsEnabled },
                    set: { flags.money3DChartsEnabled = $0 }
                ),
                status: "Beta",
                description: "New 3D visualization for spending trends"
            )
            
            FlagToggle(
                "Liquid Glass Profile",
                systemImage: "person.crop.circle",
                isOn: Binding(
                    get: { flags.liquidGlassProfileEnabled },
                    set: { flags.liquidGlassProfileEnabled = $0 }
                ),
                status: "Ready for Beta",
                description: "Redesigned profile with modern glass material"
            )
            
            FlagToggle(
                "Social Features",
                systemImage: "person.2.fill",
                isOn: Binding(
                    get: { flags.socialFeaturesEnabled },
                    set: { flags.socialFeaturesEnabled = $0 }
                ),
                status: "In Development",
                description: "Groups, sharing, and leaderboards"
            )
        } header: {
            Text("UI Features")
        }
    }
    
    private var dataSection: some View {
        Section {
            FlagToggle(
                "GraphQL API",
                systemImage: "network",
                isOn: Binding(
                    get: { flags.graphQLAPIEnabled },
                    set: { flags.graphQLAPIEnabled = $0 }
                ),
                status: "Experimental",
                description: "Use new GraphQL API instead of REST"
            )
            
            FlagToggle(
                "Offline Mode",
                systemImage: "wifi.slash",
                isOn: Binding(
                    get: { flags.offlineModeEnabled },
                    set: { flags.offlineModeEnabled = $0 }
                ),
                status: "Planning",
                description: "Local-first architecture for offline usage"
            )
        } header: {
            Text("Data & Backend")
        }
    }
    
    private var debugSection: some View {
        Section {
            FlagToggle(
                "Verbose Logging",
                systemImage: "doc.text",
                isOn: Binding(
                    get: { flags.verboseLoggingEnabled },
                    set: { flags.verboseLoggingEnabled = $0 }
                ),
                status: "Debug",
                description: "Enable detailed logs for all subsystems"
            )
            
            FlagToggle(
                "Mock Data",
                systemImage: "questionmark.folder",
                isOn: Binding(
                    get: { flags.useMockData },
                    set: { flags.useMockData = $0 }
                ),
                status: "Debug",
                description: "Use fake data instead of real API"
            )
            
            FlagToggle(
                "Slow Network",
                systemImage: "tortoise",
                isOn: Binding(
                    get: { flags.simulateSlowNetwork },
                    set: { flags.simulateSlowNetwork = $0 }
                ),
                status: "Debug",
                description: "Add 2s delay to all network requests"
            )
            
            FlagToggle(
                "Data Inspector",
                systemImage: "cylinder",
                isOn: Binding(
                    get: { flags.showDataInspector },
                    set: { flags.showDataInspector = $0 }
                ),
                status: "Debug",
                description: "Show SwiftData model inspector"
            )
        } header: {
            Text("Debug Tools")
        }
    }
    
    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Flags", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.red)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Feature flags allow testing incomplete features without affecting other users.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Flags are stored per-device and persist across app launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Flag Toggle Row

private struct FlagToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let status: String
    let description: String
    
    init(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        status: String,
        description: String
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
        self.status = status
        self.description = description
    }
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(isOn ? .blue : .secondary)
                        .font(.title3)
                    
                    Text(title)
                        .font(.body)
                    
                    Spacer()
                    
                    StatusBadge(status)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: String
    
    init(_ status: String) {
        self.status = status
    }
    
    private var color: Color {
        switch status {
        case "Stable", "Ready for Beta": return .green
        case "Beta": return .blue
        case "Alpha", "In Development": return .orange
        case "Experimental", "Planning": return .purple
        case "Debug": return .gray
        default: return .secondary
        }
    }
    
    var body: some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}

// MARK: - Preview

#Preview {
    FeatureFlagsScreen()
}
#endif
