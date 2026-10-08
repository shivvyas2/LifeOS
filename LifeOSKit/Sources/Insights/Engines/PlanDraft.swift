import Foundation

/// A feature list LIFO drafted, for the owner to edit before anything is kept.
public struct PlanDraft: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable, Identifiable {
        public var id = UUID()
        public var title: String
        public var note: String
        public var branch: String
        public var milestone: String
        enum CodingKeys: String, CodingKey { case title, note, branch, milestone }
        public init(title: String, note: String, branch: String, milestone: String) {
            self.title = title; self.note = note; self.branch = branch; self.milestone = milestone
        }
    }
    public var features: [Item]
}

/// What the phone tells LIFO about a project. Bounded here and again on the
/// server: README 6,000 characters, 20 commit subjects, nudge 200.
public enum PlanPrompt {
    public static func make(name: String, scope: String, startsOn: Date?, endsOn: Date?, milestones: [String],
                            readme: String?, commits: [String], nudge: String?) -> String {
        var lines = ["Project: \(name)", "Scope: \(scope.isEmpty ? "(none given)" : scope)"]
        if let startsOn, let endsOn {
            lines.append("Dates: \(startsOn.formatted(.iso8601.year().month().day())) to \(endsOn.formatted(.iso8601.year().month().day()))")
        }
        if !milestones.isEmpty { lines.append("Milestones: " + milestones.joined(separator: "; ")) }
        if let readme, !readme.isEmpty { lines.append("README:\n" + String(readme.prefix(6_000))) }
        if !commits.isEmpty {
            lines.append("Recent commits:\n" + commits.prefix(20).map { "- " + String($0.prefix(120)) }.joined(separator: "\n"))
        }
        if let nudge, !nudge.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Nudge from the owner: " + String(nudge.prefix(200)))
        }
        return String(lines.joined(separator: "\n\n").prefix(12_000))
    }
}

public enum PlanDrafter {
    public static func draft(prompt: String, baseURL: URL, anonKey: String, accessToken: String,
                             session: URLSession = .shared) async throws -> PlanDraft {
        let request = try RemoteWire.request(baseURL: baseURL, anonKey: anonKey, accessToken: accessToken,
                                             taskName: "plan", prompt: prompt)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw RemoteEngineError.unavailable }
        return try RemoteWire.result(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
