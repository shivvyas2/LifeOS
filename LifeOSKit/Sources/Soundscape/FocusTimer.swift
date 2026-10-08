import Foundation

public enum TimerPlan: Codable, Equatable, Sendable {
    /// `blocks` nil runs until ended.
    case pomodoro(work: TimeInterval, rest: TimeInterval, longRest: TimeInterval, longEvery: Int, blocks: Int?)
    /// nil is open-ended.
    case countdown(TimeInterval?)
    /// nil plays all night without fading.
    case fade(TimeInterval?)
}

public enum TimerPhase: Codable, Equatable, Sendable {
    case work(block: Int)
    case rest(afterBlock: Int)
    case longRest(afterBlock: Int)
    case open
    case fading
    case finished
}

public struct TimerReading: Equatable, Sendable {
    public var phase: TimerPhase
    public var phaseLength: TimeInterval?
    public var remaining: TimeInterval?
    public var completedBlocks: Int
    public var focusedSeconds: TimeInterval
    public var isPaused: Bool
    public var progress: Double? {
        guard let phaseLength, phaseLength > 0, let remaining else { return nil }
        return 1 - remaining / phaseLength
    }
}

public struct PhaseEnd: Equatable, Sendable {
    public var ending: TimerPhase
    public var next: TimerPhase
    public var at: Date
}

/// The session clock: a run of segments (work, breaks, a countdown, a
/// fade) measured from wall-clock dates, so a suspended app reads it right.
public struct FocusTimer: Codable, Equatable, Sendable {
    public let plan: TimerPlan
    private var segment = 0
    private var segmentStart: Date
    private var pausedAt: Date?
    /// Focused seconds from segments before `segment`.
    private var banked: TimeInterval = 0
    /// Work blocks cut short by a skip: they count as focus time, not as
    /// completed blocks.
    private var skippedBlocks = 0

    public init(plan: TimerPlan, startedAt: Date) {
        self.plan = plan
        self.segmentStart = startedAt
    }

    private var segmentCount: Int? {
        switch plan {
        case .pomodoro(_, _, _, _, let blocks): blocks.map { 2 * $0 - 1 }
        case .countdown, .fade: 1
        }
    }

    private func phase(of index: Int) -> TimerPhase {
        if let count = segmentCount, index >= count { return .finished }
        switch plan {
        case .pomodoro(_, _, _, let every, _):
            if index % 2 == 0 { return .work(block: index / 2 + 1) }
            let block = (index + 1) / 2
            return block % max(1, every) == 0 ? .longRest(afterBlock: block) : .rest(afterBlock: block)
        case .countdown: return .open
        case .fade(let length): return length == nil ? .open : .fading
        }
    }

    private func length(of index: Int) -> TimeInterval? {
        switch plan {
        case .pomodoro(let work, let rest, let longRest, _, _):
            if index % 2 == 0 { return work }
            if case .longRest = phase(of: index) { return longRest }
            return rest
        case .countdown(let length), .fade(let length): return length
        }
    }

    private func counts(_ index: Int) -> Bool {
        if case .pomodoro = plan { return index % 2 == 0 }
        return true
    }

    private func completed(before index: Int) -> Int {
        guard case .pomodoro = plan else { return 0 }
        return max(0, (index + 1) / 2 - skippedBlocks)
    }

    /// The segment holding `clock`, its start, and the focus banked before it.
    private func locate(_ clock: Date) -> (index: Int, start: Date, banked: TimeInterval) {
        var index = segment, start = segmentStart, total = banked
        while true {
            if let count = segmentCount, index >= count { break }
            guard let length = length(of: index), clock.timeIntervalSince(start) >= length else { break }
            if counts(index) { total += length }
            start = start.addingTimeInterval(length)
            index += 1
        }
        return (index, start, total)
    }

    public func reading(at now: Date) -> TimerReading {
        let clock = pausedAt ?? now
        let (index, start, total) = locate(clock)
        let phase = phase(of: index)
        if phase == .finished {
            return TimerReading(phase: .finished, phaseLength: nil, remaining: nil,
                                completedBlocks: completed(before: index), focusedSeconds: total, isPaused: pausedAt != nil)
        }
        let elapsed = max(0, clock.timeIntervalSince(start))
        let length = length(of: index)
        return TimerReading(phase: phase, phaseLength: length, remaining: length.map { max(0, $0 - elapsed) },
                            completedBlocks: completed(before: index),
                            focusedSeconds: total + (counts(index) ? elapsed : 0), isPaused: pausedAt != nil)
    }

    private mutating func settle(at now: Date) {
        let (index, start, total) = locate(pausedAt ?? now)
        segment = index; segmentStart = start; banked = total
    }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        settle(at: now)
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        segmentStart = segmentStart.addingTimeInterval(now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    public mutating func skip(at now: Date) {
        settle(at: now)
        if let count = segmentCount, segment >= count { return }
        let clock = pausedAt ?? now
        if counts(segment) {
            let elapsed = max(0, clock.timeIntervalSince(segmentStart))
            banked += min(elapsed, length(of: segment) ?? elapsed)
            if case .pomodoro = plan, let length = length(of: segment), elapsed < length { skippedBlocks += 1 }
        }
        segment += 1
        segmentStart = clock
    }

    /// The next boundaries, for notifications. Empty while paused.
    public func upcomingEnds(after now: Date, limit: Int) -> [PhaseEnd] {
        guard pausedAt == nil else { return [] }
        var (index, start, _) = locate(now)
        var ends: [PhaseEnd] = []
        while ends.count < limit, phase(of: index) != .finished, let length = length(of: index) {
            let end = start.addingTimeInterval(length)
            ends.append(PhaseEnd(ending: phase(of: index), next: phase(of: index + 1), at: end))
            start = end
            index += 1
        }
        return ends
    }
}

extension SoundPhase {
    public init(_ reading: TimerReading) {
        switch reading.phase {
        case .work:
            if let remaining = reading.remaining, remaining <= 60 { self = .closing(1 - remaining / 60) } else { self = .work }
        case .rest, .longRest: self = .rest
        case .open: self = .work
        case .fading: self = .fading(reading.progress ?? 0)
        case .finished: self = .fading(1)
        }
    }
}
