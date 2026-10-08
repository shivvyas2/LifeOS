/// The four soundscapes. Like Endel's modes, each holds attention without
/// asking for it: little melody, slow change.
public enum Mood: String, CaseIterable, Codable, Sendable {
    case focus, brainstorm, relax, sleep

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .brainstorm: "Brainstorm"
        case .relax: "Relax"
        case .sleep: "Sleep"
        }
    }

    /// What to search the Apple Music catalog for when nothing personal fits.
    public var musicSearchTerm: String {
        switch self {
        case .focus: "focus"
        case .brainstorm: "upbeat instrumental"
        case .relax: "calm ambient"
        case .sleep: "sleep"
        }
    }

    /// Words that mark a personal recommendation as right for this mood.
    public var musicKeywords: [String] {
        switch self {
        case .focus: ["focus", "study", "deep work", "concentration"]
        case .brainstorm: ["creative", "upbeat", "energy", "flow"]
        case .relax: ["calm", "chill", "relax", "ambient"]
        case .sleep: ["sleep"]
        }
    }
}

/// A steady sound under the music. Auto follows the weather.
public enum Texture: String, CaseIterable, Codable, Sendable {
    case auto, none, rain, wind, brown

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .none: "None"
        case .rain: "Rain"
        case .wind: "Wind"
        case .brown: "Brown noise"
        }
    }
}

/// The renderer's layers. The raw value indexes `SoundParameters.gains`.
public enum Layer: Int, CaseIterable, Sendable {
    case pad, bell, pluck, pulse, drone, bed, texture
}
