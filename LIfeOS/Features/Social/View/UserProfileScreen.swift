import SwiftUI
import Integrations
import DesignSystem

struct UserProfileScreen: View {
    @State var profile: SocialProfile
    @State private var photo: Data?
    @State private var relationship: Friendship?
    @State private var stats: SharedStats?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var chat = false
    @State private var removing = false
    private var mine: Bool { SocialSession.current?.userID.lowercased() == profile.id.uuidString.lowercased() }
    private var incoming: Bool { relationship?.addressee.uuidString.lowercased() == SocialSession.current?.userID.lowercased() }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ProfilePhotoBackdrop(photo: photo, showsPortrait: proxy.size.width < 760)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if proxy.size.width >= 760, let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 260, height: 300, alignment: .top)
                                .clipShape(RoundedRectangle(cornerRadius: 24)).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(height: min(320, proxy.size.width * 0.7))
                                .overlay { if photo == nil { Image(systemName: "person.crop.circle").font(.system(size: 88, weight: .ultraLight)).opacity(0.7) } }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(profile.displayName).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                            if let country = profile.country, let title = Locale.current.localizedString(forRegionCode: country) {
                                Label(title, systemImage: "globe").lifeOSText(.secondary).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        if let error { SocialNotice(message: error) { Task { await load() } } }
                        if loading { ProgressView() } else { actions }
                        if let stats, stats.hasFigures {
                            SocialPanel {
                                VStack(alignment: .leading, spacing: 18) {
                                    Label("Shared with friends", systemImage: "person.2").font(.headline)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], spacing: 20) {
                                        if let value = stats.streak { stat("Day streak", value) }
                                        if let value = stats.daysTracked { stat("Days tracked", value) }
                                        if let value = stats.workouts { stat("Workouts", value) }
                                    }
                                }
                            }
                        } else {
                            Label("Activity appears here when shared with you.", systemImage: "lock")
                                .lifeOSText(.secondary).foregroundStyle(.white.opacity(0.8))
                        }
                    }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
                }.refreshable { await load() }
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark).tint(LifeOSTokens.accent)
        .toolbarBackground(.hidden, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $chat) { FriendChatScreen(friend: profile) }
        .task { await load() }
        .confirmationDialog("Remove \(profile.displayName) as a friend?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) { Task { await change(.remove) } }
        } message: { Text("You’ll need to become friends again to send new direct messages.") }
    }

    @ViewBuilder private var actions: some View {
        if mine {
            Text("This is how your profile appears to others. Edit your details from your own profile.").lifeOSText(.secondary).foregroundStyle(.secondary)
        } else if relationship?.status == .accepted {
            Button { chat = true } label: { Label("Message", systemImage: "bubble.left").font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
            Button("Remove friend", role: .destructive) { removing = true }.lifeOSText(.secondary).frame(minHeight: 44).disabled(busy)
        } else if relationship != nil {
            if incoming {
                HStack {
                    Button("Decline") { Task { await change(.remove) } }.buttonStyle(.bordered)
                    Spacer()
                    Button("Accept request") { Task { await change(.accept) } }.buttonStyle(.borderedProminent)
                }.disabled(busy)
            } else {
                SocialPanel {
                    HStack { Label("Request sent", systemImage: "checkmark"); Spacer(); Button("Cancel") { Task { await change(.remove) } }.disabled(busy) }
                }
            }
        } else {
            Button { Task { await change(.add) } } label: {
                Label("Add friend", systemImage: "person.badge.plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).disabled(busy || error != nil)
            Text("Once they accept, you can message and invite them to groups.").lifeOSText(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value.formatted()).font(.title.bold()).monospacedDigit()
            Text(title).lifeOSText(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let api = SocialSession.people, let session = SocialSession.current else {
            loading = false; error = "Sign in to view this profile."; return
        }
        do {
            let rows = try await api.profiles(ids: [profile.id], accessToken: session.accessToken)
            guard SocialSession.current?.userID == session.userID else { return }
            guard let fresh = rows.first else { error = "This profile is no longer available."; loading = false; return }
            profile = fresh
            let relationships = try await api.friendships(accessToken: session.accessToken)
            relationship = relationships.first { $0.requester == profile.id || $0.addressee == profile.id }
            if let api = SocialSession.stats {
                let result = try await api.stats(ids: [profile.id], accessToken: session.accessToken)
                stats = result[profile.id]
            }
            photo = nil
            if let path = profile.avatarPath, let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
                photo = try? await ProfileClient(baseURL: url, anonKey: key).downloadAvatar(path: path, accessToken: session.accessToken)
            }
            error = nil
        } catch { self.error = SocialSession.reason(error) }
        loading = false
    }
    private enum Change { case add, accept, remove }
    private func change(_ action: Change) async {
        guard !busy, let api = SocialSession.people, let session = SocialSession.current, let user = UUID(uuidString: session.userID) else { return }
        busy = true; defer { busy = false }
        do {
            switch action {
            case .add: try await api.request(from: user, to: profile.id, accessToken: session.accessToken)
            case .accept: if let relationship { try await api.accept(friendshipID: relationship.id, accessToken: session.accessToken) }
            case .remove: if let relationship { try await api.remove(friendshipID: relationship.id, accessToken: session.accessToken) }
            }
            await load()
        } catch { self.error = SocialSession.reason(error) }
    }
}
