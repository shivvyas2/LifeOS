import Foundation

public enum SoundSource: String, CaseIterable, Codable, Sendable {
    case soundscape, appleMusic, silence
    public var title: String {
        switch self { case .soundscape: "Soundscape"; case .appleMusic: "Apple Music"; case .silence: "Silence" }
    }
}

public struct TimerPreset: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
}

extension Mood {
    public var presets: [TimerPreset] {
        switch self {
        case .focus, .brainstorm:
            [.init(id: "25-5", title: "25 / 5"), .init(id: "50-10", title: "50 / 10"), .init(id: "90-20", title: "90 / 20")]
        case .relax:
            [.init(id: "10", title: "10 min"), .init(id: "20", title: "20 min"), .init(id: "30", title: "30 min"), .init(id: "open", title: "Open")]
        case .sleep:
            [.init(id: "15", title: "15 min"), .init(id: "30", title: "30 min"), .init(id: "60", title: "60 min"), .init(id: "night", title: "All night")]
        }
    }

    var standardPresetID: String {
        switch self { case .focus, .brainstorm: "25-5"; case .relax: "20"; case .sleep: "30" }
    }
}

public struct FocusSetup: Codable, Equatable, Sendable {
    public var mood: Mood
    public var source: SoundSource
    public var presetID: String
    /// Pomodoro block count; nil runs until ended.
    public var blocks: Int?
    public var texture: Texture

    public init(mood: Mood, source: SoundSource = .soundscape, presetID: String, blocks: Int? = 4, texture: Texture = .auto) {
        self.mood = mood; self.source = source; self.presetID = presetID; self.blocks = blocks; self.texture = texture
    }

    public static func standard(for mood: Mood) -> FocusSetup { FocusSetup(mood: mood, presetID: mood.standardPresetID) }

    public var plan: TimerPlan {
        let id = mood.presets.contains { $0.id == presetID } ? presetID : mood.standardPresetID
        switch (mood, id) {
        case (.focus, "50-10"), (.brainstorm, "50-10"): return .pomodoro(work: 3000, rest: 600, longRest: 1200, longEvery: 4, blocks: blocks)
        case (.focus, "90-20"), (.brainstorm, "90-20"): return .pomodoro(work: 5400, rest: 1200, longRest: 1800, longEvery: 4, blocks: blocks)
        case (.focus, _), (.brainstorm, _): return .pomodoro(work: 1500, rest: 300, longRest: 900, longEvery: 4, blocks: blocks)
        case (.relax, "open"): return .countdown(nil)
        case (.relax, let minutes): return .countdown((Double(minutes) ?? 20) * 60)
        case (.sleep, "night"): return .fade(nil)
        case (.sleep, let minutes): return .fade((Double(minutes) ?? 30) * 60)
        }
    }
}

/// What each mood was last set to, so Start is one tap.
public struct FocusPreferences: Codable, Equatable, Sendable {
    public private(set) var lastMood: Mood = .focus
    private var perMood: [String: FocusSetup] = [:]

    public init() {}

    public func setup(for mood: Mood) -> FocusSetup { perMood[mood.rawValue] ?? .standard(for: mood) }

    public mutating func remember(_ setup: FocusSetup) {
        perMood[setup.mood.rawValue] = setup
        lastMood = setup.mood
    }

    public static func load(from defaults: UserDefaults, key: String) -> FocusPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(FocusPreferences.self, from: data) else { return FocusPreferences() }
        return prefs
    }

    public func save(to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}

public enum MusicAvailability: Equatable, Sendable { case available, notSubscribed, denied, unknown }

/// Apple Music only when it can play; otherwise a soundscape and one line why.
public func resolveSource(_ requested: SoundSource, music: MusicAvailability) -> (source: SoundSource, notice: String?) {
    guard requested == .appleMusic else { return (requested, nil) }
    switch music {
    case .available: return (.appleMusic, nil)
    case .notSubscribed: return (.soundscape, "Apple Music needs a subscription. Playing a soundscape instead.")
    case .denied: return (.soundscape, "Allow Apple Music for Almanac in Settings. Playing a soundscape instead.")
    case .unknown: return (.soundscape, "Apple Music isn't available right now. Playing a soundscape instead.")
    }
}
