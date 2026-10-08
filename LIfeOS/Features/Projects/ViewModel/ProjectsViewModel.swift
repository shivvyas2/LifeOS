import Foundation
import SwiftData
import Integrations
import Persistence

/// The Projects tab's state: your projects, today's tasks across them, the
/// contribution grid, and every write, each followed by a sync.
@MainActor @Observable
final class ProjectsViewModel {
    private(set) var projects: [ProjectSnapshot] = []
    private(set) var archived: [ProjectSnapshot] = []
    private(set) var todayTasks: [ProjectTaskSnapshot] = []
    /// A year of daily counts, oldest first, and their total.
    private(set) var contributions: [Int] = []
    private(set) var contributionTotal = 0
    private(set) var contributionsFromGitHub = false
    /// Display names for user ids seen in projects.
    private(set) var names: [UUID: String] = [:]

    private(set) var me: UUID?
    private var context: ModelContext?
    private var sync: ProjectSync?
    private let calendar: Calendar

    init(calendar: Calendar = .current) { self.calendar = calendar }

    var store: ProjectsStore? { context.map { ProjectsStore(context: $0, calendar: calendar) } }

    func attach(_ context: ModelContext, sync: ProjectSync?, me: UUID?) {
        self.context = context
        self.sync = sync
        self.me = me
    }

    func load() {
        guard let store else { return }
        projects = (try? store.projects()) ?? []
        archived = ((try? store.projects(includeArchived: true)) ?? []).filter(\.isArchived)
        todayTasks = me.flatMap { try? store.myTasks(userID: $0, on: .now) } ?? []
        if !contributionsFromGitHub {
            contributions = (try? store.completedPerDay(endingOn: .now)) ?? []
            contributionTotal = contributions.reduce(0, +)
        }
    }

    /// GitHub's year when connected; otherwise tasks completed per day.
    /// Called again whenever the connection changes, so connecting shows the
    /// GitHub year at once and disconnecting goes back to tasks rather than
    /// leaving the last account's year on screen.
    func loadContributions(from github: GitHubConnectionViewModel?) async {
        if let year = await github?.contributions() {
            contributions = year.days
            contributionTotal = year.total
            contributionsFromGitHub = true
        } else if contributionsFromGitHub {
            contributionsFromGitHub = false
            load()
        }
    }

    func refresh() async {
        await sync?.sync()
        load()
        await loadNames()
    }

    /// Stages written from GitHub go up like any other edit.
    func syncAfterStages() { requestSync() }

    private func requestSync() {
        load()
        Task { await sync?.sync(); load() }
    }

    /// Names for every member of every project, from the profiles table.
    func loadNames() async {
        guard let store, let base = AppConfig.supabaseURL, let anon = AppConfig.supabaseAnonKey,
              let token = KeychainAuthSessionStore().load()?.accessToken else { return }
        let ids = Set((try? store.projects(includeArchived: true))?.flatMap { project in
            ((try? store.members(projectID: project.id)) ?? []).map(\.userID)
        } ?? []).subtracting(names.keys)
        guard !ids.isEmpty else { return }
        let profiles = (try? await SocialAPI(baseURL: base, anonKey: anon).profiles(ids: Array(ids), accessToken: token)) ?? []
        for profile in profiles { names[profile.userID] = profile.displayName }
    }

    /// Shown on the home when the last sync could not finish.
    var syncError: String? { sync?.lastError }

    func name(_ id: UUID?) -> String {
        guard let id else { return "Unassigned" }
        if id == me { return "You" }
        return names[id] ?? "Member"
    }

    // MARK: Writes

    @discardableResult
    func createProject(name: String, scope: String, colour: ProjectColourName, startsOn: Date?, endsOn: Date?,
                       repo: String?) -> UUID? {
        guard let store, let me else { return nil }
        let id = try? store.createProject(name: name, scope: scope, colour: colour, ownerID: me,
                                          startsOn: startsOn, endsOn: endsOn, repo: repo)
        requestSync()
        return id
    }

    func updateProject(_ id: UUID, name: String? = nil, scope: String? = nil, colour: String? = nil,
                       startsOn: Date?? = nil, endsOn: Date?? = nil, repo: String?? = nil, archived: Bool? = nil) {
        try? store?.updateProject(id: id, name: name, scope: scope, colour: colour, startsOn: startsOn,
                                  endsOn: endsOn, repo: repo, archived: archived)
        requestSync()
    }

    @discardableResult
    func createTask(in project: UUID, title: String, status: ProjectStatus = .todo,
                    startsAt: Date? = nil, endsAt: Date? = nil) -> UUID? {
        guard let store else { return nil }
        let id = try? store.createTask(projectID: project, title: title, status: status)
        if let id, startsAt != nil {
            try? store.updateTask(id: id, ownerID: .some(me), startsAt: .some(startsAt), endsAt: .some(endsAt))
        }
        requestSync()
        return id
    }

    func updateTask(_ id: UUID, title: String? = nil, notes: String? = nil, ownerID: UUID?? = nil,
                    milestoneID: UUID?? = nil, featureID: UUID?? = nil, dueOn: Date?? = nil,
                    startsAt: Date?? = nil, endsAt: Date?? = nil) {
        try? store?.updateTask(id: id, title: title, notes: notes, ownerID: ownerID, milestoneID: milestoneID,
                               featureID: featureID, dueOn: dueOn, startsAt: startsAt, endsAt: endsAt)
        requestSync()
    }

    func moveTask(_ id: UUID, to status: ProjectStatus, at index: Int) {
        try? store?.moveTask(id: id, to: status, at: index)
        requestSync()
    }

    func deleteTask(_ id: UUID) {
        try? store?.deleteTask(id: id)
        requestSync()
    }

    func createMilestone(in project: UUID, title: String, dueOn: Date?) {
        try? store?.createMilestone(projectID: project, title: title, dueOn: dueOn)
        requestSync()
    }

    func moveMilestone(_ id: UUID, to index: Int) {
        try? store?.moveMilestone(id: id, to: index)
        requestSync()
    }

    @discardableResult
    func createFeature(in project: UUID, title: String, note: String = "", branch: String? = nil,
                       milestoneID: UUID? = nil) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store else { return nil }
        let id = try? store.createFeature(projectID: project, title: trimmed, note: note, branch: branch,
                                          milestoneID: milestoneID)
        requestSync()
        return id
    }

    func updateFeature(_ id: UUID, title: String? = nil, note: String? = nil, milestoneID: UUID?? = nil,
                       branch: String?? = nil) {
        try? store?.updateFeature(id: id, title: title, note: note, milestoneID: milestoneID, branch: branch)
        requestSync()
    }

    func moveFeature(_ id: UUID, to index: Int) {
        try? store?.moveFeature(id: id, to: index)
        requestSync()
    }

    func deleteFeature(_ id: UUID) {
        try? store?.deleteFeature(id: id)
        requestSync()
    }

    func addMember(_ user: UUID, name: String, to project: UUID) {
        names[user] = name
        try? store?.addMember(projectID: project, userID: user)
        requestSync()
    }

    func removeMember(_ user: UUID, from project: UUID) {
        try? store?.removeMember(projectID: project, userID: user)
        requestSync()
    }
}

/// A project's colour by name, as the store keeps it.
typealias ProjectColourName = String
