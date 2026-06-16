//
//  SeededGenerator.swift
//  SnoozeQuest
//

import Foundation

/// Deterministic PRNG so mock data is stable across app launches and previews.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
