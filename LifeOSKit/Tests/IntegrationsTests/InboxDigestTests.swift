import Testing
import Foundation
@testable import Integrations

struct InboxDigestTests {
    private let me = UUID()
    private let ada = UUID()
    private let grace = UUID()

    private var profiles: [UUID: SocialProfile] {
        [
            ada: SocialProfile(userID: ada, displayName: "Ada"),
            grace: SocialProfile(userID: grace, displayName: "Grace"),
        ]
    }

    private func message(_ id: Int, from sender: UUID, to recipient: UUID, _ body: String, minutesAgo: Int) -> SocialMessage {
        SocialMessage(
            id: id, sender: sender, recipient: recipient, body: body,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(minutesAgo) * 60)
        )
    }

    @Test func oneRowPerPersonCarryingTheirNewestMessage() {
        let messages = [
            message(4, from: ada, to: me, "third", minutesAgo: 1),
            message(3, from: me, to: grace, "hello grace", minutesAgo: 5),
            message(2, from: me, to: ada, "second", minutesAgo: 10),
            message(1, from: ada, to: me, "first", minutesAgo: 20),
        ]

        let threads = InboxDigest.threads(from: messages, mine: me, profiles: profiles)

        #expect(threads.count == 2)
        #expect(threads[0].friend.userID == ada)
        #expect(threads[0].lastMessage.body == "third")
        #expect(threads[1].friend.userID == grace)
    }

    /// Order follows the input, which arrives newest first, so the busiest
    /// recent conversation is the top row.
    @Test func theNewestConversationLeads() {
        let messages = [
            message(2, from: grace, to: me, "newer", minutesAgo: 1),
            message(1, from: ada, to: me, "older", minutesAgo: 60),
        ]
        let threads = InboxDigest.threads(from: messages, mine: me, profiles: profiles)
        #expect(threads.map(\.friend.userID) == [grace, ada])
    }

    @Test func aMessageYouSentIsMarkedAsYours() {
        let messages = [message(1, from: me, to: ada, "mine", minutesAgo: 1)]
        let thread = InboxDigest.threads(from: messages, mine: me, profiles: profiles).first
        #expect(thread?.theirsIsLast == false)
    }

    @Test func aMessageTheySentIsMarkedAsTheirs() {
        let messages = [message(1, from: ada, to: me, "theirs", minutesAgo: 1)]
        let thread = InboxDigest.threads(from: messages, mine: me, profiles: profiles).first
        #expect(thread?.theirsIsLast == true)
    }

    /// A friendship can end while its messages stay. A row for someone no
    /// longer in the friend list would be nameless, so it is dropped.
    @Test func aMessageFromSomeoneWithNoProfileIsDropped() {
        let stranger = UUID()
        let messages = [
            message(2, from: stranger, to: me, "who is this", minutesAgo: 1),
            message(1, from: ada, to: me, "hello", minutesAgo: 5),
        ]
        let threads = InboxDigest.threads(from: messages, mine: me, profiles: profiles)
        #expect(threads.map(\.friend.userID) == [ada])
    }

    @Test func anEmptyMailboxMakesNoThreads() {
        #expect(InboxDigest.threads(from: [], mine: me, profiles: profiles).isEmpty)
    }
}
