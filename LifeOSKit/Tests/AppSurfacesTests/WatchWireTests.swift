import Foundation
import Testing
@testable import AppSurfaces

struct WatchWireTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func packetRoundTripsAndKeepsAbsence() throws {
        var packet = WatchPacket(sentAt: now)
        packet.heartRate = 141; packet.heartRateAt = now; packet.energyKcal = 88.4
        packet.reps = 7; packet.setIndex = 2; packet.completedSets = [12, 10]
        let data = try WatchWire.encode(packet)
        let back = try #require(WatchWire.packet(from: data))
        #expect(back == packet)
        #expect(WatchWire.packet(from: try WatchWire.encode(WatchPacket(sentAt: now)))?.reps == nil)
    }

    @Test func unknownVersionIsIgnored() throws {
        var packet = WatchPacket(sentAt: now); packet.v = 99
        #expect(WatchWire.packet(from: try WatchWire.encode(packet)) == nil)
        #expect(WatchWire.packet(from: Data("junk".utf8)) == nil)
    }

    @Test func commandRoundTrips() throws {
        let envelope = PhoneCommandEnvelope(command: .configure, sentAt: now, maxHeartRate: 187)
        let back = try #require(WatchWire.command(from: try WatchWire.encode(envelope)))
        #expect(back == envelope)
        #expect(WatchWire.command(from: try WatchWire.encode(WatchPacket(sentAt: now))) == nil)
    }

    @Test func removeRepCommandRoundTrips() throws {
        let envelope = PhoneCommandEnvelope(command: .removeRep, sentAt: now)
        let back = try #require(WatchWire.command(from: try WatchWire.encode(envelope)))
        #expect(back == envelope)
        #expect(back.command == .removeRep)
    }

    /// The two shapes share `v` and `sentAt`, so without `kind` a command
    /// decodes as an empty packet. Both directions have to refuse.
    @Test func aCommandIsNeverReadAsAPacket() throws {
        let envelope = PhoneCommandEnvelope(command: .discard, sentAt: now)
        #expect(WatchWire.packet(from: try WatchWire.encode(envelope)) == nil)
        #expect(WatchWire.command(from: try WatchWire.encode(envelope))?.command == .discard)
    }
}
