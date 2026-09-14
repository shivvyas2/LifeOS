import Foundation

/// Wall-clock based: backgrounding never stops the timer and pauses never count.
public struct ActivitySessionState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case running, paused, finished }
    public let id: UUID
    public let startedAt: Date
    public let activity: String
    public private(set) var phase: Phase
    public private(set) var accumulated: TimeInterval
    public private(set) var runningSince: Date?
    public private(set) var endedAt: Date?

    public init(activity: String, at date: Date = .now) {
        id = UUID(); startedAt = date; self.activity = activity
        phase = .running; accumulated = 0; runningSince = date
    }
    public func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    public mutating func pause(at date: Date = .now) {
        guard phase == .running else { return }
        accumulated = elapsed(at: date); runningSince = nil; phase = .paused
    }
    public mutating func resume(at date: Date = .now) {
        guard phase == .paused else { return }
        runningSince = date; phase = .running
    }
    public mutating func finish(at date: Date = .now) {
        guard phase != .finished else { return }
        accumulated = elapsed(at: date); runningSince = nil; endedAt = date; phase = .finished
    }
}

/// Who runs the HealthKit session. The phone when no watch is nearby, the
/// watch when it is; the draft keeps the answer so a relaunch knows.
public enum SessionSource: String, Codable, Sendable { case phone, watch }

/// Bluetooth SIG Heart Rate Measurement, supporting both 8-bit and 16-bit values.
public enum HeartRateMeasurement {
    public static func beatsPerMinute(_ data: Data) -> Int? {
        let bytes = Array(data)
        guard bytes.count >= 2 else { return nil }
        // When supported, a sensor reporting no skin contact is not a reading.
        if bytes[0] & 0x04 != 0 && bytes[0] & 0x02 == 0 { return nil }
        let bpm: Int
        if bytes[0] & 1 == 0 { bpm = Int(bytes[1]) }
        else {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | Int(bytes[2]) << 8
        }
        return (20...250).contains(bpm) ? bpm : nil
    }
}
