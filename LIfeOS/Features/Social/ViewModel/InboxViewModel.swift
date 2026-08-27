import Foundation
import Integrations

/// Everything waiting on the signed-in person: requests to answer, and
/// conversations to come back to.
///
/// Same shape as `FriendsViewModel`, and deliberately not folded into it. The
/// friends screen is a directory, which is a thing you browse; this is a
/// queue, which is a thing you clear. They load different data and empty for
/// different reasons.
@MainActor @Observable
final class InboxViewModel {
    enum Phase: Equatable { case loading, ready, guest }

    private(set) var phase: Phase = .loading
    /// Pending friendships where the signed-in user is the addressee: the
    /// ones needing a decision, not the ones already sent.
    private(set) var requests: [(profile: SocialProfile, friendshipID: Int)] = []
    /// Newest conversation first.
    private(set) var threads: [InboxThread] = []
    private(set) var errorMessage: String?

    private let sessions: any AuthSessionStoring
    private var myUserID: UUID?
    /// Read fresh on every call rather than captured, for the reason
    /// `FriendsViewModel` gives: the session refreshes hourly and a screen
    /// left open would otherwise strand itself on a rotated token.
    private var accessToken: String? { sessions.load()?.accessToken }

    init(sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.sessions = sessions
    }

    private var api: SocialAPI? {
        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: baseURL, anonKey: anonKey)
    }

    /// What the badge counts. Requests only: a conversation is not a task.
    var pendingCount: Int { requests.count }

    func appear() async {
        guard let session = sessions.load(), let userID = UUID(uuidString: session.userID) else {
            phase = .guest
            return
        }
        myUserID = userID
        await load()
    }

    func refresh() async { await load() }

    /// Three requests, not one per friend: the friendships, the profiles
    /// behind them, and the whole mailbox in one go. The grouping into
    /// threads is `InboxDigest`, in the package, where it can be tested.
    private func load() async {
        guard let api, let myUserID, let accessToken else { phase = .guest; return }

        do {
            let friendships = try await api.friendships(accessToken: accessToken)
            let otherIDs = Array(Set(friendships.map {
                $0.requester == myUserID ? $0.addressee : $0.requester
            }))
            let profilesByID = Dictionary(
                uniqueKeysWithValues: try await api.profiles(ids: otherIDs, accessToken: accessToken)
                    .map { ($0.userID, $0) }
            )

            requests = friendships.compactMap { friendship in
                guard friendship.status == .pending, friendship.addressee == myUserID,
                      let profile = profilesByID[friendship.requester] else { return nil }
                return (profile, friendship.id)
            }

            let messages = try await api.recentMessages(accessToken: accessToken)
            threads = InboxDigest.threads(from: messages, mine: myUserID, profiles: profilesByID)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your inbox"
        }

        phase = .ready
    }

    func accept(_ friendshipID: Int) async {
        guard let api, let accessToken else { return }
        do {
            try await api.accept(friendshipID: friendshipID, accessToken: accessToken)
            await load()
        } catch {
            errorMessage = "Could not accept request"
        }
    }

    func decline(_ friendshipID: Int) async {
        guard let api, let accessToken else { return }
        do {
            try await api.remove(friendshipID: friendshipID, accessToken: accessToken)
            await load()
        } catch {
            errorMessage = "Could not decline request"
        }
    }
}
