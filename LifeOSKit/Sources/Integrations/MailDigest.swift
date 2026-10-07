import Foundation

public enum MailBucket: String, Codable, Sendable { case needsYou, fyi }

public struct MailVerdict: Codable, Equatable, Sendable {
    public let bucket: MailBucket
    public let summary: String
    public init(bucket: MailBucket, summary: String) { self.bucket = bucket; self.summary = summary }
}

/// What Today shows: NEEDS YOU first, then FYI, newest first in each, at
/// most five rows, and never an FYI in place of something that needs you.
public struct MailDigest: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let item: MailItem
        public let summary: String
        public var id: String { item.id }
    }

    public let needsYou: [Row]
    public let fyi: [Row]
    public let needsYouCount: Int

    public static let rows = 5

    public static func make(items: [MailItem], verdicts: [String: MailVerdict]) -> MailDigest {
        let ordered = items.sorted { $0.receivedAt > $1.receivedAt }
        let rows = ordered.map { item -> (Row, MailBucket) in
            let verdict = verdicts[item.id] ?? MailFallback.verdict(for: item)
            return (Row(item: item, summary: verdict.summary), verdict.bucket)
        }
        let urgent = rows.filter { $0.1 == .needsYou }.map(\.0)
        let rest = rows.filter { $0.1 == .fyi }.map(\.0)
        let shownUrgent = Array(urgent.prefix(Self.rows))
        let shownRest = Array(rest.prefix(max(Self.rows - shownUrgent.count, 0)))
        return MailDigest(needsYou: shownUrgent, fyi: shownRest, needsYouCount: urgent.count)
    }
}

/// When the on-device model cannot judge: FYI, and Gmail's snippet as the line.
public enum MailFallback {
    public static func verdict(for item: MailItem) -> MailVerdict {
        MailVerdict(bucket: .fyi, summary: shorten(clean(item.snippet.isEmpty ? item.subject : item.snippet)))
    }

    static func clean(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&#39;", "'"), ("&quot;", "\""), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shorten(_ text: String, limit: Int = 90) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit - 1)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Each message judged once: verdicts kept per message id in the account's
/// defaults, the newest 200.
public struct MailVerdictCache {
    private let defaults: UserDefaults
    private static let key = "gmail.verdicts"
    private struct Entry: Codable { let verdict: MailVerdict; let at: Date }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    private func all() -> [String: Entry] {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    public var count: Int { all().count }

    public func verdict(for id: String) -> MailVerdict? { all()[id]?.verdict }

    public func store(_ verdict: MailVerdict, for id: String) {
        var entries = all()
        let stamp = (entries.values.map(\.at).max() ?? .distantPast).addingTimeInterval(1)
        entries[id] = Entry(verdict: verdict, at: max(stamp, .now))
        let kept = entries.sorted { $0.value.at > $1.value.at }.prefix(200)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
