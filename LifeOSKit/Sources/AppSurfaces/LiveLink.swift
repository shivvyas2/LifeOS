import Foundation

/// Where a live session's readings come from, and whether they are still
/// arriving. Shown at the top of the live screen so a stale number is never
/// mistaken for a live one.
public enum LiveLink: Equatable, Sendable {
    /// The watch owns the workout and its packets are arriving.
    case watchLive
    /// The watch owns the workout but nothing has arrived for a while.
    case watchQuiet(seconds: Int)
    /// The mirrored session dropped; the watch keeps recording on its own.
    case watchDisconnected
    /// The phone records, with a heart rate strap whose beats are arriving.
    case sensorLive(name: String)
    /// A strap is connected but has gone quiet.
    case sensorQuiet(name: String, seconds: Int)
    /// The phone records with nothing feeding it heart rate.
    case noSource
    /// The session is paused; freshness does not apply.
    case paused

    /// Watch packets come every one to five seconds; three missed heartbeats
    /// is when quiet becomes worth saying.
    public static let watchQuietAfter: TimeInterval = 15
    /// A strap beats every second; fifteen without one is a dropped link.
    public static let sensorQuietAfter: TimeInterval = 15

    public static func assess(watchOwned: Bool, watchReachable: Bool, lastWatchPacket: Date?,
                              sensorName: String?, lastHeartRate: Date?, paused: Bool, now: Date) -> LiveLink {
        if paused { return .paused }
        if watchOwned {
            guard watchReachable else { return .watchDisconnected }
            guard let last = lastWatchPacket else { return .watchQuiet(seconds: 0) }
            let age = now.timeIntervalSince(last)
            return age < watchQuietAfter ? .watchLive : .watchQuiet(seconds: Int(age))
        }
        // Heart rate can reach a phone session with no strap connected, from
        // Apple Health. Fresh beats are live whatever their source is called.
        guard let sensorName else {
            if let last = lastHeartRate, now.timeIntervalSince(last) < sensorQuietAfter { return .sensorLive(name: "Heart rate") }
            return .noSource
        }
        guard let last = lastHeartRate else { return .sensorQuiet(name: sensorName, seconds: 0) }
        let age = now.timeIntervalSince(last)
        return age < sensorQuietAfter ? .sensorLive(name: sensorName) : .sensorQuiet(name: sensorName, seconds: Int(age))
    }

    /// True only when readings are arriving right now.
    public var isLive: Bool {
        switch self { case .watchLive, .sensorLive: true; default: false }
    }

    public var title: String {
        switch self {
        case .watchLive: "Apple Watch · live"
        case .watchQuiet(let seconds): seconds > 0 ? "Apple Watch · last reading \(Self.age(seconds)) ago" : "Apple Watch · waiting for the first reading"
        case .watchDisconnected: "Apple Watch disconnected · still recording on the watch"
        case .sensorLive(let name): "\(name) · live"
        case .sensorQuiet(let name, let seconds): seconds > 0 ? "\(name) · last beat \(Self.age(seconds)) ago" : "\(name) · waiting for a beat"
        case .noSource: "No heart rate source · timing only"
        case .paused: "Paused"
        }
    }

    static func age(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }
}

/// Swings per minute from the moments the swing count went up: intensity
/// rather than a running total, which only ever grows.
public enum SwingPace {
    public static func perMinute(_ moments: [Date], now: Date) -> Int {
        moments.filter { now.timeIntervalSince($0) <= 60 && $0 <= now }.count
    }
}
