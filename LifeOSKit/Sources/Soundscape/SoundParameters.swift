import Foundation

public enum TextureKind: Int, Equatable, Sendable {
    case none, rain, wind, brown, hiss

    init(_ texture: Texture, weather: WeatherInput?) {
        switch texture {
        case .none: self = .none
        case .rain: self = .rain
        case .wind: self = .wind
        case .brown: self = .brown
        case .auto:
            guard let weather else { self = .none; return }
            if weather.kind == .rain { self = .rain }
            else if weather.kind == .snow { self = .hiss }
            else if weather.windKph > 30 { self = .wind }
            else { self = .none }
        }
    }
}

/// The knobs the renderer turns. A trivial value type, so the audio thread
/// can copy it without touching reference counts.
public struct SoundParameters: Equatable, Sendable {
    public var mood: Mood
    /// Semitones from the recipe's root.
    public var keyOffset: Int
    public var tempo: Double
    /// Seconds per breath for the moods without a beat.
    public var breathPeriod: Double?
    public var density: Double
    public var brightness: Double
    public var reverb: Double
    public var gains: SIMD8<Double>
    public var texture: TextureKind
    public var master: Double
    /// The noise bed's colour: 0 pink, 1 brown.
    public var bedColour: Double

    /// A 4/4 bar, or one breath.
    public var barSeconds: Double { breathPeriod ?? 4 * 60 / tempo }

    static let textureGain = 0.22

    public static func make(_ recipe: MoodRecipe, _ c: Conditions) -> SoundParameters {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = c.timeZone
        let time = TimeOfDay(hour: calendar.component(.hour, from: c.date))
        let pulsed = recipe.mood == .focus || recipe.mood == .brainstorm
        let span = recipe.tempo.upperBound - recipe.tempo.lowerBound
        var p = SoundParameters(mood: recipe.mood, keyOffset: 0,
                                tempo: recipe.tempo.lowerBound + span * time.tempoPosition,
                                breathPeriod: recipe.breathing?.period, density: recipe.density,
                                brightness: recipe.brightness, reverb: recipe.reverb, gains: recipe.gains,
                                texture: .none, master: 0.8, bedColour: recipe.mood == .sleep ? 0 : 1)

        switch time {
        case .morning: p.keyOffset = 2; p.brightness += 0.15
        case .day: break
        case .evening, .night: p.keyOffset = -2; p.brightness -= 0.15
        }

        if let hr = c.heartRate, hr > 0 {
            let resting = (c.restingHeartRate ?? 0) > 0 ? c.restingHeartRate! : 60
            if pulsed {
                let excess = max(0, (hr - resting) / resting)
                p.density *= max(0.4, 1 - excess * 1.5)
            } else if let period = p.breathPeriod {
                p.breathPeriod = period * min(1.3, max(1, hr / (0.9 * resting)))
            }
        }

        p.texture = TextureKind(c.texture, weather: c.weather)
        if p.texture != .none { p.gains[Layer.texture.rawValue] = textureGain }

        if c.recovery == .low { p.tempo *= 0.92; p.brightness -= 0.1 }

        switch c.phase {
        case .work: break
        case .closing(let raw):
            let t = min(1, max(0, raw))
            p.density *= 1 - 0.6 * t
            p.master *= 1 - 0.3 * t
        case .rest:
            p.brightness += 0.1
            p.density *= 0.7
            p.gains[Layer.pulse.rawValue] = 0
        case .fading(let raw):
            let t = min(1, max(0, raw))
            p.master *= cos(t * .pi / 2)
            if t > 0.25 { for layer in [Layer.bell, .pluck, .pulse] { p.gains[layer.rawValue] = 0 } }
            if t > 0.5 { p.gains[Layer.pad.rawValue] = 0 }
            if t > 0.75 { p.gains[Layer.bed.rawValue] = 0; p.gains[Layer.texture.rawValue] = 0 }
            if recipe.mood == .sleep { p.bedColour = t }
        }

        if time == .night, pulsed { p.brightness = min(p.brightness, recipe.brightness - 0.15) }

        func unit(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
        p.density = unit(p.density); p.brightness = unit(p.brightness); p.reverb = unit(p.reverb)
        p.master = unit(p.master); p.bedColour = unit(p.bedColour)
        p.gains = p.gains.clamped(lowerBound: .init(repeating: 0), upperBound: .init(repeating: 1))
        return p
    }
}
