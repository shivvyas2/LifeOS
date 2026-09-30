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
    public var reps: Int?
    public var setIndex: Int?
    public var completedSets: [Int]?

    public init(sentAt: Date) { self.sentAt = sentAt }
}

/// What the phone asks the watch to do. `configure` carries the person's
/// maximum heart rate once so the watch can show a zone chip.
/// `end` finishes the workout and saves it to Health on the wrist; `discard`
/// throws it away. The phone sends `discard` when it refuses a mirrored
/// session or the person discards, so nothing half-recorded reaches Health.
public enum PhoneCommand: String, Codable, Sendable {
    case configure, pause, resume, end, nextSet, addRep, removeRep, discard
}

public struct PhoneCommandEnvelope: Codable, Equatable, Sendable {
    public var kind: String = WatchWire.commandKind
    public var v: Int = WatchWire.version
    public var command: PhoneCommand
    public var sentAt: Date
    public var maxHeartRate: Int?

    public init(command: PhoneCommand, sentAt: Date, maxHeartRate: Int? = nil) {
        self.command = command; self.sentAt = sentAt; self.maxHeartRate = maxHeartRate
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
