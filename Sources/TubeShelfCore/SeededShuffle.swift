import Foundation

/// Deterministic shuffle. The same seed always produces the same order, so a
/// paginated grid does not reshuffle on every render; a new click means a new
/// seed.
public enum SeededShuffle {
    public static func shuffle<T>(_ items: [T], seed: UInt64) -> [T] {
        guard items.count > 1 else { return items }
        var generator = SplitMix64(seed: seed)
        var result = items

        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let pick = Int(generator.next() % UInt64(index + 1))
            result.swapAt(index, pick)
        }
        return result
    }
}

/// Small, fast, seedable generator. Not cryptographic — only used for ordering.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
