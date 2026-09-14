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
    private(set) var searching = false
    /// One quiet sentence for the screen. Never an alert: a failed friend
    /// request is not an emergency.
    private(set) var errorMessage: String?
    /// Why this device's own profile row is not on the server, if it is not.
    ///
    /// Separate from `errorMessage` because `load()` clears that one whenever
    /// a reload succeeds, and "nobody can find you" outlives a successful
    /// friend list fetch. The two say different things and must not overwrite
    /// each other.
    private(set) var publishWarning: String?

    private let sessions: any AuthSessionStoring
    private var myUserID: UUID?
    /// Read fresh from the keychain on every call rather than captured once.
    /// `AppShell` refreshes the session hourly and on foregrounding; a token
    /// snapshotted at `appear()` would strand a long-open screen with 401s
    /// once that refresh rotates it. Identity does not rotate, so `myUserID`
    /// is the one thing still safe to capture.
    private var accessToken: String? { sessions.load()?.accessToken }

    init(sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.sessions = sessions
    }

#if DEBUG
    private var previewMode = false
    static func designPreview() -> FriendsViewModel {
        let model = FriendsViewModel()
        model.previewMode = true; model.phase = .ready
        model.friends = [(SocialProfile(userID: UUID(), displayName: "Alex Morgan"), 1),
                         (SocialProfile(userID: UUID(), displayName: "Jamie Chen"), 2),
                         (SocialProfile(userID: UUID(), displayName: "Sofia Rivera"), 3)]
        model.requests = [(SocialProfile(userID: UUID(), displayName: "Noah Williams"), 4)]
        return model
    }
#endif

    private var api: SocialAPI? {
        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: baseURL, anonKey: anonKey)
    }

    /// Called once when the screen appears: establish who is signed in,
    /// publish the local display name as this device's profile row, then
    /// load the lists it drives.
    func appear() async {
#if DEBUG
        if previewMode { return }
#endif
        guard let session = sessions.load(), let userID = UUID(uuidString: session.userID) else {
            phase = .guest
            return
        }
        myUserID = userID

        // Publishing this device's name is what makes the person findable, so
        // a failure here is the difference between having friends and not. It
        // used to be discarded.
        let name = ProfileStore.load().fullName
        if let api, !name.isEmpty {
            do {
                try await api.upsertMyProfile(
                    accessToken: session.accessToken, userID: userID, displayName: name
                )
                publishWarning = nil
            } catch {
                publishWarning = Self.reason("Others may not find you: publishing your profile failed", error)
            }
        } else if name.isEmpty {
            // No name, no row, no search result. Silent until now.
            publishWarning = "Add your name in Edit profile so people can find you."
        }

        await load()
    }

    /// Pull-to-refresh and the retry after an accept: the same reload.
    func refresh() async {
#if DEBUG
        if previewMode { return }
#endif
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
            errorMessage = Self.reason("Could not load friends", error)
        }

        phase = .ready
    }

    /// A failure a person can act on, or at least report.
    ///
    /// "Search failed" is true of an expired session, a missing grant and a
    /// dropped connection alike, which makes it useless for all three. The
    /// server almost always says which; this puts that sentence where it can
    /// be read instead of dropping it on the floor.
    static func reason(_ prefix: String, _ error: Error) -> String {
        if let api = error as? SocialAPIError {
            return "\(prefix): \(api.description)"
        }
        let urlError = error as? URLError
        if urlError?.code == .notConnectedToInternet || urlError?.code == .networkConnectionLost {
            return "\(prefix): no connection"
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    /// The in-flight request for the current `query`, if any.
    ///
    /// Search re-runs on every keystroke, so an older request can still be
    /// waiting on the network when a newer one is issued. Without tracking
    /// which query is in flight, a slow response for "al" could land after
    /// the fast response for "alex" and silently replace the right results
    /// with the wrong ones.
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    /// Runs a search for the current `query`. Excludes the signed-in user:
    /// finding yourself in your own friends search is noise, not a result.
    ///
    /// Cancels whatever search is already running, then only ever writes
    /// `searchResults` if this call is still the most recent one by the time
    /// its network round trip returns — a cancelled or superseded response is
    /// dropped rather than applied.
    func search() {
#if DEBUG
        if previewMode { return }
#endif
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searching = false

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        // Saying nothing here is what "it just spins" looks like from the
        // outside: no results, no error, no spinner ending. Each of these
        // three is a different problem and each is worth naming.
        guard let api else {
            errorMessage = "This build has no Supabase configuration"
            return
        }
        guard let accessToken else {
            errorMessage = "Signed out. Sign in again to search."
            return
        }
        guard let myUserID else {
            errorMessage = "Still working out who you are, try again in a moment"
            return
        }

        let issuedQuery = query
        searching = true
        searchResults = []
        searchTask = Task {
            defer { if generation == searchGeneration { searching = false } }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let results = try await api.search(trimmed, accessToken: accessToken)
                guard !Task.isCancelled, issuedQuery == self.query else { return }
                searchResults = results.filter { $0.userID != myUserID }
                errorMessage = nil
            } catch {
                guard !Task.isCancelled, issuedQuery == self.query else { return }
                errorMessage = Self.reason("Search failed", error)
            }
        }
    }

    /// Sends a friend request. Marked pending immediately rather than after
    /// the round trip, so the button's state does not flicker back to "Add"
    /// while the request is in flight.
    func add(_ profile: SocialProfile) async {
#if DEBUG
        if previewMode { return }
#endif
        // Saying nothing here is what "it just spins" looks like from the
        // outside: no results, no error, no spinner ending. Each of these
        // three is a different problem and each is worth naming.
        guard let api else {
            errorMessage = "This build has no Supabase configuration"
            return
        }
        guard let accessToken else {
            errorMessage = "Signed out. Sign in again to search."
            return
        }
        guard let myUserID else {
            errorMessage = "Still working out who you are, try again in a moment"
            return
        }
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
#if DEBUG
        if previewMode { return }
#endif
        guard let api, let accessToken else { return }
        do {
            try await api.accept(friendshipID: friendshipID, accessToken: accessToken)
            await load()
        } catch {
            errorMessage = "Could not accept request"
        }
    }

    /// Ends a friendship row and reloads. The same call for both endings of
    /// its life: declining a pending request and removing an accepted
    /// friend, since either way the row simply stops existing.
    func remove(friendshipID: Int) async {
#if DEBUG
        if previewMode { return }
#endif
        guard let api, let accessToken else { return }
        do {
            try await api.remove(friendshipID: friendshipID, accessToken: accessToken)
            await load()
        } catch {
            errorMessage = "Could not remove"
        }
    }

    private func other(of friendship: Friendship, given myUserID: UUID) -> UUID {
        friendship.requester == myUserID ? friendship.addressee : friendship.requester
    }
}
