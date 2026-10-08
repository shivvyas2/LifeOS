/// Freeverb's shape: four damped combs and two all-passes per side, the
/// right side's delays offset for width. Buffers are made once, up front.
struct Comb {
    private var buffer: [Float]
    private var index = 0
    private var store: Float = 0
    init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }
    mutating func process(_ x: Float, feedback: Float, damp: Float) -> Float {
        let y = buffer[index]
        store = y * (1 - damp) + store * damp
        buffer[index] = x + store * feedback
        index += 1; if index == buffer.count { index = 0 }
        return y
    }
}

struct Allpass {
    private var buffer: [Float]
    private var index = 0
    init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }
    mutating func process(_ x: Float) -> Float {
        let b = buffer[index]
        buffer[index] = x + b * 0.5
        index += 1; if index == buffer.count { index = 0 }
        return b - x
    }
}

struct Reverb {
    private var combsL: [Comb]
    private var combsR: [Comb]
    private var allL: [Allpass]
    private var allR: [Allpass]

    init(sampleRate: Double) {
        let scale = sampleRate / 44_100
        func n(_ v: Int) -> Int { Int(Double(v) * scale) }
        combsL = [1116, 1188, 1277, 1356].map { Comb(length: n($0)) }
        combsR = [1116, 1188, 1277, 1356].map { Comb(length: n($0 + 23)) }
        allL = [556, 441].map { Allpass(length: n($0)) }
        allR = [556, 441].map { Allpass(length: n($0 + 23)) }
    }

    /// `size` 0 to 1 sets the room; returns the wet signal only.
    mutating func process(_ l: Float, _ r: Float, size: Float) -> (Float, Float) {
        let input = (l + r) * 0.1
        let feedback = 0.7 + 0.14 * size
        var outL: Float = 0, outR: Float = 0
        for k in 0..<4 {
            outL += combsL[k].process(input, feedback: feedback, damp: 0.3)
            outR += combsR[k].process(input, feedback: feedback, damp: 0.3)
        }
        for k in 0..<2 { outL = allL[k].process(outL); outR = allR[k].process(outR) }
        return (outL * 0.5, outR * 0.5)
    }
}
