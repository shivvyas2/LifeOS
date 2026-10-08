import Foundation

/// One sounding note. Plain stored values only, so the voice pool is a flat
/// buffer the audio thread can walk without reference counting.
struct Voice {
    static let pluckSlotLength = 2048

    var active = false
    var layer: Layer = .pad
    var level = 0.0
    var velocity = 0.0
    var freq = 0.0
    var pan = 0.5
    private var age = 0
    private var attackSamples = 1
    private var holdSamples = 0
    private var releaseCoef = 0.999
    private var phases = SIMD4<Double>(repeating: 0)
    private var detune = SIMD4<Double>(1, 1, 1, 1)
    private var lp1 = 0.0
    private var lp2 = 0.0
    private var pluckSlot = 0
    private var pluckLength = 0
    private var pluckPos = 0

    static func frequency(midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    mutating func start(_ event: NoteEvent, sampleRate sr: Double, breathing: Bool, pluckSlot slot: Int,
                        pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank) {
        active = true
        layer = event.layer
        velocity = event.velocity
        freq = Self.frequency(midi: Double(event.midi))
        pan = 0.5 + 0.35 * sin(Double(event.midi) * 1.7)
        age = 0; level = 0; lp1 = 0; lp2 = 0
        phases = SIMD4(noise.white() * 0.5 + 0.5, noise.white() * 0.5 + 0.5, noise.white() * 0.5 + 0.5, 0)
        let attack: Double, release: Double
        switch event.layer {
        case .pad: (attack, release) = (breathing ? 4 : 3, 2)
        case .drone: (attack, release) = (6, 3)
        case .bell: (attack, release) = (0.004, 0.9)
        case .pluck: (attack, release) = (0.002, 1.2)
        case .pulse: (attack, release) = (0.002, 0.12)
        case .bed, .texture: (attack, release) = (1, 1)
        }
        attackSamples = max(1, Int(attack * sr))
        holdSamples = Int(max(0, event.duration) * sr)
        releaseCoef = exp(-1 / (release * sr))
        detune = SIMD4(pow(2, -7.0 / 1200), 1, pow(2, 7.0 / 1200), 1)
        if layer == .pluck {
            pluckSlot = slot
            pluckLength = min(Self.pluckSlotLength, max(2, Int(sr / freq)))
            pluckPos = 0
            let base = pluckBuffers + slot * Self.pluckSlotLength
            var smooth = 0.0
            for k in 0..<pluckLength {
                smooth += (noise.white() - smooth) * 0.5
                base[k] = Float(smooth)
            }
        }
    }

    mutating func sample(sampleRate sr: Double, padCoef: Double, brightness: Double,
                         pluckBuffers: UnsafeMutablePointer<Float>, noise: inout NoiseBank) -> Double {
        guard active else { return 0 }
        if age < attackSamples {
            level = Double(age) / Double(attackSamples)
        } else if age < attackSamples + holdSamples {
            level = 1
        } else {
            level *= releaseCoef
            if level < 0.001 { active = false; return 0 }
        }
        age += 1
        let tau = 2 * Double.pi
        switch layer {
        case .pad:
            var s = 0.0
            for k in 0..<3 {
                phases[k] += freq * detune[k] / sr
                if phases[k] >= 1 { phases[k] -= 1 }
                s += 2 * phases[k] - 1
            }
            lp1 += padCoef * (s / 3 - lp1)
            lp2 += padCoef * (lp1 - lp2)
            return lp2 * 1.6 * level * velocity
        case .drone:
            phases[0] += freq / sr; if phases[0] >= 1 { phases[0] -= 1 }
            phases[1] += freq * 1.5 / sr; if phases[1] >= 1 { phases[1] -= 1 }
            return (sin(tau * phases[0]) + 0.3 * sin(tau * phases[1])) * 0.75 * level * velocity
        case .bell:
            phases[0] += freq / sr; if phases[0] >= 1 { phases[0] -= 1 }
            phases[1] += freq * 3.5 / sr; if phases[1] >= 1 { phases[1] -= 1 }
            let index = (0.5 + 2.5 * brightness) * level
            return sin(tau * phases[0] + index * sin(tau * phases[1])) * level * velocity
        case .pluck:
            let base = pluckBuffers + pluckSlot * Self.pluckSlotLength
            let next = pluckPos + 1 == pluckLength ? 0 : pluckPos + 1
            let out = Double(base[pluckPos])
            base[pluckPos] = Float(0.996 * 0.5 * (out + Double(base[next])))
            pluckPos = next
            return out * 1.4 * level * velocity
        case .pulse:
            let drop = 1 + exp(-Double(age) / (0.01 * sr))
            phases[0] += freq * drop / sr; if phases[0] >= 1 { phases[0] -= 1 }
            var s = sin(tau * phases[0])
            if Double(age) < 0.002 * sr { s += noise.white() * 0.3 }
            return s * level * velocity
        case .bed, .texture:
            return 0
        }
    }
}
