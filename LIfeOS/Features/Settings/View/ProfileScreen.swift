import SwiftUI
import DesignSystem
import Integrations

/// Account-backed profile state and navigation; presentation is shared with previews.
struct ProfileScreen: View {
    @Bindable var settings: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var fitbit: FitbitConnectionViewModel?
    var health: HealthConnectionViewModel?
    var plaid: PlaidConnectionViewModel?
    var stats: [ProfileStat] = []
    var highlights: [ProfileStat] = []
    var allTime: [ProfileStat] = []
    var socialActivity: SocialActivitySnapshot?
    var onSignOut: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var photo: Data? = ProfilePhotoStore.load()
    @State private var profile = ProfileStore.load()
    @State private var isEditing = false
    @State private var destination: ProfileDestination?

    private enum ProfileDestination: Hashable { case settings, friends, connections }

    var body: some View {
        NavigationStack {
            ProfileOverview(profile: profile, photo: photo, stats: stats,
                            highlights: highlights, allTime: allTime,
                            onEdit: { isEditing = true }, onFriends: { destination = .friends },
                            onConnections: { destination = .connections },
                            onSettings: { destination = .settings })
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
                .navigationDestination(item: $destination) { destination in
                    switch destination {
                    case .friends: SocialHubScreen(activity: socialActivity)
                    case .connections:
                        if let whoop, let fitbit, let health, let plaid {
                            ConnectionsSettingsScreen(whoop: whoop, fitbit: fitbit, health: health, plaid: plaid)
                        } else {
                            settingsScreen
                        }
                    case .settings: settingsScreen
                    }
                }
        }
        .tint(LifeOSTokens.accent)
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet(profile: profile, photo: photo) { newProfile, newPhoto in
                profile = newProfile
                photo = newPhoto
                ProfileStore.save(newProfile)
                ProfilePhotoStore.save(newPhoto)
            }
        }
    }

    private var settingsScreen: some View {
        SettingsScreen(model: settings, whoop: whoop, fitbit: fitbit, health: health, plaid: plaid,
                       onSignOut: onSignOut)
    }
}

struct ProfileStat: Identifiable, Equatable {
    let id: String
    let value: String
    let label: String

    init(_ label: String, _ value: String) {
        self.id = label
        self.label = label
        self.value = value
    }
}
