import Foundation
import Observation
import DesignSystem
import Persistence

/// Today's arrangement for this account on this device, saved on every change.
@MainActor @Observable
final class TodayLayoutStore {
    private let defaults: UserDefaults
    private static let key = "today.layout"
    private static let githubKey = "today.layout.githubOffered"
    static let inboxOfferKey = "today.layout.inboxOffered"
    private static let hintKey = "today.layout.hintSeen"

    var layout: TodayLayout { didSet { defaults.set(layout.encoded(), forKey: Self.key) } }
    var isArranging = false
    var hintSeen: Bool { didSet { defaults.set(hintSeen, forKey: Self.hintKey) } }

    init(defaults: UserDefaults = .currentAccount) {
        self.defaults = defaults
        layout = TodayLayout.decoded(defaults.data(forKey: Self.key))
        hintSeen = defaults.bool(forKey: Self.hintKey)
    }

    func update(_ change: (inout TodayLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next
        hintSeen = true
    }

    func reset() { layout = .standard }

    /// The first time GitHub connects, once.
    func offerGitHubOnce() {
        guard !defaults.bool(forKey: Self.githubKey) else { return }
        defaults.set(true, forKey: Self.githubKey)
        update { $0.offerGitHub() }
    }

    /// The first time Gmail connects, once.
    func offerInboxOnce() {
        guard !defaults.bool(forKey: Self.inboxOfferKey) else { return }
        defaults.set(true, forKey: Self.inboxOfferKey)
        update { $0.offerInbox() }
    }
}
