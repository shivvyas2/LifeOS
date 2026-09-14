import Foundation

/// What the watch sends the phone over the mirrored session's data channel.
/// Every reading is optional: a packet without heart rate says "no reading",
/// never zero. `completedSets` holds reps per finished set, oldest first.
public struct WatchPacket: Codable, Equatable, Sendable {
    public var v: Int = WatchWire.version
    public var sentAt: Date
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
public enum PhoneCommand: String, Codable, Sendable {
    case configure, pause, resume, end, nextSet, addRep
}

public struct PhoneCommandEnvelope: Codable, Equatable, Sendable {
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
    public static let version = 1

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func packet(from data: Data) -> WatchPacket? {
        guard let packet = try? decoder.decode(WatchPacket.self, from: data), packet.v == version else { return nil }
        return packet
    }

    public static func command(from data: Data) -> PhoneCommandEnvelope? {
        guard let envelope = try? decoder.decode(PhoneCommandEnvelope.self, from: data), envelope.v == version else { return nil }
        return envelope
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
