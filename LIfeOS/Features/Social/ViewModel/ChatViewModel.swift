import Foundation
import Integrations

/// Owns one conversation: the messages with a single friend, the draft, and
/// sending. Plain `@Observable`, same shape as `FriendsViewModel` — credential
/// plumbing from the keychain, `SocialAPI` doing the actual talking.
@MainActor @Observable
final class ChatViewModel {
    let friend: SocialProfile

    private(set) var messages: [SocialMessage] = []
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
        if let session = sessions.load() {
            myUserID = UUID(uuidString: session.userID)
            accessToken = session.accessToken
        }
    }

    private var api: SocialAPI? {
        guard let baseURL = AppConfig.supabaseURL, let anonKey = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: baseURL, anonKey: anonKey)
    }

    /// Loads the conversation. Called on appear, on the poll loop, and again
    /// after a send so the optimistic row reconciles with the real one.
    func refresh() async {
        guard let api, let accessToken else { return }
        do {
            messages = try await api.messages(with: friend.userID, accessToken: accessToken)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load messages"
        }
    }

    /// Appends a provisional row immediately, clears the draft, then posts.
    /// A failed post removes the row it added rather than leaving a message
    /// on screen that never actually sent.
    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api, let accessToken, let myUserID else { return }

        let provisionalID = nextProvisionalID
        nextProvisionalID -= 1
        let provisional = SocialMessage(
            id: provisionalID, sender: myUserID, recipient: friend.userID, body: text, createdAt: .now
        )
        messages.append(provisional)
        draft = ""
        sending = true

        do {
            try await api.send(text, to: friend.userID, accessToken: accessToken)
            errorMessage = nil
            await refresh()
        } catch {
            messages.removeAll { $0.id == provisionalID }
            errorMessage = "Could not send message"
        }

        sending = false
    }
}
