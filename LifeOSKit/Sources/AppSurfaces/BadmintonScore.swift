import Foundation

/// Which side of the net, from the player's point of view.
public enum BadmintonSide: String, Codable, Sendable, CaseIterable {
    case us, them
    public var other: Self { self == .us ? .them : .us }
}

/// The half of the court a serve is delivered from.
public enum BadmintonServiceCourt: String, Codable, Sendable {
    case left, right
}

/// One game's points.
public struct BadmintonGame: Codable, Equatable, Sendable {
    public var us: Int
    public var them: Int
    public init(us: Int = 0, them: Int = 0) { self.us = us; self.them = them }
    public func points(_ side: BadmintonSide) -> Int { side == .us ? us : them }
    mutating func add(_ side: BadmintonSide) { if side == .us { us += 1 } else { them += 1 } }

    /// The winner under the Laws of Badminton: 21 points with a two-point
    /// lead, or the 30th point at 29-all, whichever comes first.
    public var winner: BadmintonSide? {
        for side in BadmintonSide.allCases {
            let mine = points(side), theirs = points(side.other)
            if mine == 30 || (mine >= 21 && mine - theirs >= 2) { return side }
        }
        return nil
    }
}

/// A match's score, stored as the rallies that produced it.
///
/// Only the rally winners are stored; games, server, service court and the
/// interval are all replayed from them. That makes undo exact (drop the last
/// rally, nothing else to keep in step), makes the watch and the phone agree
/// by construction when they exchange the list, and means a score cannot be
/// stored in a state the rules could not have produced.
public struct BadmintonScore: Codable, Equatable, Sendable {
    public var firstServer: BadmintonSide
    public private(set) var rallies: [BadmintonSide]

    /// Best of three games to 21 is at most 59 + 59 + 59 rallies.
    public static let rallyLimit = 177

    public init(firstServer: BadmintonSide = .us, rallies: [BadmintonSide] = []) {
        self.firstServer = firstServer
        self.rallies = rallies
    }

    /// Records a rally. Ignored once the match is decided, so a stray tap on
    /// the watch after match point cannot start a fourth game.
    public mutating func record(_ winner: BadmintonSide) {
        guard !isOver else { return }
        rallies.append(winner)
    }

    public mutating func undo() {
        if !rallies.isEmpty { rallies.removeLast() }
    }

    // MARK: - Replayed state

    private struct Replay {
        var games: [BadmintonGame] = []
        var current = BadmintonGame()
        var server: BadmintonSide
        var consumed = 0
    }

    private var replay: Replay {
        var state = Replay(server: firstServer)
        for winner in rallies {
            if Self.decided(state.games) { break }
            state.current.add(winner)
            state.server = winner
            state.consumed += 1
            if state.current.winner != nil {
                state.games.append(state.current)
                state.current = BadmintonGame()
            }
        }
        return state
    }

    private static func decided(_ games: [BadmintonGame]) -> Bool {
        BadmintonSide.allCases.contains { side in games.filter { $0.winner == side }.count >= 2 }
    }

    /// Finished games, in order.
    public var games: [BadmintonGame] { replay.games }
    /// The game in progress. Zero-zero between games and after the match.
    public var current: BadmintonGame { replay.current }
    public func gamesWon(by side: BadmintonSide) -> Int { games.filter { $0.winner == side }.count }
    public var isOver: Bool { Self.decided(replay.games) }
    public var winner: BadmintonSide? {
        BadmintonSide.allCases.first { gamesWon(by: $0) >= 2 }
    }
    /// The side serving the next rally: whoever won the last one.
    public var server: BadmintonSide { replay.server }

    /// Right on an even score, left on an odd one, counted on the server's
    /// own points. Holds for singles and, for the serving pair, for doubles.
    public var serviceCourt: BadmintonServiceCourt {
        current.points(server).isMultiple(of: 2) ? .right : .left
    }

    /// True on the rally that brings the leading side to 11 in the deciding
    /// game, the one moment the Laws have the players change ends mid-game.
    public var changesEndsNow: Bool {
        let state = replay
        guard state.games.count == 2, !isOver, let last = rallies.last else { return false }
        return state.current.points(last) == 11 && state.current.points(last.other) < 11
    }

    /// Every stored rally was playable: none after the match was decided and
    /// no more than a match can hold. Checked at the door, like the rest of
    /// what arrives from the watch.
    public var isValid: Bool {
        rallies.count <= Self.rallyLimit && replay.consumed == rallies.count
    }
}
