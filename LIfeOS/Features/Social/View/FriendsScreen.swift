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
    var embedded = false
    @State private var viewModel = FriendsViewModel()
    @Environment(\.colorScheme) private var scheme

    init(embedded: Bool = false) { self.embedded = embedded }
#if DEBUG
    init(preview: FriendsViewModel) { _viewModel = State(initialValue: preview) }
#endif

    /// The friend a row was tapped for. `SocialProfile` isn't `Hashable`, so
    /// this pairs a stored selection with `isPresented:` rather than using
    /// `navigationDestination(item:)`.
    @State private var openChat: SocialProfile?
    @State private var showChat = false
    @State private var showInbox = false

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    private var isSearching: Bool {
        !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SocialCanvas {
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
        .navigationTitle(embedded ? "Together" : "Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded { ToolbarItem(placement: .topBarTrailing) {
                Button { showInbox = true } label: {
                    Image(systemName: "tray")
                        .overlay(alignment: .topTrailing) {
                            // Counts requests only. A conversation is
                            // something to return to, not something owed, and
                            // badging it would make the app look like it is
                            // asking for something whenever a friend says
                            // hello.
                            if viewModel.requests.count > 0 {
                                Circle()
                                    .fill(LifeOSTokens.accent)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -3)
                            }
                        }
                }
                .accessibilityLabel(
                    viewModel.requests.isEmpty
                        ? "Inbox"
                        : "Inbox, \(viewModel.requests.count) requests waiting"
                )
            } }
        }
        .navigationDestination(isPresented: $showInbox) {
            InboxScreen()
        }
        .task { await viewModel.appear() }
        .onChange(of: showChat) { _, open in if !open { Task { await viewModel.refresh() } } }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.search()
        }
        .navigationDestination(isPresented: $showChat) {
            if let openChat {
                UserProfileScreen(profile: openChat)
            }
        }
    }

    // MARK: - Guest

    private var guestState: some View {
        Text("Sign in to find friends and message them.")
            .lifeOSText(.secondary)
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Signed in

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SocialHeading(title: "Your people.", detail: "Find a friend. Share a win. Keep each other going.", icon: "person.2.fill")
                searchField

                if let warning = viewModel.publishWarning {
                    Text(warning)
                        .lifeOSText(.secondary)
                        .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .lifeOSText(.secondary)
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
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.refresh() }
    }

    /// The same vocabulary as the library rail's own search field: a plain
    /// row on a faint tint, not a search bar borrowed from a list.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .lifeOSText(.label)
                .foregroundStyle(secondary)
            TextField("Search people", text: $viewModel.query)
                .lifeOSText(.secondary)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(primary.opacity(scheme == .dark ? 0.10 : 0.05))
        )
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("Friend requests")
            ForEach(viewModel.requests, id: \.profile.id) { entry in
                SocialFriendRequest(profile: entry.profile,
                    accept: { Task { await viewModel.accept(entry.friendshipID) } },
                    decline: { Task { await viewModel.remove(friendshipID: entry.friendshipID) } })
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { eyebrow("Your circle"); Spacer(); Text("\(viewModel.friends.count)").lifeOSText(.secondary).foregroundStyle(secondary) }
            if viewModel.friends.isEmpty {
                SocialEmpty(title: "Good company starts here", detail: "Search for someone by name to send a friend request.", icon: "person.crop.circle.badge.plus")
            } else {
                ForEach(viewModel.friends, id: \.profile.id) { entry in
                    Button {
                        openChat = entry.profile
                        showChat = true
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(profile: entry.profile, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.profile.displayName).lifeOSText(.rowTitle).foregroundStyle(primary)
                                Text("View profile & message").lifeOSText(.caption).foregroundStyle(secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(LifeOSType.eyebrow)
                                .foregroundStyle(secondary)
                        }.padding(.vertical, 10).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                            Task { await viewModel.remove(friendshipID: entry.friendshipID) }
                        }
                    }
                    if entry.profile.id != viewModel.friends.last?.profile.id { Divider().padding(.leading, 64) }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.searching {
                ProgressView("Searching people…").frame(maxWidth: .infinity).padding(24)
            } else if viewModel.searchResults.isEmpty && viewModel.errorMessage == nil {
                Text("No one found")
                    .lifeOSText(.secondary)
                    .foregroundStyle(secondary)
            } else {
                ForEach(viewModel.searchResults) { profile in
                    HStack(spacing: 12) {
                        Button { openChat = profile; showChat = true } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(profile: profile)
                                Text(profile.displayName).lifeOSText(.rowTitle).foregroundStyle(primary)
                            }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 52).contentShape(.rect)
                        }.buttonStyle(.plain)
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
                .lifeOSText(.label)
                .foregroundStyle(secondary)
        } else if viewModel.outgoingPending.contains(profile.userID)
            || viewModel.requests.contains(where: { $0.profile.id == profile.id }) {
            Text("Requested")
                .lifeOSText(.label)
                .foregroundStyle(secondary)
        } else {
            Button("Add") {
                Task { await viewModel.add(profile) }
            }.buttonStyle(.editorial(.primary, size: .compact))
        }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .lifeOSText(.sectionTitle)
            .foregroundStyle(primary)
    }

}
