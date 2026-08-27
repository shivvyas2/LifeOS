import Foundation
import Integrations

/// Owns one conversation: the messages with a single friend, the draft, and
/// sending. Plain `@Observable`, same shape as `FriendsViewModel` — credential
/// plumbing from the keychain, `SocialAPI` doing the actual talking.
@MainActor @Observable
final class ChatViewModel {
    let friend: SocialProfile

    private(set) var messages: [SocialMessage] = []
    /// Optimistic rows not yet confirmed by the server, kept apart from
    /// `messages` so a poll landing mid-send can never wholesale-replace them.
    /// `refresh()` only ever assigns `messages`; the screen renders
    /// `messages + pending`.
    private(set) var pending: [SocialMessage] = []
    var draft = ""
    private(set) var sending = false
    /// One quiet sentence for the screen. Never an alert: a failed send is
    /// not an emergency.
    private(set) var errorMessage: String?

    private let sessions: any AuthSessionStoring
    private(set) var myUserID: UUID?
    private var accessToken: String?

    /// Provisional rows get negative ids counting down from -1, so they can
    /// never collide with a real server id (always positive) while a send is
    /// still in flight.
    private var nextProvisionalID = -1

    init(friend: SocialProfile, sessions: any AuthSessionStoring = KeychainAuthSessionStore()) {
        self.friend = friend
        self.sessions = sessions
        // A token without a parseable identity is not a usable session: keep
        // both or neither, rather than holding a token with a nil `myUserID`.
        if let session = sessions.load(), let userID = UUID(uuidString: session.userID) {
            myUserID = userID
            accessToken = session.accessToken
        }
    }

    private var api: SocialAPI? {
        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: baseURL, anonKey: anonKey)
    }

    /// Loads the conversation. Called on the poll loop and again after a send
    /// so the server's real row shows up; only ever assigns `messages`, never
    /// touches `pending`.
    func refresh() async {
        guard let api, let accessToken else { return }
        do {
            messages = try await api.messages(with: friend.userID, accessToken: accessToken)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load messages"
        }
    }

    /// Appends a provisional row to `pending` immediately, clears the draft,
    /// then posts. A failed post removes the row it added rather than leaving
    /// a message on screen that never actually sent. Guards its own reentry
    /// so a fast double-tap of the send button (before the disabled state has
    /// a chance to apply) can never fire two posts for the same draft.
    func send() async {
        guard !sending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api, let accessToken, let myUserID else { return }

        let provisionalID = nextProvisionalID
        nextProvisionalID -= 1
        let provisional = SocialMessage(
            id: provisionalID, sender: myUserID, recipient: friend.userID, body: text, createdAt: .now
        )
        pending.append(provisional)
        draft = ""
        sending = true

        do {
            try await api.send(text, to: friend.userID, accessToken: accessToken)
            pending.removeAll { $0.id == provisionalID }
            errorMessage = nil
            await refresh()
        } catch {
            pending.removeAll { $0.id == provisionalID }
            errorMessage = "Could not send message"
        }

        sending = false
    }
}
