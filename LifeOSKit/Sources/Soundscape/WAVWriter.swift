import Foundation

/// 16-bit stereo PCM, for listening while tuning.
public enum WAVWriter {
    public static func data(left: [Float], right: [Float], sampleRate: Int) -> Data {
        let frames = min(left.count, right.count)
        let bytes = frames * 4
        var d = Data(capacity: 44 + bytes)
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + bytes)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        ascii("data"); u32(UInt32(bytes))
        for i in 0..<frames {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, left[i])) * 32_767)))
            u16(UInt16(bitPattern: Int16(max(-1, min(1, right[i])) * 32_767)))
        }
        return d
    }
}
