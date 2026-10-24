/// Deterministic PRNG for deals: xoshiro256** seeded through SplitMix64.
///
/// Deals must come out identical from the same seed on every device and OS
/// version, so this does its own bounded sampling and shuffling instead of
/// relying on the standard library's algorithms, which may change.
public struct DealRandom: Sendable {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    public init(seed: UInt64) {
        var sm = seed
        func splitMix() -> UInt64 {
            sm &+= 0x9E37_79B9_7F4A_7C15
            var z = sm
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s = (splitMix(), splitMix(), splitMix(), splitMix())
    }

    public mutating func next() -> UInt64 {
        let result = rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = rotl(s.3, 45)
        return result
    }

    /// A uniform integer in `0..<bound`, using Lemire's multiply-shift with
    /// rejection.
    public mutating func next(below bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        var m = next().multipliedFullWidth(by: b)
        if m.low < b {
            let threshold = (0 &- b) % b
            while m.low < threshold {
                m = next().multipliedFullWidth(by: b)
            }
        }
        return Int(m.high)
    }

    /// Fisher–Yates shuffle.
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, next(below: i + 1))
        }
    }

    private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }
}
