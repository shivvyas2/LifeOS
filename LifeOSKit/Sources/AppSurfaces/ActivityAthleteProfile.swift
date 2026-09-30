import Foundation

/// Stored in the account's defaults on iPhone; the Watch receives an owner-bound copy.
public struct ActivityAthleteProfile: Codable, Equatable, Sendable {
    public enum Side: String, Codable, CaseIterable, Sendable { case left, right }
    public var heightCM: Double?
    public var weightKG: Double?
    public var playingHand: Side
    public var watchWrist: Side
    public var motionEnabled: Bool
    public var updatedAt: Date
    public init(heightCM: Double? = nil, weightKG: Double? = nil, playingHand: Side = .right,
                watchWrist: Side = .left, motionEnabled: Bool = false, updatedAt: Date = .now) {
        self.heightCM = heightCM; self.weightKG = weightKG; self.playingHand = playingHand
        self.watchWrist = watchWrist; self.motionEnabled = motionEnabled; self.updatedAt = updatedAt
    }
    public var canAnalyzeSwings: Bool { motionEnabled && playingHand == watchWrist }
    public var isValid: Bool {
        (heightCM.map { $0.isFinite && (80...250).contains($0) } ?? true)
        && (weightKG.map { $0.isFinite && (20...350).contains($0) } ?? true)
    }
    public static let storageKey = "activity.athlete.v1"
    public static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: storageKey), let profile = try? JSONDecoder().decode(Self.self, from: data), profile.isValid else { return nil }
        return profile
    }
    public func save(to defaults: UserDefaults) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
