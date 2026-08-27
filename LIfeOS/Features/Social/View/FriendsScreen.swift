import SwiftUI
import DesignSystem
import Integrations

/// Find people and keep the ones already found.
///
/// One list, three shapes: a search field that, once typed in, replaces the
/// screen's own sections with results; otherwise REQUESTS above FRIENDS, in
/// that order, because a decision waiting on you outranks a list you already
/// know. Pushed from the profile, not tabbed, the same way settings is: this
/// is a place you go, not a home you live in.
struct FriendsScreen: View {
    @State private var viewModel = FriendsViewModel()
    @Environment(\.colorScheme) private var scheme

    /// The friend a row was tapped for. `SocialProfile` isn't `Hashable`, so
    /// this pairs a stored selection with `isPresented:` rather than using
    /// `navigationDestination(item:)`.
    @State private var openChat: SocialProfile?
    @State private var showChat = false

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    private var isSearching: Bool {
        !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GradientCanvas(hue: .habits) {
            switch viewModel.phase {
            case .guest:
                guestState
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                ready
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.appear() }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.search()
        }
        .navigationDestination(isPresented: $showChat) {
            if let openChat {
                FriendChatScreen(friend: openChat)
            }
        }
    }

    // MARK: - Guest

    private var guestState: some View {
        Text("Sign in to find friends and message them.")
            .font(LifeOSType.secondary)
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Signed in

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                searchField

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                }

                if isSearching {
                    searchResultsSection
                } else {
                    if !viewModel.requests.isEmpty { requestsSection }
                    friendsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.refresh() }
    }

    /// The same vocabulary as the library rail's own search field: a plain
    /// row on a faint tint, not a search bar borrowed from a list.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(LifeOSType.label)
                .foregroundStyle(secondary)
            TextField("Search people", text: $viewModel.query)
                .font(LifeOSType.secondary)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.10 : 0.05))
        )
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("REQUESTS")
            ForEach(viewModel.requests, id: \.profile.id) { entry in
                HStack(spacing: 12) {
                    initialBubble(entry.profile.displayName)
                    Text(entry.profile.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(primary)
                    Spacer(minLength: 8)
                    CapsuleButton(title: "Accept") {
                        Task { await viewModel.accept(entry.friendshipID) }
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("FRIENDS")
            if viewModel.friends.isEmpty {
                Text("No friends yet. Search above to find people.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(secondary)
            } else {
                ForEach(viewModel.friends, id: \.profile.id) { entry in
                    Button {
                        openChat = entry.profile
                        showChat = true
                    } label: {
                        HStack(spacing: 12) {
                            initialBubble(entry.profile.displayName)
                            Text(entry.profile.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(primary)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(LifeOSType.eyebrow)
                                .foregroundStyle(secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.searchResults.isEmpty {
                Text("No one found")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(secondary)
            } else {
                ForEach(viewModel.searchResults) { profile in
                    HStack(spacing: 12) {
                        initialBubble(profile.displayName)
                        Text(profile.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(primary)
                        Spacer(minLength: 8)
                        searchTrailing(for: profile)
                    }
                }
            }
        }
    }

    /// Add, Requested or Friends: a search result is always exactly one of
    /// the three, never a fourth "request me back" state — accepting still
    /// happens from the REQUESTS section, which already owns that decision.
    @ViewBuilder
    private func searchTrailing(for profile: SocialProfile) -> some View {
        if viewModel.friends.contains(where: { $0.profile.id == profile.id }) {
            Text("Friends")
                .font(LifeOSType.label)
                .foregroundStyle(secondary)
        } else if viewModel.outgoingPending.contains(profile.userID)
            || viewModel.requests.contains(where: { $0.profile.id == profile.id }) {
            Text("Requested")
                .font(LifeOSType.label)
                .foregroundStyle(secondary)
        } else {
            CapsuleButton(title: "Add") {
                Task { await viewModel.add(profile) }
            }
        }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .font(LifeOSType.eyebrow)
            .tracking(0.8)
            .foregroundStyle(secondary)
    }

    /// A 38pt pastel circle carrying the first letter of a name, coloured by
    /// a stable hash of that name so the same person is always the same
    /// colour. `String.hashValue` is randomised per launch, which would make
    /// a friend a different colour every time the app opens, so the hash is
    /// hand-rolled from the name's bytes instead.
    private func initialBubble(_ name: String) -> some View {
        let hue = Self.stableHue(for: name)
        let letter = name.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "?"
        return Text(letter)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(hue.top)
            .frame(width: 38, height: 38)
            .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
    }

    private static func stableHue(for name: String) -> ModuleHue {
        let hash = name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let index = abs(hash) % ModuleHue.allCases.count
        return ModuleHue.allCases[index]
    }
}
