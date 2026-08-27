import Foundation
import Integrations

/// Owns the friends screen: who signed in is, who they already know, who is
/// asking to know them, and whoever a search just turned up.
///
/// Plain `@Observable`, not a service with its own retry logic. `SocialAPI`
/// already shapes every request; this only turns three tables (friendships,
/// the profiles behind them, a search) into the four lists the screen reads.
@MainActor @Observable
final class FriendsViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// No session in the keychain. The profile owns the sign-in journey;
        /// this screen only has to say why it is empty.
        case guest
    }

    private(set) var phase: Phase = .loading
    /// Accepted friendships, alphabetised by name so the list does not
    /// reorder itself as requests come and go.
    private(set) var friends: [(profile: SocialProfile, friendshipID: Int)] = []
    /// Pending requests where the signed-in user is the addressee: the ones
    /// that need a decision, not the ones already sent.
    private(set) var requests: [(profile: SocialProfile, friendshipID: Int)] = []
    /// Users the signed-in person has already asked, so a search result for
    /// them reads "Requested" instead of offering to ask again.
    private(set) var outgoingPending: Set<UUID> = []
    private(set) var searchResults: [SocialProfile] = []
    var query = ""
    /// One quiet sentence for the screen. Never an alert: a failed friend
    /// request is not an emergency.
    private(set) var errorMessage: String?

    private let sessions: any AuthSessionStoring
    private var myUserID: UUID?
    private var accessToken: String?

    init(sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.sessions = sessions
    }

    private var api: SocialAPI? {
        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: baseURL, anonKey: anonKey)
    }

    /// Called once when the screen appears: establish who is signed in,
    /// publish the local display name as this device's profile row, then
    /// load the lists it drives.
    func appear() async {
        guard let session = sessions.load(), let userID = UUID(uuidString: session.userID) else {
            phase = .guest
            return
        }
        myUserID = userID
        accessToken = session.accessToken

        let name = ProfileStore.load().fullName
        if let api, !name.isEmpty {
            try? await api.upsertMyProfile(accessToken: session.accessToken, userID: userID, displayName: name)
        }

        await load()
    }

    /// Pull-to-refresh and the retry after an accept: the same reload.
    func refresh() async {
        await load()
    }

    private func load() async {
        guard let api, let myUserID, let accessToken else { phase = .guest; return }

        do {
            let friendships = try await api.friendships(accessToken: accessToken)
            let otherIDs = Array(Set(friendships.map { other(of: $0, given: myUserID) }))
            let profilesByID = Dictionary(
                uniqueKeysWithValues: try await api.profiles(ids: otherIDs, accessToken: accessToken)
                    .map { ($0.userID, $0) }
            )

            var acceptedFriends: [(SocialProfile, Int)] = []
            var incomingRequests: [(SocialProfile, Int)] = []
            var pendingOutgoing: Set<UUID> = []

            for friendship in friendships {
                let otherID = other(of: friendship, given: myUserID)
                guard let profile = profilesByID[otherID] else { continue }
                switch friendship.status {
                case .accepted:
                    acceptedFriends.append((profile, friendship.id))
                case .pending:
                    if friendship.addressee == myUserID {
                        incomingRequests.append((profile, friendship.id))
                    } else {
                        pendingOutgoing.insert(otherID)
                    }
                }
            }

            friends = acceptedFriends.sorted { $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending }
            requests = incomingRequests
            outgoingPending = pendingOutgoing
            errorMessage = nil
        } catch {
            errorMessage = "Could not load friends"
        }

        phase = .ready
    }

    /// Runs a search for the current `query`. Excludes the signed-in user:
    /// finding yourself in your own friends search is noise, not a result.
    func search() async {
        guard let api, let accessToken, let myUserID else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try await api.search(trimmed, accessToken: accessToken)
                .filter { $0.userID != myUserID }
            errorMessage = nil
        } catch {
            errorMessage = "Search failed"
        }
    }

    /// Sends a friend request. Marked pending immediately rather than after
    /// the round trip, so the button's state does not flicker back to "Add"
    /// while the request is in flight.
    func add(_ profile: SocialProfile) async {
        guard let api, let accessToken, let myUserID else { return }
        outgoingPending.insert(profile.userID)
        do {
            try await api.request(from: myUserID, to: profile.userID, accessToken: accessToken)
            errorMessage = nil
        } catch {
            outgoingPending.remove(profile.userID)
            errorMessage = "Could not send request"
        }
    }

    /// Accepts an incoming request and reloads, since accepting turns a
    /// request row into a friend row.
    func accept(_ friendshipID: Int) async {
        guard let api, let accessToken else { return }
        do {
            try await api.accept(friendshipID: friendshipID, accessToken: accessToken)
            await load()
        } catch {
            errorMessage = "Could not accept request"
        }
    }

    private func other(of friendship: Friendship, given myUserID: UUID) -> UUID {
        friendship.requester == myUserID ? friendship.addressee : friendship.requester
    }
}
