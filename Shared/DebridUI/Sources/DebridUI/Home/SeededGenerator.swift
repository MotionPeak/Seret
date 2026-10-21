import Foundation

/// A random number generator that gives the same sequence for the same seed, on every launch and
/// every device — SplitMix64 over an FNV-1a hash of the seed string.
///
/// Not `hashValue`: Swift randomises string hashing per process, so a shuffle seeded from it would
/// reorder the row every launch instead of once a day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = Self.stableHash(seed)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// FNV-1a, 64-bit, over the UTF-8 bytes.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
