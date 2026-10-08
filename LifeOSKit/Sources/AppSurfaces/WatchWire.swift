import Foundation

/// What the watch sends the phone over the mirrored session's data channel.
/// Every reading is optional: a packet without heart rate says "no reading",
/// never zero. `completedSets` holds reps per finished set, oldest first.
public struct WatchPacket: Codable, Equatable, Sendable {
    /// Names the shape, so the version gate can tell a packet from a command:
    /// both carry `v` and `sentAt`, and nothing else is required.
    public var kind: String = WatchWire.packetKind
    public var v: Int = WatchWire.version
    public var sentAt: Date
    public var sessionID: UUID?
    public var ownerID: String?
    public var elapsed: TimeInterval?
    public var paused: Bool?
    public var distanceMeters: Double?
    public var heartRate: Int?
    public var heartRateAt: Date?
    public var energyKcal: Double?
    public var swingCount: Int?
    public var peakWristRotation: Double?
    public var reps: Int?
    public var setIndex: Int?
    public var completedSets: [Int]?
    /// The badminton session as the watch holds it, score included. The
    /// watch owns the score while it owns the workout; the phone shows this.
    public var badminton: BadmintonSession?

    public init(sentAt: Date) { self.sentAt = sentAt }
}

/// What the phone asks the watch to do. `configure` carries the person's
/// maximum heart rate once so the watch can show a zone chip.
/// `end` finishes the workout and saves it to Health on the wrist; `discard`
/// throws it away. The phone sends `discard` when it refuses a mirrored
/// session or the person discards, so nothing half-recorded reaches Health.
///
/// `scoreUs`, `scoreThem` and `undoRally` are the phone's scoreboard taps on a
/// watch-owned badminton match. Like `addRep`, they echo back in the next
/// packet rather than changing the phone's copy, so the two cannot disagree.
extension WatchWire {
    /// A focus session is heart rate only: the phone may only throw it away,
    /// never end (and so save), pause or configure it like a workout.
    public static func phoneMayDrive(_ command: PhoneCommand, focusSession: Bool) -> Bool {
        !focusSession || command == .discard
    }
}

public enum PhoneCommand: String, Codable, Sendable {
    case configure, pause, resume, end, nextSet, addRep, removeRep, discard
    case scoreUs, scoreThem, undoRally
}

public struct PhoneCommandEnvelope: Codable, Equatable, Sendable {
    public var kind: String = WatchWire.commandKind
    public var v: Int = WatchWire.version
    public var command: PhoneCommand
    public var sentAt: Date
    public var maxHeartRate: Int?
    /// Sent with `configure`: the match or practice set up on the phone
    /// before the watch took the workout.
    public var badminton: BadmintonSession?
    /// Sent with `configure`: the phone's athlete profile, so a workout the
    /// phone started on a Watch that never received the profile can still
    /// analyze swings. Absent from older phones, which the Watch tolerates.
    public var athlete: ActivityAthleteProfile?

    public init(command: PhoneCommand, sentAt: Date, maxHeartRate: Int? = nil, badminton: BadmintonSession? = nil,
                athlete: ActivityAthleteProfile? = nil) {
        self.command = command; self.sentAt = sentAt; self.maxHeartRate = maxHeartRate; self.badminton = badminton
        self.athlete = athlete
    }
}

/// Encoding and the version gate in one place, shared by both devices.
public enum WatchWire {
    public static let version = 2
    public static let packetKind = "packet"
    public static let commandKind = "command"

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func packet(from data: Data) -> WatchPacket? {
        guard let packet = try? decoder.decode(WatchPacket.self, from: data),
              packet.kind == packetKind, packet.v == version else { return nil }
        return packet
    }

    public static func command(from data: Data) -> PhoneCommandEnvelope? {
        guard let envelope = try? decoder.decode(PhoneCommandEnvelope.self, from: data),
              envelope.kind == commandKind, envelope.v == version else { return nil }
        return envelope
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
