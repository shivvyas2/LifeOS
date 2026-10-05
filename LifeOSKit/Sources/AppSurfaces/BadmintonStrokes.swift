import Foundation

public enum BadmintonStroke: String, Codable, Sendable, CaseIterable {
    case forehand, backhand
    public var title: String { self == .forehand ? "Forehand" : "Backhand" }
}

/// The shots a player can tag. Not detected: a wrist cannot tell a clear
/// from a drop without labelled examples, so these come only from the
/// player, and those tags are what a classifier would later learn from.
public enum BadmintonShotType: String, Codable, Sendable, CaseIterable {
    case serve, clear, drop, smash, drive, net, lift
    public var title: String { rawValue.capitalized }
}

/// What the player said about one swing candidate.
public struct BadmintonShotTag: Codable, Equatable, Sendable {
    public var stroke: BadmintonStroke?
    public var type: BadmintonShotType?
    /// The candidate was not a shot at all: a practice swing, a wave.
    public var notAShot: Bool
    public init(stroke: BadmintonStroke? = nil, type: BadmintonShotType? = nil, notAShot: Bool = false) {
        self.stroke = stroke; self.type = type; self.notAShot = notAShot
    }
    public var isEmpty: Bool { stroke == nil && type == nil && !notAShot }
}

/// Tags for one session, keyed by `SwingEvent.id`.
public struct BadmintonShotTags: Codable, Equatable, Sendable {
    public var byEvent: [Int: BadmintonShotTag] = [:]
    public init() {}
    public subscript(id: Int) -> BadmintonShotTag? {
        get { byEvent[id] }
        set { byEvent[id] = newValue?.isEmpty == true ? nil : newValue }
    }
}

/// Forehand or backhand, from the twist of the forearm.
public enum StrokeClassifier {
    /// Mean twist below this (rad/s) is too small to call either way.
    public static let threshold = 1.0

    /// Which twist sign is a forehand for this player: +1, -1, or nil when
    /// the tags do not say. Each tagged swing with a clear twist votes; a
    /// convention needs a margin of two votes, so one mis-tap cannot set it.
    public static func convention(events: [SwingEvent], tags: BadmintonShotTags) -> Double? {
        var votes = 0
        for event in events {
            guard let stroke = tags[event.id]?.stroke, let twist = event.twist, abs(twist) >= threshold else { continue }
            let sign = twist > 0 ? 1 : -1
            votes += stroke == .forehand ? sign : -sign
        }
        guard abs(votes) >= 2 else { return nil }
        return votes > 0 ? 1 : -1
    }

    /// The player's tag when there is one; otherwise the convention's call,
    /// or nil when there is no convention yet or the twist is too small.
    public static func stroke(of event: SwingEvent, convention: Double?, tags: BadmintonShotTags) -> BadmintonStroke? {
        if let tagged = tags[event.id]?.stroke { return tagged }
        guard let convention, let twist = event.twist, abs(twist) >= threshold else { return nil }
        return twist * convention > 0 ? .forehand : .backhand
    }

    public struct Side: Equatable, Sendable {
        public var count = 0
        public var averagePeak: Double?
    }
    public struct Summary: Equatable, Sendable {
        public var forehand = Side()
        public var backhand = Side()
        /// Shots whose side could not be called.
        public var unclear = 0
        public var types: [BadmintonShotType: Int] = [:]
        /// The side with the higher average wrist speed, when both have
        /// enough swings (three) for the comparison to mean something.
        public var stronger: BadmintonStroke? {
            guard forehand.count >= 1, backhand.count >= 1,
                  forehand.count + backhand.count >= 3,
                  let fore = forehand.averagePeak, let back = backhand.averagePeak, fore != back else { return nil }
            return fore > back ? .forehand : .backhand
        }
    }

    /// Per-side counts and average peak wrist speed, leaving out candidates
    /// the player marked as not a shot.
    public static func summary(events: [SwingEvent], convention: Double?, tags: BadmintonShotTags) -> Summary {
        var result = Summary()
        var forePeaks: [Double] = [], backPeaks: [Double] = []
        for event in events where tags[event.id]?.notAShot != true {
            if let type = tags[event.id]?.type { result.types[type, default: 0] += 1 }
            switch stroke(of: event, convention: convention, tags: tags) {
            case .forehand: forePeaks.append(event.peakRotation)
            case .backhand: backPeaks.append(event.peakRotation)
            case nil: result.unclear += 1
            }
        }
        result.forehand = Side(count: forePeaks.count, averagePeak: forePeaks.isEmpty ? nil : forePeaks.reduce(0, +) / Double(forePeaks.count))
        result.backhand = Side(count: backPeaks.count, averagePeak: backPeaks.isEmpty ? nil : backPeaks.reduce(0, +) / Double(backPeaks.count))
        return result
    }
}
