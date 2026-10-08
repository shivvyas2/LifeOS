import Foundation

/// Every noise the soundscape uses, left and right drawn separately so the
/// beds are wide. A xorshift generator: no allocation, no locks.
struct NoiseBank {
    private typealias Drop = (freq: Double, phase: Double, amp: Double)
    private typealias Band = (low: Double, band: Double)

    private var state: UInt32
    private var pinkL = SIMD3<Double>(repeating: 0)
    private var pinkR = SIMD3<Double>(repeating: 0)
    private var brownL = 0.0
    private var brownR = 0.0
    private var rainLowL = 0.0
    private var rainLowR = 0.0
    private var rainWander = 0.85
    private var dropL: Drop = (0, 0, 0)
    private var dropR: Drop = (0, 0, 0)
    private var windL: Band = (0, 0)
    private var windR: Band = (0, 0)
    private var windPhase = 0.0
    private var hissLowL = 0.0
    private var hissLowR = 0.0

    init(seed: UInt32 = 0x1234_5678) { state = seed == 0 ? 1 : seed }

    mutating func white() -> Double {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }

    private mutating func pinkSample(_ b: inout SIMD3<Double>) -> Double {
        let w = white()
        b[0] = 0.99765 * b[0] + w * 0.0990460
        b[1] = 0.96300 * b[1] + w * 0.2965164
        b[2] = 0.57000 * b[2] + w * 1.0526913
        return (b[0] + b[1] + b[2] + w * 0.1848) * 0.11
    }

    private mutating func brownSample(_ x: inout Double) -> Double {
        x = (x + 0.02 * white()) / 1.02
        return x * 3.5
    }

    /// The bed under every mood: 0 is pink, 1 is brown.
    mutating func bed(colour: Double) -> (Double, Double) {
        var pinks = (pinkL, pinkR), browns = (brownL, brownR)
        let pl = pinkSample(&pinks.0), pr = pinkSample(&pinks.1)
        let bl = brownSample(&browns.0), br = brownSample(&browns.1)
        (pinkL, pinkR) = pinks; (brownL, brownR) = browns
        return (pl + (bl - pl) * colour, pr + (br - pr) * colour)
    }

    mutating func texture(_ kind: TextureKind, sampleRate sr: Double) -> (Double, Double) {
        switch kind {
        case .none: return (0, 0)
        case .brown:
            var browns = (brownL, brownR)
            let out = (brownSample(&browns.0), brownSample(&browns.1))
            (brownL, brownR) = browns
            return out
        case .hiss:
            let a = 1 - exp(-2 * .pi * 3000 / sr)
            let wl = white(), wr = white()
            hissLowL += a * (wl - hissLowL); hissLowR += a * (wr - hissLowR)
            return ((wl - hissLowL) * 0.25, (wr - hissLowR) * 0.25)
        case .rain:
            rainWander = min(1, max(0.7, rainWander + white() * 0.0005))
            let a = 1 - exp(-2 * .pi * 1500 / sr)
            let wl = white(), wr = white()
            rainLowL += a * (wl - rainLowL); rainLowR += a * (wr - rainLowR)
            var drops = (dropL, dropR)
            let l = (wl - rainLowL) * 0.5 * rainWander + dropSample(&drops.0, sr: sr)
            let r = (wr - rainLowR) * 0.5 * rainWander + dropSample(&drops.1, sr: sr)
            (dropL, dropR) = drops
            return (l, r)
        case .wind:
            windPhase += 0.05 / sr
            if windPhase >= 1 { windPhase -= 1 }
            let swell = 0.6 + 0.4 * sin(2 * .pi * windPhase * 0.7)
            var bands = (windL, windR)
            let l = windSample(&bands.0, centre: 300 + 900 * (0.5 + 0.5 * sin(2 * .pi * windPhase)), sr: sr)
            let r = windSample(&bands.1, centre: 300 + 900 * (0.5 + 0.5 * cos(2 * .pi * windPhase)), sr: sr)
            (windL, windR) = bands
            return (l * swell, r * swell)
        }
    }

    /// A single raindrop at a time per side: a short, bright, decaying ping.
    private mutating func dropSample(_ d: inout Drop, sr: Double) -> Double {
        if d.amp < 1e-4, (white() + 1) / 2 < 25 / sr {
            d.freq = 2000 + (white() + 1) * 1500
            d.amp = 0.05 + (white() + 1) * 0.075
            d.phase = 0
        }
        guard d.amp >= 1e-4 else { return 0 }
        d.phase += d.freq / sr
        if d.phase >= 1 { d.phase -= 1 }
        let out = sin(2 * .pi * d.phase) * d.amp
        d.amp *= exp(-1 / (0.008 * sr))
        return out
    }

    /// State-variable band-pass, Q about 2.
    private mutating func windSample(_ s: inout Band, centre: Double, sr: Double) -> Double {
        let f = 2 * sin(.pi * min(centre, sr / 6) / sr)
        let q = 0.5
        let high = white() - s.low - q * s.band
        s.band += f * high
        s.low += f * s.band
        return s.band * 0.6
    }
}
