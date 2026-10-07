import Foundation

public enum ProjectStatus: String, CaseIterable, Codable, Sendable {
    case todo, doing, done

    public var label: String {
        switch self {
        case .todo: "TO DO"
        case .doing: "DOING"
        case .done: "DONE"
        }
    }
}

/// Done over total, for a project or a milestone.
public enum ProjectProgress {
    public static func of(_ statuses: [ProjectStatus]) -> (done: Int, total: Int, fraction: Double) {
        let done = statuses.filter { $0 == .done }.count
        // An empty project reads nothing done, not a division by zero.
        return (done, statuses.count, statuses.isEmpty ? 0 : Double(done) / Double(statuses.count))
    }
}

public struct BoardCard: Equatable, Sendable {
    public let id: UUID
    public var status: ProjectStatus
    public var position: Int
    public var doneAt: Date?

    public init(id: UUID, status: ProjectStatus, position: Int, doneAt: Date?) {
        self.id = id; self.status = status; self.position = position; self.doneAt = doneAt
    }
}

/// A card dropped into a column at a position: both columns renumbered from
/// zero, `doneAt` stamped on the way into Done and cleared on the way out.
public enum BoardMove {
    public static func move(_ id: UUID, to status: ProjectStatus, at index: Int,
                            in cards: [BoardCard], now: Date) -> [BoardCard] {
        guard var moving = cards.first(where: { $0.id == id }) else { return cards }
        let from = moving.status
        if status == .done, from != .done { moving.doneAt = now }
        if status != .done { moving.doneAt = nil }
        moving.status = status

        var target = cards.filter { $0.status == status && $0.id != id }.sorted { $0.position < $1.position }
        target.insert(moving, at: min(max(index, 0), target.count))
        var result: [UUID: BoardCard] = [:]
        for (position, var card) in target.enumerated() { card.position = position; result[card.id] = card }
        if from != status {
            let source = cards.filter { $0.status == from && $0.id != id }.sorted { $0.position < $1.position }
            for (position, var card) in source.enumerated() { card.position = position; result[card.id] = card }
        }
        return cards.map { result[$0.id] ?? $0 }
    }
}

public struct TimeBlock: Equatable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public init(id: UUID, start: Date, end: Date) { self.id = id; self.start = start; self.end = end }
}

/// Places a day's time blocks in lanes: overlapping blocks side by side, each
/// in the lowest lane free at its start; every block in a run of overlaps
/// shares that run's lane count.
public enum ScheduleLayout {
    public static func lanes(_ blocks: [TimeBlock]) -> [UUID: (lane: Int, lanes: Int)] {
        let sorted = blocks.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [UUID: (lane: Int, lanes: Int)] = [:]
        var cluster: [UUID] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func close() {
            for id in cluster { result[id] = (result[id]?.lane ?? 0, laneEnds.count) }
            cluster = []; laneEnds = []
        }
        for block in sorted {
            if block.start >= clusterEnd, !cluster.isEmpty { close() }
            if let free = laneEnds.firstIndex(where: { $0 <= block.start }) {
                laneEnds[free] = block.end
                result[block.id] = (free, 0)
            } else {
                laneEnds.append(block.end)
                result[block.id] = (laneEnds.count - 1, 0)
            }
            cluster.append(block.id)
            clusterEnd = max(clusterEnd, block.end)
        }
        close()
        return result
    }
}

/// A year of daily counts as five levels: 0 for none, then 1 to 4 by the
/// quartiles of the days that had any.
public enum ContributionScale {
    public static func levels(_ counts: [Int]) -> [Int] {
        let active = counts.filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return counts.map { _ in 0 } }
        func quartile(_ q: Double) -> Int { active[Int(floor(q * Double(active.count - 1)))] }
        let q1 = quartile(0.25), q2 = quartile(0.5), q3 = quartile(0.75)
        return counts.map { count in
            if count <= 0 { return 0 }
            if count <= q1 { return 1 }
            if count <= q2 { return 2 }
            if count <= q3 { return 3 }
            return 4
        }
    }
}

/// Whether a pulled row should leave the local one alone: only when the local
/// row carries an edit not yet pushed and newer than the server's.
public enum ProjectMerge {
    public static func keepLocal(localUpdatedAt: Date, localSyncedAt: Date?, remoteUpdatedAt: Date) -> Bool {
        let unsynced = localSyncedAt.map { localUpdatedAt > $0 } ?? true
        return unsynced && localUpdatedAt > remoteUpdatedAt
    }
}
