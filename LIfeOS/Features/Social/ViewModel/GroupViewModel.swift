import Foundation
import Integrations

@MainActor enum SocialSession {
    static var current: AuthSession? { KeychainAuthSessionStore().load() }
    static var api: GroupAPI? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return GroupAPI(baseURL: url, anonKey: key)
    }
    static var people: SocialAPI? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return SocialAPI(baseURL: url, anonKey: key)
    }
    static var stats: SharedStatsClient? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return SharedStatsClient(baseURL: url, anonKey: key)
    }
    static func reason(_ error: Error) -> String {
        if let issue = error as? URLError, issue.code == .notConnectedToInternet { return "You’re offline. Try again when you’re connected." }
        return FriendsViewModel.reason("Couldn’t complete that", error)
    }
}

@MainActor @Observable final class GroupsViewModel {
    var groups: [SocialGroup] = []
    var loading = true
    private(set) var refreshing = false
#if DEBUG
    var previewMode = false
#endif
    var busy = false
    var error: String?
    var sharesWithFriends = false
    let activity: SocialActivitySnapshot?
    init(activity: SocialActivitySnapshot?) { self.activity = activity }

    func refresh(afterChange: Bool = false) async {
#if DEBUG
        if previewMode { return }
#endif
        guard !refreshing, !busy || afterChange else { return }
        refreshing = true
        defer { refreshing = false }
        guard let api = SocialSession.api, let session = SocialSession.current else {
            loading = false; error = "Sign in to use groups."; return
        }
        do {
            let result = try await api.groups(token: session.accessToken)
            guard SocialSession.current?.userID == session.userID else { return }
            groups = result
            if groups.contains(where: { $0.members.contains(where: { $0.sharesWellness == true }) }), let activity { try await api.publish(activity, token: session.accessToken) }
            if let user = UUID(uuidString: session.userID), let statsAPI = SocialSession.stats {
                let stats = try await statsAPI.stats(ids: [user], accessToken: session.accessToken)
                sharesWithFriends = stats[user]?.shares ?? false
                if sharesWithFriends, let activity {
                    try await statsAPI.push(SharedStats(userID: user, shares: true, streak: activity.streak,
                        daysTracked: activity.daysTracked, workouts: activity.workouts), accessToken: session.accessToken)
                }
            }
            error = nil
        } catch { self.error = SocialSession.reason(error) }
        loading = false
    }

    func shareWithFriends(_ enabled: Bool) async {
        guard !busy, !refreshing, let session = SocialSession.current, let user = UUID(uuidString: session.userID), let api = SocialSession.stats else { return }
        busy = true; defer { busy = false }
        do {
            try await api.push(SharedStats(userID: user, shares: enabled, streak: activity?.streak,
                daysTracked: activity?.daysTracked, workouts: activity?.workouts), accessToken: session.accessToken)
            sharesWithFriends = enabled; error = nil
        } catch { self.error = SocialSession.reason(error) }
    }

    func answer(_ group: SocialGroup, accept: Bool) async {
        guard !busy, let api = SocialSession.api, let session = SocialSession.current else { return }
        busy = true; defer { busy = false }
        do { try await api.answer(group: group.id, accept: accept, token: session.accessToken); await refresh(afterChange: true) }
        catch { self.error = SocialSession.reason(error) }
    }
}

@MainActor @Observable final class GroupViewModel {
    var group: SocialGroup
    var members: [GroupMember] = []
    var profiles: [UUID: SocialProfile] = [:]
    var messages: [GroupMessage] = []
    var board: [LeaderboardEntry] = []
    var loadingBoard = false
    var metric: LeaderboardMetric = .effort
    var boardDate = Date.now
    var draft = ""
    var error: String?
    var loading = true
    private(set) var refreshing = false
#if DEBUG
    var previewMode = false
#endif
    var sending = false
    var busy = false
    var loadingOlder = false
    var hasOlder = false
    var accessLost = false
    var failedSend: (id: UUID, body: String)?
    private let activity: SocialActivitySnapshot?
    private var boardGeneration = 0
    private var refreshGeneration = 0
    var myID: UUID? {
#if DEBUG
        if previewMode { return UUID(uuidString: "a6140000-0000-4000-8000-000000000001") }
#endif
        return SocialSession.current.flatMap { UUID(uuidString: $0.userID) }
    }
    var isOwner: Bool { myID == group.ownerID }
    var shares: Bool { members.first { $0.userID == myID }?.sharesWellness == true }

    init(group: SocialGroup, activity: SocialActivitySnapshot?) { self.group = group; self.activity = activity }

    func refresh(afterChange: Bool = false) async {
#if DEBUG
        if previewMode { return }
#endif
        guard (!busy || afterChange) else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshing = true
        defer { if generation == refreshGeneration { refreshing = false } }
        guard let api = SocialSession.api, let session = SocialSession.current else { loading = false; accessLost = true; return }
        do {
            let roster = try await api.members(group: group.id, token: session.accessToken)
            guard generation == refreshGeneration, SocialSession.current?.userID == session.userID else { return }
            guard roster.contains(where: { $0.userID == myID && $0.isAccepted }) else {
                accessLost = true; members = []; messages = []; board = []; loading = false; return
            }
            let people = try await SocialSession.people?.profiles(ids: roster.map(\.userID), accessToken: session.accessToken) ?? []
            let latest = try await api.messages(group: group.id, token: session.accessToken)
            let groups = try await api.groups(token: session.accessToken)
            guard generation == refreshGeneration, SocialSession.current?.userID == session.userID else { return }
            members = roster
            profiles = Dictionary(uniqueKeysWithValues: people.map { ($0.userID, $0) })
            if loading { hasOlder = latest.count == 50 }
            var merged = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
            latest.forEach { merged[$0.id] = $0 }
            messages = merged.values.sorted { $0.id < $1.id }
            if let failedSend, latest.contains(where: { $0.clientID == failedSend.id }) { self.failedSend = nil }
            if let fresh = groups.first(where: { $0.id == group.id }) { group = fresh }
            error = nil
        } catch { if generation == refreshGeneration { self.error = SocialSession.reason(error) } }
        if generation == refreshGeneration { loading = false }
    }

    func older() async {
        guard !loadingOlder, let first = messages.first, let api = SocialSession.api, let token = SocialSession.current?.accessToken else { return }
        loadingOlder = true; defer { loadingOlder = false }
        do {
            let page = try await api.messages(group: group.id, before: first.id, token: token)
            let existing = Set(messages.map(\.id))
            messages.insert(contentsOf: page.filter { !existing.contains($0.id) }, at: 0)
            hasOlder = page.count == 50
        } catch { self.error = SocialSession.reason(error) }
    }

    func send(retry: Bool = false) async {
        guard !sending, !accessLost, let api = SocialSession.api, let token = SocialSession.current?.accessToken else { return }
        let text = retry ? failedSend?.body ?? "" : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.unicodeScalars.count <= 2000 else { return }
        let id = retry ? failedSend?.id ?? UUID() : UUID()
        sending = true; defer { sending = false }
        do {
            _ = try await api.send(group: group.id, body: text, clientID: id, token: token)
            if !retry, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            failedSend = nil
            await refresh()
        } catch {
            failedSend = (id, text)
            if !retry, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            self.error = "Message wasn’t confirmed. Tap Retry to resend it safely."
        }
    }

    func loadBoard() async {
#if DEBUG
        if previewMode { return }
#endif
        guard let api = SocialSession.api, let token = SocialSession.current?.accessToken else { return }
        boardGeneration += 1
        let generation = boardGeneration
        let selection = metric
        loadingBoard = true
        defer { if generation == boardGeneration { loadingBoard = false } }
        do {
            let rows = try await api.leaderboard(group: group.id, metric: selection, day: SocialWellness.dayKey(boardDate), token: token)
            guard generation == boardGeneration else { return }
            board = rows; error = nil
        } catch { if generation == boardGeneration { self.error = SocialSession.reason(error) } }
    }

    func share(_ enabled: Bool) async {
        boardGeneration += 1
        board = []
        await change {
            try await $0.share(group: self.group.id, enabled: enabled, token: $1)
            if enabled, let activity = self.activity { try await $0.publish(activity, token: $1) }
        }
        await loadBoard()
    }
    func invite(_ user: UUID) async { await change { try await $0.invite(group: self.group.id, user: user, token: $1) } }
    func remove(_ user: UUID) async { await change { try await $0.remove(group: self.group.id, user: user, token: $1) } }
    func leave() async -> Bool {
        guard !busy, let api = SocialSession.api, let token = SocialSession.current?.accessToken else { return false }
        busy = true; defer { busy = false }
        do { try await api.leave(group: group.id, token: token); return true }
        catch { self.error = SocialSession.reason(error); return false }
    }
    private func change(_ operation: (GroupAPI, String) async throws -> Void) async {
        guard !busy, let api = SocialSession.api, let token = SocialSession.current?.accessToken else { return }
        busy = true
        refreshGeneration += 1
        defer { busy = false; refreshing = false }
        do { try await operation(api, token); await refresh(afterChange: true) }
        catch { self.error = SocialSession.reason(error) }
    }
}
