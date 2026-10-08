/// SplitMix64: tiny, fast, and the same everywhere, so a seed always
/// writes the same piece.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct NoteEvent: Equatable, Sendable {
    public var layer: Layer
    public var midi: Int
    public var velocity: Double
    /// Seconds from the start of the bar.
    public var offset: Double
    /// Seconds held; 0 for the struck layers, which decay on their own.
    public var duration: Double
    public init(layer: Layer, midi: Int, velocity: Double, offset: Double, duration: Double) {
        self.layer = layer; self.midi = midi; self.velocity = velocity; self.offset = offset; self.duration = duration
    }
}

/// Writes one bar at a time from a recipe. Runs on the audio thread at bar
/// boundaries, so it only appends into the caller's reserved buffer.
public struct Composer: Sendable {
    public let recipe: MoodRecipe
    private var rng: SeededGenerator
    public private(set) var chordIndex = 0
    public private(set) var barNumber = 0
    private var barsLeftInChord = 0
    /// The key is latched at each chord change so a time-of-day shift never
    /// lands in the middle of a held chord.
    private var chordKey = 0
    private var pluckDegree = 0

    public init(recipe: MoodRecipe, seed: UInt64) {
        self.recipe = recipe
        self.rng = SeededGenerator(seed: seed)
    }

    public func midi(degree: Int, keyOffset: Int) -> Int {
        let n = recipe.scale.count
        let octave = degree >= 0 ? degree / n : (degree - n + 1) / n
        let step = degree - octave * n
        // Fold by octaves, never clamp, so a note always stays in the scale.
        var note = recipe.rootMidi + keyOffset + octave * 12 + recipe.scale[step]
        while note > 100 { note -= 12 }
        while note < 24 { note += 12 }
        return note
    }

    public mutating func nextBar(_ p: SoundParameters, into events: inout [NoteEvent]) {
        events.removeAll(keepingCapacity: true)
        let bar = p.barSeconds
        let beat = bar / 4
        let n = recipe.scale.count

        if barsLeftInChord == 0 {
            if barNumber > 0, recipe.chords.count > 1 {
                var next = Int.random(in: 0..<(recipe.chords.count - 1), using: &rng)
                if next >= chordIndex { next += 1 }
                chordIndex = next
            }
            chordKey = p.keyOffset
            barsLeftInChord = Int.random(in: recipe.barsPerChord, using: &rng)
            let held = Double(barsLeftInChord) * bar + 1.5
            if p.gains[Layer.pad.rawValue] > 0 {
                for degree in recipe.chords[chordIndex] {
                    events.append(NoteEvent(layer: .pad, midi: midi(degree: degree, keyOffset: chordKey),
                                            velocity: 0.6, offset: 0, duration: held))
                }
            }
            if p.gains[Layer.drone.rawValue] > 0 {
                events.append(NoteEvent(layer: .drone, midi: midi(degree: recipe.chords[chordIndex][0], keyOffset: chordKey) - 12,
                                        velocity: 0.7, offset: 0, duration: held))
            }
        }
        barsLeftInChord -= 1
        barNumber += 1

        if p.gains[Layer.pulse.rawValue] > 0, p.breathPeriod == nil {
            let root = midi(degree: 0, keyOffset: chordKey) - 12
            for b in 0..<4 {
                events.append(NoteEvent(layer: .pulse, midi: root, velocity: b == 0 ? 0.7 : 0.45,
                                        offset: Double(b) * beat, duration: 0))
            }
        }

        if p.gains[Layer.bell.rawValue] > 0, Double.random(in: 0..<1, using: &rng) < min(1, p.density * 1.5) {
            let chord = recipe.chords[chordIndex]
            let degree = chord[Int.random(in: 0..<chord.count, using: &rng)] + n
            events.append(NoteEvent(layer: .bell, midi: midi(degree: degree, keyOffset: chordKey), velocity: 0.5,
                                    offset: Double(Int.random(in: 0..<4, using: &rng)) * beat, duration: 0))
        }

        if p.gains[Layer.pluck.rawValue] > 0 {
            for slot in 0..<8 where Double.random(in: 0..<1, using: &rng) < p.density * 0.8 {
                pluckDegree = min(max(pluckDegree + Int.random(in: -2...2, using: &rng), 0), n)
                let swing = slot % 2 == 1 ? beat * 0.08 : 0
                events.append(NoteEvent(layer: .pluck, midi: midi(degree: pluckDegree + n, keyOffset: chordKey),
                                        velocity: slot % 2 == 0 ? 0.55 : 0.4,
                                        offset: Double(slot) * beat / 2 + swing, duration: 0))
            }
            if recipe.mood == .brainstorm, p.gains[Layer.bell.rawValue] > 0,
               Double.random(in: 0..<1, using: &rng) < 0.08 {
                let chord = recipe.chords[chordIndex]
                events.append(NoteEvent(layer: .bell, midi: midi(degree: chord[0] + 2 * n, keyOffset: chordKey),
                                        velocity: 0.35, offset: Double(Int.random(in: 0..<8, using: &rng)) * beat / 2,
                                        duration: 0))
            }
        }

        // Insertion sort: in place, no allocation, and the lists are short.
        if events.count > 1 {
            for i in 1..<events.count {
                let item = events[i]
                var j = i - 1
                while j >= 0, events[j].offset > item.offset { events[j + 1] = events[j]; j -= 1 }
                events[j + 1] = item
            }
        }
    }
}
