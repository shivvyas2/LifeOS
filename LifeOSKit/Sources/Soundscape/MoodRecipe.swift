/// A breathing cycle for the moods without a beat.
public struct Breathing: Equatable, Sendable {
    public var inhale: Double
    public var exhale: Double
    public init(inhale: Double, exhale: Double) { self.inhale = inhale; self.exhale = exhale }
    public var period: Double { inhale + exhale }
}

/// Everything that makes a mood sound like itself, as data.
public struct MoodRecipe: Equatable, Sendable {
    public var mood: Mood
    /// Semitones above the root, within one octave, starting at 0.
    public var scale: [Int]
    /// The key centre before the time of day moves it.
    public var rootMidi: Int
    /// Beats per minute. Unpulsed moods keep a nominal tempo for the clock.
    public var tempo: ClosedRange<Double>
    public var barsPerChord: ClosedRange<Int>
    /// Chords as scale-degree indexes; a degree past the scale's length is
    /// the same degree an octave up.
    public var chords: [[Int]]
    /// Base gain per `Layer`, 0 to 1.
    public var gains: SIMD8<Double>
    public var breathing: Breathing?
    public var density: Double
    public var brightness: Double
    public var reverb: Double

    public static func `for`(_ mood: Mood) -> MoodRecipe {
        switch mood {
        case .focus:
            MoodRecipe(mood: .focus, scale: [0, 2, 4, 7, 9], rootMidi: 55, tempo: 60...72, barsPerChord: 5...9,
                       chords: [[0, 2, 4], [1, 3, 5], [4, 6, 8], [3, 5, 7]],
                       gains: gains(pad: 0.55, bell: 0.25, pulse: 0.30, bed: 0.18),
                       breathing: nil, density: 0.25, brightness: 0.5, reverb: 0.55)
        case .brainstorm:
            MoodRecipe(mood: .brainstorm, scale: [0, 2, 4, 6, 7, 9, 11], rootMidi: 60, tempo: 76...92, barsPerChord: 8...8,
                       chords: [[0, 2, 4, 6], [1, 3, 5, 7], [4, 6, 8, 10], [5, 7, 9, 11]],
                       gains: gains(pad: 0.45, bell: 0.20, pluck: 0.45, pulse: 0.15, bed: 0.08),
                       breathing: nil, density: 0.6, brightness: 0.7, reverb: 0.5)
        case .relax:
            MoodRecipe(mood: .relax, scale: [0, 2, 5, 7, 9], rootMidi: 50, tempo: 50...50, barsPerChord: 3...5,
                       chords: [[0, 1, 3], [0, 2, 3], [1, 3, 4]],
                       gains: gains(pad: 0.55, bell: 0.12, drone: 0.40, bed: 0.20),
                       breathing: Breathing(inhale: 4, exhale: 6), density: 0.12, brightness: 0.4, reverb: 0.8)
        case .sleep:
            MoodRecipe(mood: .sleep, scale: [0, 3, 7, 10], rootMidi: 43, tempo: 40...40, barsPerChord: 8...8,
                       chords: [[0, 2]],
                       gains: gains(pad: 0.30, bell: 0.05, drone: 0.55, bed: 0.30),
                       breathing: Breathing(inhale: 5, exhale: 7), density: 0.05, brightness: 0.2, reverb: 0.85)
        }
    }

    static func gains(pad: Double = 0, bell: Double = 0, pluck: Double = 0, pulse: Double = 0,
                      drone: Double = 0, bed: Double = 0) -> SIMD8<Double> {
        var g = SIMD8<Double>(repeating: 0)
        g[Layer.pad.rawValue] = pad; g[Layer.bell.rawValue] = bell; g[Layer.pluck.rawValue] = pluck
        g[Layer.pulse.rawValue] = pulse; g[Layer.drone.rawValue] = drone; g[Layer.bed.rawValue] = bed
        return g
    }
}
