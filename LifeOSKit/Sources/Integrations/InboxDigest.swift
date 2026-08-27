import Foundation

/// One conversation, reduced to what an inbox row needs: who it is with, and
/// the last thing either of you said.
public struct InboxThread: Identifiable, Equatable, Sendable {
    public let friend: SocialProfile
    public let lastMessage: SocialMessage
    /// True when the last word was theirs, which is the only thing the schema
    /// lets an inbox honestly say about attention. `messages` carries no read
    /// state, so nothing here claims a message is unread.
    public let theirsIsLast: Bool

    public var id: UUID { friend.userID }

    public init(friend: SocialProfile, lastMessage: SocialMessage, theirsIsLast: Bool) {
        self.friend = friend
        self.lastMessage = lastMessage
        self.theirsIsLast = theirsIsLast
    }
}

/// Turns a flat mailbox into one row per counterpart.
///
/// Its own type in the package rather than a method on the screen's view
/// model, because this is the only real logic the inbox has and it should be
/// testable without a network, a keychain or a simulator. PostgREST cannot
/// express "newest message per counterpart" without a view, so the grouping
/// happens here.
public enum InboxDigest {
    /// `messages` is expected newest first, which is how `recentMessages`
    /// returns it: the first message seen for a counterpart is therefore
    /// their newest, and later ones are skipped.
    ///
    /// A message from someone with no profile in `profiles` is dropped rather
    /// than shown nameless. That happens when a friendship ended while its
    /// messages stayed, and a row for a person no longer in your list is more
    /// confusing than its absence.
    public static func threads(
        from messages: [SocialMessage], mine: UUID, profiles: [UUID: SocialProfile]
    ) -> [InboxThread] {
        var seen: Set<UUID> = []
        var result: [InboxThread] = []

        for message in messages {
            let otherID = message.sender == mine ? message.recipient : message.sender
            guard !seen.contains(otherID), let profile = profiles[otherID] else { continue }
            seen.insert(otherID)
            result.append(
                InboxThread(friend: profile, lastMessage: message, theirsIsLast: message.sender != mine)
            )
        }
        return result
    }
}
